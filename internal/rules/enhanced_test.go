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

			result, err := enhancedReplace(re, tt.input, tt.replacement)
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
		rule     Rule
		input    string
		expected string
		match    bool
	}{
		{
			name: "Google search with encoded query",
			rule: Rule{
				ID:      "1",
				From:    `^https://www\.google\.com/search\?q=(.*)$`,
				To:      `https://duckduckgo.com/?q=$1`,
				Enabled: true,
			},
			input:    "https://www.google.com/search?q=golang%20tutorial",
			expected: "https://duckduckgo.com/?q=golang tutorial",
			match:    true,
		},
		{
			name: "YouTube shorts with encoded ID",
			rule: Rule{
				ID:      "2",
				From:    `https://www\.youtube\.com/shorts/([\w-]+)`,
				To:      `https://www.youtube.com/watch?v=$1`,
				Enabled: true,
			},
			input:    "https://www.youtube.com/shorts/dQw4w9WgXcQ",
			expected: "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
			match:    true,
		},
		{
			name: "Disabled rule should not match",
			rule: Rule{
				ID:      "3",
				From:    `^https://example\.com/(.*)$`,
				To:      `https://newsite.com/$1`,
				Enabled: false,
			},
			input:    "https://example.com/page",
			expected: "",
			match:    false,
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
