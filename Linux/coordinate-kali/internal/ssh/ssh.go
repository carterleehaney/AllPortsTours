package ssh

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	"io"
	"net"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"sync"
	"time"

	"github.com/bramvdbogaerde/go-scp"
	"github.com/melbahja/goph"

	. "github.com/LByrgeCP/coordinate-kali/internal/config"
	. "github.com/LByrgeCP/coordinate-kali/internal/globals"
	"github.com/LByrgeCP/coordinate-kali/internal/logger"
	"github.com/LByrgeCP/coordinate-kali/internal/utils"
)

func SsherWrapper(i Instance, client *goph.Client) {
	logger.Debug(fmt.Sprintf("Starting SsherWrapper for instance: %+v", i))
	var wg sync.WaitGroup

	// Resolve hostname early so downloads can use it for directory names
	if i.Hostname == "" {
		output, err := client.Run("hostname")
		if err != nil {
			output, err = client.Run("cat /etc/hostname")
		}
		if err == nil && !strings.Contains(string(output), "No such file or directory") {
			i.Hostname = strings.TrimSpace(string(output))
		} else {
			i.Hostname = i.IP
		}
		logger.Debug(fmt.Sprintf("Resolved hostname early: %s", i.Hostname))
	}

	// Upload local files/dirs if -F flags were specified
	if len(*UploadFiles) > 0 {
		logger.Debug(fmt.Sprintf("Upload files requested: %v", *UploadFiles))
		UploadToRemote(i, client)
	}

	// Download remote directories if -D flags were specified
	if len(*DownloadDirs) > 0 {
		logger.Debug(fmt.Sprintf("Download directories requested: %v", *DownloadDirs))
		DownloadRemoteDirs(i, client)
	}

	// Save credentials to config when --config-only is set
	if *ConfigOnly != "" {
		logger.Debug(fmt.Sprintf("ConfigOnly: saving credentials for %s (user: %s)", i.IP, i.Username))
		UpdateEntry(ConfigEntry{IP: i.IP, Username: i.Username, Password: *ConfigOnly})
	}

	// If only uploading/downloading (no scripts or commands), we're done
	if len(Commands) == 0 && len(Scripts) == 0 {
		TotalRuns++
		return
	}

	// Handle direct commands if specified
	if len(Commands) > 0 {
		logger.Debug("Executing direct commands instead of scripts")
		for _, command := range Commands {
			logger.Debug(fmt.Sprintf("Processing command: %s", command))
			i.Script = fmt.Sprintf("command: %s", command) // For logging purposes

			// Build full command with environment variables
			var fullCommand string
			for _, cmd := range EnvironCmds {
				fullCommand += fmt.Sprintf("%s ", cmd)
			}
			fullCommand += command

			wg.Add(1)
			go ssherCommand(i, client, fullCommand, &wg)
			i.ID++
		}
		wg.Wait()
		logger.Debug("Finished executing all commands in SsherWrapper.")
		return
	}

	// Handle scripts (existing logic)
	first := true
	for _, path := range Scripts {
		logger.Debug(fmt.Sprintf("Processing script path: %s", path))
		var Script string
		i.Script = path

		ScriptContents, err := os.ReadFile(path)
		if err != nil {
			logger.Crit(i, errors.New("Error reading "+i.Script+": "+err.Error()))
			continue
		}
		for _, cmd := range EnvironCmds {
			Script += fmt.Sprintf("%s ", cmd)
		}
		Script += string(ScriptContents)

		for t := 0; t < *Threads && t < len(Scripts); t++ {
			if first {
				logger.Debug("Launching first thread for script execution.")
				first = false
			}
			wg.Add(1)
			go ssher(i, client, Script, &wg)
			i.ID++
		}
	}

	wg.Wait()
	logger.Debug("Finished executing all threads in SsherWrapper.")
}

