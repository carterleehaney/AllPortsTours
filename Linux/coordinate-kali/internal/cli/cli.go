package cli

import (
	"fmt"
	"os"
	"strings"
	"time"

	flag "github.com/spf13/pflag"

	"github.com/LByrgeCP/coordinate-kali/internal/config"
	. "github.com/LByrgeCP/coordinate-kali/internal/globals"
	"github.com/LByrgeCP/coordinate-kali/internal/logger"
)



func Init() {
	logger.InitLogger()

	flag.Parse()

	Timeout = time.Duration(*Timelimit * int(time.Second))
	ShortTimeout = time.Duration(*Timelimit * 40 * int(time.Millisecond))
	
	Scripts = flag.Args()
	Commands = *Command

	if *TmpDir != "" {
		if _, err := os.Stat(*TmpDir); os.IsNotExist(err) {
			err := os.Mkdir(*TmpDir, 0777)
			if err != nil {
				logger.Err(fmt.Sprintf("Error creating tmp directory: %s", err))
			}
		}
	}
	if _, err := os.Stat("output"); os.IsNotExist(err) {
		err := os.Mkdir("output", 0777)
		if err != nil {
			logger.Err("Error creating output directory.")
		}
	}
}

func InputCheck() error {
	if (len(Scripts) == 0 && len(Commands) == 0 && *CreateConfig == "" && *ConfigOnly == "" && len(*DownloadDirs) == 0 && len(*UploadFiles) == 0) || ((*Usernames == "" || *Targets == "") && !*UseConfig) {
		return fmt.Errorf("Missing target(s), script(s)/command(s), and/or username(s).")
	}

	// Ensure scripts and commands are mutually exclusive
	if len(Scripts) > 0 && len(Commands) > 0 {
		return fmt.Errorf("Cannot specify both scripts and commands. Use either scripts or --command flag.")
	}

	if *CreateConfig != "" && *ConfigOnly == "" {
		*Environment = fmt.Sprintf("ROOTPASS=%s", *CreateConfig)
		if *IgnoreUsers != "" {
			*Environment += fmt.Sprintf(";IGNOREUSERS=%s", *IgnoreUsers)
		}
		if *AllPass != "" {
			*Environment += fmt.Sprintf(";ALLPASS=%s", *AllPass)
		}
		Scripts = nil
		Commands = nil
		Scripts = append(Scripts, "scripts/misc/password.sh")
	}

	if *Environment != "" {
		EnvironCmds = strings.Split(*Environment, ";")
	}

	config.ReadEnv()

	return nil
}

func PrintUsage() {
	fmt.Println("Usage:")
	flag.PrintDefaults()
}
