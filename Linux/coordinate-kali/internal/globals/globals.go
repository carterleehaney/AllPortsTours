package globals

import (
	"time"

	"inet.af/netaddr"

	flag "github.com/spf13/pflag"
)

type Instance struct {
	ID       int
	IP       string
	Username string
	Password string
	Script   string
	Port     int
	Outfile  string
	Hostname string
}

var (
	Timeout      time.Duration
	ShortTimeout time.Duration
	BrokenHosts  []string
	AnnoyingErrs []string
	TotalRuns    int
)

var (
	Port            = flag.IntP("port", "P", 22, "SSH port to use")
	Threads         = flag.IntP("limit", "l", 3, "Thread limit per IP")
	Timelimit       = flag.IntP("timeout", "T", 30, "Time limit per script")
	Targets         = flag.StringP("targets", "t", "", "List of target IP addresses (ex., 127.0.0.1-127.0.0.5,192.168.1.0/24)")
	Usernames       = flag.StringP("usernames", "u", "", "List of usernames")
	Passwords       = flag.StringP("passwords", "p", "", "List of passwords")
	Callbacks       = flag.StringP("callbacks", "c", "", "Callback IP address(es)")
	Outfile         = flag.StringP("outfile-fmt", "o", "", "Output format. If not specified, then no output is saved.")
	Key             = flag.StringP("key", "k", "", "Use this SSH key to connect")
	Environment     = flag.StringP("env", "E", "", "Set these variables before running scripts")
	TmpDir		    = flag.StringP("tmpdir", "W", "/tmp", "Directory to store temporary files")
	DownloadDirs    = flag.StringArrayP("download", "D", []string{}, "Download remote directory(s) to local output (e.g. -D /etc/ssh -D /var/log)")
	UploadFiles     = flag.StringArrayP("upload", "F", []string{}, "Upload local file/dir(s) to remote (e.g. -F 'local;remote' or -F ./tools;/tmp/tools)")
	Sudo            = flag.BoolP("sudo", "S", false, "Attempt to escalate through sudo, if not root")
	QuietOut        = flag.BoolP("quiet", "q", false, "Print only script output")
	SuperQuietOut   = flag.BoolP("super-quiet", "Q", false, "Print only script output, and no errors")
	DebugOut        = flag.BoolP("debug", "d", false, "Print debug messages")
	Errs            = flag.BoolP("errors", "e", false, "Print errors only (no stdout)")
	NoValidate      = flag.BoolP("no-validate", "n", false, "Don't ensure shell is valid, or that scripts have finished running")
	CreateConfig    = flag.StringP("create-config", "C", "", "Create a json config for auth. ONLY COMPATIBLE WITH password.sh. This has no error handling. Have fun.")
	IgnoreUsers	    = flag.StringP("ignore-users", "I", "", "Ignore users")
	AllPass         = flag.StringP("all-pass", "A", "", "Set the same password for all users (except root and ignored users)")
	UseConfig       = flag.BoolP("use-config", "U", false, "Use config.json. This has no error handling. Have fun.")
	ConfigOnly      = flag.StringP("CO", "O", "", "Create a config from existing credentials without running password.sh. Pass the root password as value.")
	Command         = flag.StringArrayP("command", "x", []string{}, "Execute command(s) directly instead of scripts")
	PrivKey         = ""
	DownloadPaths   = []string{}
	CallbackIPs     = []string{}
	Scripts         = []string{}
	Commands        = []string{}
	UsernameList    = []string{}
	PasswordList    = []string{}
	EnvironCmds     = []string{}
	Addresses       = []netaddr.IP{}
	StringAddresses = []string{}
)