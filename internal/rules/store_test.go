package rules

import "testing"

func clearRules() error {
	rules := GetRules()
	for _, rule := range rules {
		err := DeleteRule(rule.ID)
		if err != nil {
			return err
		}
	}
	return nil
}

func TestStore(t *testing.T) {
	SetConfName("test-linkpure")
	err := clearRules()
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		err := clearRules()
		if err != nil {
			t.Fatal(err)
		}
	})

	t.Run("GetRules empty", func(t *testing.T) {
		rules := GetRules()
		if len(rules) != 0 {
			t.Fatal("Expected empty rules, got:", rules)
		}
	})
	t.Run("NewRule", func(t *testing.T) {
		rule := Rule{
			ID:      "test-id",
			From:    "http://example.com",
			To:      "http://example.org",
			Enabled: true,
		}
		err := NewRule(rule)
		if err != nil {
			t.Fatal(err)
		}
		rules := GetRules()
		if len(rules) == 0 || rules[0].ID != "test-id" {
			t.Fatal("NewRule failed")
		}
	})
	t.Run("NewRuleOrder", func(t *testing.T) {
		rule1 := Rule{
			ID:      "rule-1",
			From:    "http://example1.com",
			To:      "http://example1.org",
			Enabled: true,
		}
		rule2 := Rule{
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
		rules := GetRules()
		if len(rules) < 2 || rules[0].ID != "rule-2" || rules[1].ID != "rule-1" {
			t.Fatalf("NewRule did not insert at the beginning: %v", rules)
		}
	})
}