func ssherCommand(i Instance, client *goph.Client, command string, wg *sync.WaitGroup) {
	defer wg.Done()

	logger.Debug(fmt.Sprintf("Starting ssherCommand for instance: %+v with command: %s", i, command))

	// Test SSH connection validity
	output, err := client.Run("echo a ; asdfhasdf")
	if len(output) == 0 {
		logger.Err(fmt.Sprintf("%s: Couldn't read stdout. Coordinate does not work with this host's shell probably\n", i.IP))
		BrokenHosts = append(BrokenHosts, i.IP)
		return
	}

	elevated := true
	if i.Username != "root" {
		elevated = false
		logger.Debug(fmt.Sprintf("User '%s' is not root.", i.Username))
		if *Sudo {
			logger.Debug("Sudo is enabled. Attempting privilege escalation.")
			if escalateSudo(i, client) {
				elevated = true
				logger.InfoExtra(i, "Privilege escalation succeeded.")
			} else {
				logger.InfoExtra(i, "Privilege escalation failed.")
			}
		} else {
			logger.InfoExtra(i, "Not root, not sudoing. Proceeding with user.")
		}
	}

	// Get hostname for logging
	name := "hostname"
	output, err = client.Run(name)
	if err != nil {
		logger.Debug("Hostname command failed, attempting 'cat /etc/hostname'")
		name = "cat /etc/hostname"
		output, err = client.Run(name)
	}
	stroutput := string(output)
	if !strings.Contains(stroutput, "No such file or directory") {
		i.Hostname = strings.TrimSpace(stroutput)
		logger.Debug(fmt.Sprintf("Resolved hostname: %s", i.Hostname))
	} else {
		i.Hostname = i.IP
		logger.Debug("No hostname found.")
	}

	// Update output file path with placeholders
	i.Outfile = strings.Replace(i.Outfile, "%i%", i.IP, -1)
	i.Outfile = strings.Replace(i.Outfile, "%h%", i.Hostname, -1)
	i.Outfile = strings.Replace(i.Outfile, "%s%", "command", -1) // Use "command" as script name replacement

	logger.Debug(fmt.Sprintf("Resolved output file path: %s", i.Outfile))

	// Execute command with timeout
	ctx, cancel := context.WithTimeout(context.Background(), Timeout)
	defer cancel()

	var execCommand string
	if elevated || !*Sudo {
		execCommand = command
	} else {
		execCommand = fmt.Sprintf("echo \"%s\" | sudo -S bash -c '%s'", i.Password, command)
	}
	logger.Debug(fmt.Sprintf("Executing command: %s", execCommand))

	output, err = client.RunContext(ctx, execCommand)
	stroutput = string(output)

	if err != nil {
		if strings.Contains(err.Error(), "context deadline exceeded") {
			if len(i.Hostname) > 0 {
				AnnoyingErrs = append(AnnoyingErrs, fmt.Sprintf("Command timed out on %s", i.Hostname))
			} else {
				AnnoyingErrs = append(AnnoyingErrs, fmt.Sprintf("Command timed out on %s", i.IP))
			}
		} else {
			logger.Err(fmt.Sprintf("%s: Error running command: %s\n", i.IP, err))
		}
	}

	if len(stroutput) > 0 {
		logger.Stdout(i, stroutput)
		if *CreateConfig != "" {
			for _, line := range strings.Split(stroutput, "\n") {
				parts := strings.Split(line, ",")
				if len(parts) < 2 || parts[0] != "root" {
					continue
				}
				Password := parts[1]
				UpdateEntry(ConfigEntry{IP: i.IP, Username: "root", Password: Password})
			}
		}
	}

	TotalRuns++
	logger.Debug(fmt.Sprintf("Total runs incremented: %d", TotalRuns))
}

