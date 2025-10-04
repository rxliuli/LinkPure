package envpaths

import (
	"testing"
)

func TestEnvPaths(t *testing.T) {
	paths, err := EnvPaths("com.rxliuli.linkpure")
	if err != nil {
		t.Fatal(err)
		return
	}
	t.Log(paths.Config)
}
