package rules

import (
	_ "embed"
	"encoding/json"
)

//go:embed assets/shared-rules.json
var sharedRulesData []byte

type ShareRule struct {
	ID                string     `json:"id"`
	RegexFilter       string     `json:"regexFilter"`
	RegexSubstitution string     `json:"regexSubstitution,omitempty"`
	RemoveParams      []string   `json:"removeParams,omitempty"`
	Test              []TestCase `json:"test,omitempty"`
}

type TestCase struct {
	From string `json:"from"`
	To   string `json:"to"`
}

type SharedRulesFile struct {
	Name        string      `json:"name"`
	Description string      `json:"description"`
	Rules       []ShareRule `json:"rules"`
}

func GetShareRules() []ShareRule {
	var rulesFile SharedRulesFile
	if err := json.Unmarshal(sharedRulesData, &rulesFile); err != nil {
		// If parsing fails, return empty slice
		return []ShareRule{}
	}
	return rulesFile.Rules
}

func ToggleShareRules(id string, enable bool) error {
	panic("not implemented")
}

func FetchShareRules() error {
	panic("not implemented")
}
