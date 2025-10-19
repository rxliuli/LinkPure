package envpaths

import (
	"os"
	"path/filepath"
	"testing"
)

func TestEnvPathsLinux(t *testing.T) {
	// Save original environment variables
	originalXDGDataHome := os.Getenv("XDG_DATA_HOME")
	originalXDGConfigHome := os.Getenv("XDG_CONFIG_HOME")
	originalXDGCacheHome := os.Getenv("XDG_CACHE_HOME")
	originalXDGStateHome := os.Getenv("XDG_STATE_HOME")

	// Clean up after test
	defer func() {
		os.Setenv("XDG_DATA_HOME", originalXDGDataHome)
		os.Setenv("XDG_CONFIG_HOME", originalXDGConfigHome)
		os.Setenv("XDG_CACHE_HOME", originalXDGCacheHome)
		os.Setenv("XDG_STATE_HOME", originalXDGStateHome)
	}()

	t.Run("with default XDG directories", func(t *testing.T) {
		// Clear XDG environment variables to test defaults
		os.Unsetenv("XDG_DATA_HOME")
		os.Unsetenv("XDG_CONFIG_HOME")
		os.Unsetenv("XDG_CACHE_HOME")
		os.Unsetenv("XDG_STATE_HOME")

		bundleId := "com.example.testapp"
		paths, err := EnvPaths(bundleId)
		if err != nil {
			t.Fatalf("EnvPaths failed: %v", err)
		}

		homedir, _ := os.UserHomeDir()

		expectedData := filepath.Join(homedir, ".local", "share", bundleId)
		expectedConfig := filepath.Join(homedir, ".config", bundleId)
		expectedCache := filepath.Join(homedir, ".cache", bundleId)
		expectedLog := filepath.Join(homedir, ".local", "state", bundleId, "logs")
		expectedTemp := filepath.Join("/tmp", bundleId)

		if paths.Data != expectedData {
			t.Errorf("Expected Data path %s, got %s", expectedData, paths.Data)
		}
		if paths.Config != expectedConfig {
			t.Errorf("Expected Config path %s, got %s", expectedConfig, paths.Config)
		}
		if paths.Cache != expectedCache {
			t.Errorf("Expected Cache path %s, got %s", expectedCache, paths.Cache)
		}
		if paths.Log != expectedLog {
			t.Errorf("Expected Log path %s, got %s", expectedLog, paths.Log)
		}
		if paths.Temp != expectedTemp {
			t.Errorf("Expected Temp path %s, got %s", expectedTemp, paths.Temp)
		}
	})

	t.Run("with custom XDG directories", func(t *testing.T) {
		// Set custom XDG environment variables
		os.Setenv("XDG_DATA_HOME", "/custom/data")
		os.Setenv("XDG_CONFIG_HOME", "/custom/config")
		os.Setenv("XDG_CACHE_HOME", "/custom/cache")
		os.Setenv("XDG_STATE_HOME", "/custom/state")

		bundleId := "com.example.testapp"
		paths, err := EnvPaths(bundleId)
		if err != nil {
			t.Fatalf("EnvPaths failed: %v", err)
		}

		expectedData := filepath.Join("/custom/data", bundleId)
		expectedConfig := filepath.Join("/custom/config", bundleId)
		expectedCache := filepath.Join("/custom/cache", bundleId)
		expectedLog := filepath.Join("/custom/state", bundleId, "logs")
		expectedTemp := filepath.Join("/tmp", bundleId)

		if paths.Data != expectedData {
			t.Errorf("Expected Data path %s, got %s", expectedData, paths.Data)
		}
		if paths.Config != expectedConfig {
			t.Errorf("Expected Config path %s, got %s", expectedConfig, paths.Config)
		}
		if paths.Cache != expectedCache {
			t.Errorf("Expected Cache path %s, got %s", expectedCache, paths.Cache)
		}
		if paths.Log != expectedLog {
			t.Errorf("Expected Log path %s, got %s", expectedLog, paths.Log)
		}
		if paths.Temp != expectedTemp {
			t.Errorf("Expected Temp path %s, got %s", expectedTemp, paths.Temp)
		}
	})
}
