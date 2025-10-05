package rules

import (
	"linkpure/internal/logger"
	"os"
	"testing"
)

func init() {
	logger.Init(os.TempDir())
	SetConfName("test-linkpure")
	rules := GetLocalRules()
	for _, rule := range rules {
		err := DeleteRule(rule.ID)
		if err != nil {
			panic(err)
		}
	}
}

func TestGetRulesEmpty(t *testing.T) {
	rules := GetLocalRules()
	if len(rules) != 0 {
		t.Fatal("Expected empty rules, got:", rules)
	}
}
func TestNewRule(t *testing.T) {
	rule := LocalRule{
		ID:      "test-id",
		From:    "http://example.com",
		To:      "http://example.org",
		Enabled: true,
	}
	err := NewRule(rule)
	if err != nil {
		t.Fatal(err)
	}
	rules := GetLocalRules()
	if len(rules) == 0 || rules[0].ID != "test-id" {
		t.Fatal("NewRule failed")
	}
}
func TestUpdateRule(t *testing.T) {
	rule1 := LocalRule{
		ID:      "rule-1",
		From:    "http://example1.com",
		To:      "http://example1.org",
		Enabled: true,
	}
	rule2 := LocalRule{
		ID:      "rule-2",
		From:    "http://example2.com",
		To:      "http://example2.org",
		Enabled: true,
	}
	err := NewRule(rule1)
	if err != nil {
		t.Fatalf("Failed to add rule1: %v", err)
	}
	err = NewRule(rule2)
	if err != nil {
		t.Fatalf("Failed to add rule2: %v", err)
	}
	rules := GetLocalRules()
	if len(rules) < 2 || rules[0].ID != "rule-2" || rules[1].ID != "rule-1" {
		t.Fatalf("NewRule did not insert at the beginning: %v", rules)
	}
}