func ssher(i Instance, client *goph.Client, script string, wg *sync.WaitGroup) {
	defer wg.Done()

	logger.Debug(fmt.Sprintf("Starting ssher for instance: %+v with script length: %d", i, len(script)))

	filename := fmt.Sprintf("%s/%s", *TmpDir, utils.GenerateRandomFileName(16))
	remoteFilename := fmt.Sprintf("/tmp/%s", utils.GenerateRandomFileName(16))
	logger.Debug(fmt.Sprintf("Generated temporary filename: %s", filename))

	output, err := client.Run("echo a ; asdfhasdf")
	if len(output) == 0 {
		logger.Err(fmt.Sprintf("%s: Couldn't read stdout. Coordinate does not work with this host's shell probably\n", i.IP))
		BrokenHosts = append(BrokenHosts, i.IP)
		return
	}

	elevated := true
	if i.Username != "root" {
		elevated = false
		logger.Debug(fmt.Sprintf("User '%s' is not root.", i.Username))
		if *Sudo {
			logger.Debug("Sudo is enabled. Attempting privilege escalation.")
			if escalateSudo(i, client) {
				elevated = true
				logger.InfoExtra(i, "Privilege escalation succeeded.")
			} else {
				logger.InfoExtra(i, "Privilege escalation failed.")
			}
		} else {
			logger.InfoExtra(i, "Not root, not sudoing. Proceeding with user.")
		}
	}

	name := "hostname"
	output, err = client.Run(name)
	if err != nil {
		logger.Debug("Hostname command failed, attempting 'cat /etc/hostname'")
		name = "cat /etc/hostname"
		output, err = client.Run(name)
	}
	stroutput := string(output)
	if !strings.Contains(stroutput, "No such file or directory") {
		i.Hostname = strings.TrimSpace(stroutput)
		logger.Debug(fmt.Sprintf("Resolved hostname: %s", i.Hostname))
	} else {
		i.Hostname = i.IP
		logger.Debug("No hostname found.")
	}

	i.Outfile = strings.Replace(i.Outfile, "%i%", i.IP, -1)
	i.Outfile = strings.Replace(i.Outfile, "%h%", i.Hostname, -1)
	i.Outfile = strings.Replace(i.Outfile, "%s%", strings.TrimSuffix(i.Script, ".sh"), -1)

	logger.Debug(fmt.Sprintf("Resolved output file path: %s", i.Outfile))

	err = os.WriteFile(filename, []byte(script), 0644)
	if err != nil {
		logger.Err(fmt.Sprintf("Error writing to temporary file: %s", filename))
		return
	}
	logger.Debug(fmt.Sprintf("Script written to temporary file: %s", filename))

	logger.Debug(fmt.Sprintf("Converting to unix endings: %s", filename))
	err = utils.Dos2unix(filename)
	if err != nil {
		logger.Err(fmt.Sprintf("Error converting file to unix endings: %s", err))
	}

	err = Upload(client, filename, remoteFilename)
	if err != nil {
		logger.ErrExtra(i, err)
		os.Remove(filename)
		return
	}

	ctx, cancel := context.WithTimeout(context.Background(), Timeout)
	defer cancel()

	var command string
	if elevated || !*Sudo {
		command = fmt.Sprintf("%s ; rm %s", remoteFilename, remoteFilename)
	} else {
		command = fmt.Sprintf("echo \"%s\" | sudo -S %s; sudo rm %s", i.Password, remoteFilename, remoteFilename)
	}
	logger.Debug(fmt.Sprintf("Executing command: %s", command))

	output, err = client.RunContext(ctx, command)
	stroutput = string(output)

	if err != nil {
		if strings.Contains(err.Error(), "context deadline exceeded") {
			if len(i.Hostname) > 0 {
				AnnoyingErrs = append(AnnoyingErrs, fmt.Sprintf("%s timed out on %s", i.Script, i.Hostname))
			} else {
				AnnoyingErrs = append(AnnoyingErrs, fmt.Sprintf("%s timed out on %s", i.Script, i.IP))
			}
		} else {
			logger.Err(fmt.Sprintf("%s: Error running script: %s\n", i.IP, err))
		}
	}
	if len(stroutput) > 0 {
		logger.Stdout(i, stroutput)
		if *CreateConfig != "" {
			for _, line := range strings.Split(stroutput, "\n") {
				parts := strings.Split(line, ",")
				if len(parts) < 2 || parts[0] != "root" {
					continue
				}
				Password := parts[1]
				UpdateEntry(ConfigEntry{IP: i.IP, Username: "root", Password: Password})
			}
		}
	}
	os.Remove(filename)
	logger.Debug(fmt.Sprintf("Removed temporary file: %s", filename))

	TotalRuns++
	logger.Debug(fmt.Sprintf("Total runs incremented: %d", TotalRuns))
}

