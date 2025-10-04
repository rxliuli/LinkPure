package envpaths

import (
	"os"
	"path/filepath"
)

func EnvPaths(bundleId string) (Paths, error) {
	localAppData := os.Getenv("LOCALAPPDATA")
	if localAppData == "" {
		homedir, err := os.UserHomeDir()
		if err != nil {
			return Paths{}, err
		}
		localAppData = filepath.Join(homedir, "AppData", "Local")
	}

	appPath := filepath.Join(localAppData, bundleId)
	return Paths{
		Data:   filepath.Join(appPath, "Data"),
		Config: filepath.Join(appPath, "Config"),
		Cache:  filepath.Join(appPath, "Cache"),
		Log:    filepath.Join(appPath, "Logs"),
		Temp:   filepath.Join(appPath, "Temp"),
	}, nil
}
