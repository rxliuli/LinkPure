package rules

import (
	"testing"

	"github.com/samber/lo"
)

func TestGetShareRules(t *testing.T) {
	rules := GetShareRules()

	if len(rules) == 0 {
		t.Fatal("Expected to load shared rules, got 0")
	}

	// Check first rule
	if len(rules) > 0 {
		t.Logf("First rule: %s - %s", rules[0].ID, rules[0].RegexFilter)
	}

	// Verify some known rules exist
	foundAmazon := false
	foundGoogle := false

	for _, rule := range rules {
		if rule.ID == "amazon-params" {
			foundAmazon = true
		}
		if rule.ID == "google-redirect-0" {
			foundGoogle = true
		}
	}

	if !foundAmazon {
		t.Error("Expected to find amazon-params rule")
	}

	if !foundGoogle {
		t.Error("Expected to find google-redirect-0 rule")
	}
}

func TestAllShareRules(t *testing.T) {
	shareRules := GetShareRules()
	rules := lo.Map(shareRules, func(item ShareRule, index int) CommonRule {
		return CommonRule{
			ID:                item.ID,
			RegexFilter:       item.RegexFilter,
			RegexSubstitution: item.RegexSubstitution,
			RemoveParams:      item.RemoveParams,
		}
	})
	for _, rule := range shareRules {
		if len(rule.Test) == 0 {
			continue
		}
		for _, test := range rule.Test {
			result := CheckRuleChain(rules, test.From, nil)
			if result.Status != StatusMatched {
				t.Errorf("Rule %s failed to match %s", rule.ID, test.From)
				return
			}
			if result.URLs[len(result.URLs)-1] != test.To {
				t.Errorf("Rule %s expected to transform %s to %s, got %s", rule.ID, test.From, test.To, result.URLs[len(result.URLs)-1])
			}
		}
	}
}