// UploadToRemote uploads local files/directories to remote hosts.
// Uses streaming tar over SSH stdin — no temp files, no SCP binary needed on remote.
// Format: -F "local_path;remote_path"
func UploadToRemote(i Instance, client *goph.Client) {
	var wg sync.WaitGroup
	for _, entry := range *UploadFiles {
		entry = strings.TrimSpace(entry)
		if entry == "" {
			continue
		}

		wg.Add(1)
		go func(entry string) {
			defer wg.Done()
			uploadSingleEntry(i, client, entry)
		}(entry)
	}
	wg.Wait()
}

func uploadSingleEntry(i Instance, client *goph.Client, entry string) {
	// Parse local;remote syntax
	parts := strings.SplitN(entry, ";", 2)
	if len(parts) != 2 || strings.TrimSpace(parts[0]) == "" || strings.TrimSpace(parts[1]) == "" {
		logger.ErrExtra(i, fmt.Sprintf("Invalid upload format '%s' — use 'local_path;remote_path'", entry))
		return
	}
	localPath := strings.TrimSpace(parts[0])
	remotePath := strings.TrimSpace(parts[1])

	// Check local path exists
	info, err := os.Stat(localPath)
	if err != nil {
		logger.ErrExtra(i, fmt.Sprintf("Local path '%s' not found: %s", localPath, err))
		return
	}

	logger.InfoExtra(i, fmt.Sprintf("Uploading %s -> %s (streaming)", localPath, remotePath))

	if info.IsDir() {
		err = streamUploadDir(client, localPath, remotePath)
	} else {
		err = streamUploadFile(client, localPath, remotePath)
	}

	if err != nil {
		logger.ErrExtra(i, fmt.Sprintf("Failed to upload '%s': %s", localPath, err))
	} else {
		logger.InfoExtra(i, fmt.Sprintf("Successfully uploaded %s -> %s", localPath, remotePath))
	}
}

// streamUploadDir tars a local directory and streams it over SSH stdin to extract on remote.
// One pipe, no temp files on either side.
func streamUploadDir(client *goph.Client, localDir string, remotePath string) error {
	session, err := client.NewSession()
	if err != nil {
		return fmt.Errorf("failed to create session: %w", err)
	}
	defer session.Close()

	stdin, err := session.StdinPipe()
	if err != nil {
		return fmt.Errorf("failed to get stdin pipe: %w", err)
	}

	// Remote: create destination and extract tar from stdin
	remoteCmd := fmt.Sprintf("mkdir -p %s && tar xf - -C %s", remotePath, remotePath)
	if err := session.Start(remoteCmd); err != nil {
		return fmt.Errorf("failed to start remote extract: %w", err)
	}

	// Local: tar the directory and write to SSH stdin
	writeErr := utils.WriteTarToWriter(localDir, stdin)
	stdin.Close() // Signal EOF to remote tar

	sessionErr := session.Wait()

	if writeErr != nil {
		return fmt.Errorf("local tar error: %w", writeErr)
	}
	if sessionErr != nil {
		return fmt.Errorf("remote extract error: %w", sessionErr)
	}
	return nil
}

