package rules

import (
	"linkpure/internal/conf"
	"linkpure/internal/logger"
)

// PresetSize represents a window size preset
type PresetSize struct {
	ID     string `json:"id"`
	Width  int    `json:"width"`
	Height int    `json:"height"`
}

var config *conf.Conf

func SetConfName(filename string) {
	var err error
	config, err = conf.GetConf(filename)
	if err != nil {
		logger.Error("Failed to get conf: %v", err)
	}
}

type LocalRule struct {
	ID      string `json:"id"`
	From    string `json:"from"`
	To      string `json:"to"`
	Enabled bool   `json:"enabled"`
}

func GetLocalRules() []LocalRule {
	if config == nil {
		logger.Error("Config is nil, rules.SetConfName() may not have been called")
		return nil
	}
	var rules []LocalRule
	err := config.Get("rules", &rules)
	if err != nil {
		logger.Error("Failed to get rules: %v", err)
		return nil
	}
	logger.Info("GetRules returned %d rules", len(rules))
	return rules
}

func NewRule(rule LocalRule) error {
	rules := GetLocalRules()
	rules = append([]LocalRule{rule}, rules...)
	return config.Set("rules", rules)
}

func UpdateRule(updated LocalRule) error {
	rules := GetLocalRules()
	for i, rule := range rules {
		if rule.ID == updated.ID {
			rules[i] = updated
			break
		}
	}
	return config.Set("rules", rules)
}

func DeleteRule(id string) error {
	rules := GetLocalRules()
	for i, rule := range rules {
		if rule.ID == id {
			rules = append(rules[:i], rules[i+1:]...)
			break
		}
	}
	return config.Set("rules", rules)
}
