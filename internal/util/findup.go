package util

import "path/filepath"

func FindUp(cwd string, cond func(string) bool) (string, bool) {
	current, err := filepath.Abs(cwd)
	if err != nil {
		return "", false
	}
	for {
		if cond(current) {
			return current, true
		}
		parent := filepath.Dir(current)
		if parent == current || err != nil {
			break
		}
		current = parent
	}
	return "", false
}