// streamUploadFile streams a single file over SSH stdin using cat.
// Faster than SCP for single files — no protocol overhead.
func streamUploadFile(client *goph.Client, localFile string, remotePath string) error {
	session, err := client.NewSession()
	if err != nil {
		return fmt.Errorf("failed to create session: %w", err)
	}
	defer session.Close()

	stdin, err := session.StdinPipe()
	if err != nil {
		return fmt.Errorf("failed to get stdin pipe: %w", err)
	}

	// Get local file info for permissions
	info, err := os.Stat(localFile)
	if err != nil {
		return fmt.Errorf("failed to stat local file: %w", err)
	}

	// Remote: preserve executable bit
	perm := "644"
	if info.Mode()&0111 != 0 {
		perm = "755"
	}

	// Let the remote shell figure out if dest is a directory.
	// If /root is a dir → writes to /root/meow. If /root/meow is a path → writes there.
	localName := filepath.Base(localFile)
	remoteCmd := fmt.Sprintf(
		"d='%s'; n='%s'; if [ -d \"$d\" ]; then d=\"$d/$n\"; fi; mkdir -p \"$(dirname \"$d\")\" && cat > \"$d\" && chmod %s \"$d\"",
		remotePath, localName, perm)
	if err := session.Start(remoteCmd); err != nil {
		return fmt.Errorf("failed to start remote write: %w", err)
	}

	// Stream local file to SSH stdin
	f, err := os.Open(localFile)
	if err != nil {
		stdin.Close()
		return fmt.Errorf("failed to open local file: %w", err)
	}

	_, copyErr := io.Copy(stdin, f)
	f.Close()
	stdin.Close()

	sessionErr := session.Wait()

	if copyErr != nil {
		return fmt.Errorf("stream error: %w", copyErr)
	}
	if sessionErr != nil {
		return fmt.Errorf("remote write error: %w", sessionErr)
	}
	return nil
}

// probeRemote checks what archiving tools exist on the remote. Called once per
// host so we never waste time on fallback methods we know will fail.
func probeRemote(client *goph.Client) (hasTar, hasGzip bool) {
	out, err := client.Run("command -v tar >/dev/null 2>&1 && echo TAR; command -v gzip >/dev/null 2>&1 && echo GZIP")
	if err != nil {
		// 'command' builtin may not exist (old sh); try 'which'
		out, _ = client.Run("which tar >/dev/null 2>&1 && echo TAR; which gzip >/dev/null 2>&1 && echo GZIP")
	}
	s := string(out)
	hasTar = strings.Contains(s, "TAR")
	hasGzip = strings.Contains(s, "GZIP")
	return
}

func DownloadRemoteDirs(i Instance, client *goph.Client) {
	hostname := i.IP
	if i.Hostname != "" {
		hostname = i.Hostname
	}
	localBase := filepath.Join("output", "downloads", hostname)
	if err := os.MkdirAll(localBase, 0755); err != nil {
		logger.ErrExtra(i, fmt.Sprintf("Failed to create local download dir: %s", err))
		return
	}

	// Probe remote capabilities once — avoids repeated failed fallback attempts
	hasTar, hasGzip := probeRemote(client)
	logger.Debug(fmt.Sprintf("Remote probe %s: tar=%v gzip=%v", i.IP, hasTar, hasGzip))

	if !hasTar {
		// No tar on remote — SFTP per entry (rare: all target OSes have tar)
		logger.InfoExtra(i, "No tar on remote, falling back to SFTP per entry")
		var wg sync.WaitGroup
		for _, entry := range *DownloadDirs {
			entry = strings.TrimSpace(entry)
			if entry == "" {
				continue
			}
			wg.Add(1)
			go func(e string) {
				defer wg.Done()
				remote, extractDir := parseDownloadEntry(e, localBase)
				downloadFallbackSFTP(i, client, remote, extractDir)
			}(entry)
		}
		wg.Wait()
		return
	}

	// Partition: entries with ";" use the explicit local dest.
	// Entries without ";" use the basename of the remote path as local subdir.
	type customEntry struct{ remote, extractDir string }
	var customs []customEntry

	for _, entry := range *DownloadDirs {
		entry = strings.TrimSpace(entry)
		if entry == "" {
			continue
		}
		if idx := strings.Index(entry, ";"); idx != -1 {
			remote := strings.TrimSpace(entry[:idx])
			localDest := strings.TrimSpace(entry[idx+1:])
			var ed string
			if filepath.IsAbs(localDest) {
				ed = localDest
			} else {
				ed = filepath.Join(localBase, localDest)
			}
			os.MkdirAll(ed, 0755)
			customs = append(customs, customEntry{remote, ed})
		} else {
			// Default: extract into localBase directly.
			// The tar entries already start with the basename (e.g. "backups/...")
			// so extraction naturally creates output/downloads/{hostname}/backups/
			customs = append(customs, customEntry{entry, localBase})
		}
	}

	// Download all entries concurrently, one stream each
	if len(customs) > 0 {
		var wg sync.WaitGroup
		for _, ce := range customs {
			wg.Add(1)
			go func(remote, extractDir string) {
				defer wg.Done()
				downloadSingleStream(i, client, remote, extractDir, hasGzip)
			}(ce.remote, ce.extractDir)
		}
		wg.Wait()
	}
}

