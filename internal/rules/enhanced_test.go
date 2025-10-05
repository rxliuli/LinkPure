package rules

import (
	"testing"

	"github.com/dlclark/regexp2"
)

func TestEnhancedReplace(t *testing.T) {
	tests := []struct {
		name        string
		pattern     string
		input       string
		replacement string
		expected    string
		shouldMatch bool
	}{
		{
			name:        "Simple URL decode",
			pattern:     `^https://example\.com/search\?q=(.*)$`,
			input:       "https://example.com/search?q=hello%20world",
			replacement: "https://newsite.com/search?q=$1",
			expected:    "https://newsite.com/search?q=hello world",
			shouldMatch: true,
		},
		{
			name:        "Multiple capture groups with encoding",
			pattern:     `^https://example\.com/(.+)/(.+)$`,
			input:       "https://example.com/user%20name/file%2Bname",
			replacement: "https://newsite.com/$1/$2",
			expected:    "https://newsite.com/user name/file+name",
			shouldMatch: true,
		},
		{
			name:        "Chinese characters encoded",
			pattern:     `^https://example\.com/search\?q=(.*)$`,
			input:       "https://example.com/search?q=%E4%B8%AD%E6%96%87",
			replacement: "https://newsite.com/q=$1",
			expected:    "https://newsite.com/q=中文",
			shouldMatch: true,
		},
		{
			name:        "Mixed encoded and plain text",
			pattern:     `^https://example\.com/(.+)\?ref=(.*)$`,
			input:       "https://example.com/page?ref=some%20source",
			replacement: "https://newsite.com/$1?from=$2",
			expected:    "https://newsite.com/page?from=some source",
			shouldMatch: true,
		},
		{
			name:        "No encoding needed",
			pattern:     `^https://example\.com/(.+)$`,
			input:       "https://example.com/page",
			replacement: "https://newsite.com/$1",
			expected:    "https://newsite.com/page",
			shouldMatch: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			re, err := regexp2.Compile(tt.pattern, 0)
			if err != nil {
				t.Fatalf("Failed to compile regex: %v", err)
			}

			matched, err := re.MatchString(tt.input)
			if err != nil {
				t.Fatalf("Failed to match: %v", err)
			}

			if matched != tt.shouldMatch {
				t.Errorf("Match result mismatch. Expected %v, got %v", tt.shouldMatch, matched)
			}

			if !matched {
				return
			}

			result, err := enhancedReplace(re, tt.input, CommonRule{
				RegexSubstitution: tt.replacement,
			})
			if err != nil {
				t.Fatalf("enhancedReplace failed: %v", err)
			}

			if result != tt.expected {
				t.Errorf("Result mismatch.\nExpected: %q\nGot:      %q", tt.expected, result)
			}
		})
	}
}

func TestMatchRuleWithResultEnhanced(t *testing.T) {
	tests := []struct {
		name     string
		rule     CommonRule
		input    string
		expected string
		match    bool
	}{
		{
			name: "Google search with encoded query",
			rule: CommonRule{
				ID:                "1",
				RegexFilter:       `^https://www\.google\.com/search\?q=(.*)$`,
				RegexSubstitution: `https://duckduckgo.com/?q=$1`,
			},
			input:    "https://www.google.com/search?q=golang%20tutorial",
			expected: "https://duckduckgo.com/?q=golang tutorial",
			match:    true,
		},
		{
			name: "YouTube shorts with encoded ID",
			rule: CommonRule{
				ID:                "2",
				RegexFilter:       `https://www\.youtube\.com/shorts/([\w-]+)`,
				RegexSubstitution: `https://www.youtube.com/watch?v=$1`,
			},
			input:    "https://www.youtube.com/shorts/dQw4w9WgXcQ",
			expected: "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
			match:    true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := MatchRuleWithResult(tt.rule, tt.input)

			if result.Match != tt.match {
				t.Errorf("Match result mismatch. Expected %v, got %v", tt.match, result.Match)
			}

			if result.Match && result.URL != tt.expected {
				t.Errorf("URL mismatch.\nExpected: %q\nGot:      %q", tt.expected, result.URL)
			}
		})
	}
}

func TestRemoveParams(t *testing.T) {
	rule := CommonRule{
		ID:                "3",
		RegexFilter:       `^https://example\.com/page\?id=(.*)&utm_source=(.*)$`,
		RegexSubstitution: `https://example.com/page?id=$1`,
		RemoveParams:      []string{"utm_source"},
	}

	input := "https://example.com/page?id=123&utm_source=newsletter"
	expected := "https://example.com/page?id=123"

	result := MatchRuleWithResult(rule, input)

	if !result.Match {
		t.Errorf("Expected a match but got none")
	}

	if result.URL != expected {
		t.Errorf("URL mismatch.\nExpected: %q\nGot:      %q", expected, result.URL)
	}
}
