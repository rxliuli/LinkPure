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

	// Follow XDG Base Directory Specification
	// https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html
	
	dataHome := os.Getenv("XDG_DATA_HOME")
	if dataHome == "" {
		dataHome = filepath.Join(homedir, ".local", "share")
	}
	
	configHome := os.Getenv("XDG_CONFIG_HOME")
	if configHome == "" {
		configHome = filepath.Join(homedir, ".config")
	}
	
	cacheHome := os.Getenv("XDG_CACHE_HOME")
	if cacheHome == "" {
		cacheHome = filepath.Join(homedir, ".cache")
	}
	
	// For logs, use XDG_STATE_HOME or fallback to .local/state
	stateHome := os.Getenv("XDG_STATE_HOME")
	if stateHome == "" {
		stateHome = filepath.Join(homedir, ".local", "state")
	}

	return Paths{
		Data:   filepath.Join(dataHome, bundleId),
		Config: filepath.Join(configHome, bundleId),
		Cache:  filepath.Join(cacheHome, bundleId),
		Log:    filepath.Join(stateHome, bundleId, "logs"),
		Temp:   filepath.Join("/tmp", bundleId),
	}, nil
}