package envpaths

import (
	"testing"
)

func TestEnvPaths(t *testing.T) {
	paths, err := EnvPaths("com.rxliuli.linkpure2")
	if err != nil {
		t.Fatal(err)
		return
	}
	t.Log(paths.Config)
}
