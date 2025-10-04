package envpaths

import (
	"os"
	"path/filepath"
)

func EnvPaths(bundleId string) (Paths, error) {
	homedir, err := os.UserHomeDir()
	if err != nil {
		return Paths{}, err
	}

	containerPath := filepath.Join(homedir, "Library/Containers", bundleId)
	return Paths{
		Data:   filepath.Join(containerPath, "Application Support"),
		Config: filepath.Join(containerPath, "Preferences"),
		Cache:  filepath.Join(containerPath, "Caches"),
		Log:    filepath.Join(containerPath, "Logs"),
		Temp:   filepath.Join(containerPath, "Temp"),
	}, nil
}