// parseDownloadEntry splits "remote;local" and resolves the local extraction dir.
func parseDownloadEntry(entry string, localBase string) (remotePath, extractDir string) {
	remotePath = strings.TrimSpace(entry)
	if idx := strings.Index(entry, ";"); idx != -1 {
		remotePath = strings.TrimSpace(entry[:idx])
		localDest := strings.TrimSpace(entry[idx+1:])
		if filepath.IsAbs(localDest) {
			extractDir = localDest
		} else {
			extractDir = filepath.Join(localBase, localDest)
		}
	} else {
		extractDir = localBase
	}
	os.MkdirAll(extractDir, 0755)
	return
}

// batchFallbackIndividual streams each path one-by-one when the batch tar fails.
// downloadSingleStream downloads one remote path via streaming tar.
// Skips methods known unavailable from probe — no wasted attempts.
func downloadSingleStream(i Instance, client *goph.Client, remotePath string, extractDir string, hasGzip bool) {
	cleanPath := strings.TrimRight(strings.TrimSpace(remotePath), "/")
	parentDir := filepath.Dir(cleanPath)
	baseName := filepath.Base(cleanPath)
	logger.InfoExtra(i, fmt.Sprintf("Downloading %s -> %s", remotePath, extractDir))

	// 1) Uncompressed tar — fastest on LAN, works everywhere tar exists
	// cd into parent dir so tar entries use only the basename
	// e.g. /root/.cache/backups -> cd /root/.cache && tar cf - backups
	cmd := fmt.Sprintf("cd %s && tar cf - %s 2>/dev/null", parentDir, baseName)
	if err := streamTarOverSSH(client, cmd, extractDir, false); err == nil {
		logger.InfoExtra(i, fmt.Sprintf("Downloaded %s", remotePath))
		return
	}

	// 2) Compressed — only if gzip exists (probe told us)
	if hasGzip {
		cmd = fmt.Sprintf("cd %s && tar cf - %s 2>/dev/null | gzip", parentDir, baseName)
		if err := streamTarOverSSH(client, cmd, extractDir, true); err == nil {
			logger.InfoExtra(i, fmt.Sprintf("Downloaded %s (gzip)", remotePath))
			return
		}
	}

	// 3) SFTP file-based fallback — last resort
	downloadFallbackSFTP(i, client, remotePath, extractDir)
}

// streamTarOverSSH pipes a remote tar command's stdout directly into a local
// tar extractor. 64KB buffered I/O for throughput. No temp files anywhere.
func streamTarOverSSH(client *goph.Client, remoteCmd string, extractDir string, isGzipped bool) error {
	session, err := client.NewSession()
	if err != nil {
		return fmt.Errorf("failed to create session: %w", err)
	}
	defer session.Close()

	stdout, err := session.StdoutPipe()
	if err != nil {
		return fmt.Errorf("failed to get stdout pipe: %w", err)
	}

	if err := session.Start(remoteCmd); err != nil {
		return fmt.Errorf("failed to start command: %w", err)
	}

	// 64KB buffered reader — reduces syscall overhead on the SSH channel
	buffered := bufio.NewReaderSize(stdout, 64*1024)

	var extractErr error
	if isGzipped {
		extractErr = utils.ExtractTarGzFromReader(buffered, extractDir)
	} else {
		extractErr = utils.ExtractTarFromReader(buffered, extractDir)
	}

	sessionErr := session.Wait()
	if extractErr != nil {
		return fmt.Errorf("extraction error: %w", extractErr)
	}
	// tar exits non-zero on permission errors but data is fine — ignore
	_ = sessionErr
	return nil
}

// downloadFallbackSFTP is the last-resort: tar to temp file on remote, SFTP
// download, extract locally. Only used when streaming completely fails.
func downloadFallbackSFTP(i Instance, client *goph.Client, remotePath string, extractDir string) {
	cleanPath := strings.TrimRight(strings.TrimSpace(remotePath), "/")
	parentDir := filepath.Dir(cleanPath)
	baseName := filepath.Base(cleanPath)
	logger.InfoExtra(i, fmt.Sprintf("SFTP fallback: %s -> %s", remotePath, extractDir))

	randName := utils.GenerateRandomFileName(12)
	remoteArchive := fmt.Sprintf("/tmp/%s.tar", randName)
	localArchive := filepath.Join(extractDir, fmt.Sprintf("%s.tar", randName))

	// Uncompressed for speed + maximum compat
	// cd into parent dir so tar entries use only the basename
	archiveCmd := fmt.Sprintf("cd %s && tar cf %s %s 2>/dev/null; [ -s %s ]", parentDir, remoteArchive, baseName, remoteArchive)
	if _, err := client.Run(archiveCmd); err != nil {
		client.Run(fmt.Sprintf("rm -f %s", remoteArchive))
		logger.ErrExtra(i, fmt.Sprintf("Failed to archive '%s' on remote", remotePath))
		return
	}

	if err := client.Download(remoteArchive, localArchive); err != nil {
		logger.ErrExtra(i, fmt.Sprintf("SFTP download failed for '%s': %s", remotePath, err))
		client.Run(fmt.Sprintf("rm -f %s", remoteArchive))
		os.Remove(localArchive)
		return
	}
	client.Run(fmt.Sprintf("rm -f %s", remoteArchive))

	if err := utils.ExtractTar(localArchive, extractDir); err != nil {
		logger.ErrExtra(i, fmt.Sprintf("Extract failed for '%s': %s (keeping archive)", remotePath, err))
		return
	}

	os.Remove(localArchive)
	logger.InfoExtra(i, fmt.Sprintf("Downloaded %s (SFTP fallback)", remotePath))
}

func Upload(client *goph.Client, localPath string, remotePath string) error {
	logger.Debug(fmt.Sprintf("Starting Upload. Local path: %s, Remote path: %s", localPath, remotePath))

	scp_client, err := scp.NewClientBySSH(client.Client)
	if err != nil {
		logger.Err(fmt.Sprintf("Failed to initialize SCP client: %s", err))
		return err
	}

	f, err := os.Open(localPath)
	if err != nil {
		logger.Err(fmt.Sprintf("Failed to open local file: %s", err))
		return err
	}
	defer f.Close()

	err = scp_client.CopyFromFile(context.Background(), *f, remotePath, "0777")
	if err != nil {
		logger.Err(fmt.Sprintf("Failed to SCP file: %s", err))
		return err
	}

	output, err := client.Run("ls " + remotePath)
	if err != nil {
		logger.Err(fmt.Sprintf("Failed to verify remote file: %s", err))
		return err
	}
	if strings.Contains(string(output), "No such file or directory") {
		logger.Err("Remote file does not exist after upload.")
		return errors.New("upload failed: remote file missing")
	}
	logger.Debug("Upload successful.")
	return nil
}

func IsValidPort(host string, port int) bool {
	logger.Debug(fmt.Sprintf("Checking if port %d is valid on host %s", port, host))

	address := fmt.Sprintf("%s:%d", host, port)
	conn, err := net.DialTimeout("tcp", address, 5000*time.Millisecond)
	if err != nil {
		return false
	}
	defer conn.Close()

	banner, _ := bufio.NewReader(conn).ReadString('\n')
	regex := regexp.MustCompile(`(?i)windows|winssh`)
	isValid := !regex.MatchString(banner)
	logger.Debug(fmt.Sprintf("Port %d validity on host %s: %t", port, host, isValid))
	return isValid
}
