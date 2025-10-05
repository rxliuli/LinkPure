package rules

import (
	"testing"
)

func TestCheckRuleChainValidRule(t *testing.T) {
	rule := CommonRule{
		ID:                "test-rule",
		RegexFilter:       `^https://duckduckgo\.com/\?.*&q=(.*?)(&.*)?$`,
		RegexSubstitution: "https://www.google.com/search?q=$1",
		RemoveParams:      []string{},
		Test:              []string{},
	}

	result := CheckRuleChain([]CommonRule{rule}, "https://duckduckgo.com/?t=h_&q=js&ia=web", nil)

	expected := CheckResult{
		Status: StatusMatched,
		URLs:   []string{"https://www.google.com/search?q=js"},
	}

	if result.Status != expected.Status {
		t.Errorf("Expected Status to be %v, got %v", expected.Status, result.Status)
	}

	if len(result.URLs) != len(expected.URLs) {
		t.Errorf("Expected %d URLs, got %d", len(expected.URLs), len(result.URLs))
	}

	if len(result.URLs) > 0 && result.URLs[0] != expected.URLs[0] {
		t.Errorf("Expected URL to be %s, got %s", expected.URLs[0], result.URLs[0])
	}
}

func TestCheckRuleChainNoMatch(t *testing.T) {
	rule := CommonRule{
		ID:                "test-rule",
		RegexFilter:       "https://www.reddit.com/r/(.*?)/",
		RegexSubstitution: "https://www.reddit.com/r/$1/top/",
	}

	result := CheckRuleChain([]CommonRule{rule}, "https://www.google.com/", nil)

	expected := CheckResult{
		Status: StatusNotMatched,
		URLs:   []string{},
	}

	if result.Status != expected.Status {
		t.Errorf("Expected Status to be %v, got %v", expected.Status, result.Status)
	}

	if len(result.URLs) != 0 {
		t.Errorf("Expected 0 URLs, got %d", len(result.URLs))
	}
}

func TestCheckRuleChainInfiniteRedirect(t *testing.T) {
	rule := CommonRule{
		ID:                "test-rule",
		RegexFilter:       "https://www.reddit.com/r/(.*)/(.*)",
		RegexSubstitution: "https://www.reddit.com/r/$1/top/$2",
	}

	result := CheckRuleChain([]CommonRule{rule}, "https://www.reddit.com/r/MadeMeSmile/test", nil)

	if result.Status != StatusInfiniteRedirect {
		t.Errorf("Expected Status to be %v, got %v", StatusInfiniteRedirect, result.Status)
	}

	if len(result.URLs) != 5 { // Default maxRedirects is 5
		t.Errorf("Expected 5 URLs for infinite redirect, got %d", len(result.URLs))
	}
}

func TestCheckRuleChainSelfRedirect(t *testing.T) {
	rule := CommonRule{
		ID:                "test-rule",
		RegexFilter:       "(.*)",
		RegexSubstitution: "$1",
	}

	result := CheckRuleChain([]CommonRule{rule}, "https://example.com/", nil)

	expected := CheckResult{
		Status: StatusCircularRedirect,
		URLs:   []string{"https://example.com/"},
	}

	if result.Status != expected.Status {
		t.Errorf("Expected Status to be %v, got %v", expected.Status, result.Status)
	}

	if len(result.URLs) != 1 {
		t.Errorf("Expected 1 URL, got %d", len(result.URLs))
	}
}

func TestCheckRuleChainCircularRedirectInChain(t *testing.T) {
	rules := []CommonRule{
		{
			ID:                "rule1",
			RegexFilter:       "https://a.com/(.*)",
			RegexSubstitution: "https://b.com/$1",
		},
		{
			ID:                "rule2",
			RegexFilter:       "https://b.com/(.*)",
			RegexSubstitution: "https://c.com/$1",
		},
		{
			ID:                "rule3",
			RegexFilter:       "https://c.com/(.*)",
			RegexSubstitution: "https://a.com/$1",
		},
	}

	result := CheckRuleChain(rules, "https://a.com/test", nil)

	if result.Status != StatusCircularRedirect {
		t.Errorf("Expected Status to be %v, got %v", StatusCircularRedirect, result.Status)
	}

	expectedURLs := []string{
		"https://b.com/test",
		"https://c.com/test",
		"https://a.com/test",
	}

	if len(result.URLs) != len(expectedURLs) {
		t.Errorf("Expected %d URLs, got %d", len(expectedURLs), len(result.URLs))
	}

	for i, expectedURL := range expectedURLs {
		if i < len(result.URLs) && result.URLs[i] != expectedURL {
			t.Errorf("Expected URL[%d] to be %s, got %s", i, expectedURL, result.URLs[i])
		}
	}
}

func TestCheckRuleChainRedditExample(t *testing.T) {
	// Problematic rule with non-greedy regex (.*?)
	// The non-greedy pattern only captures "MadeMeSmile", not "MadeMeSmile/top"
	// So after first redirect, it keeps matching the same pattern and produces circular redirect
	rule := CommonRule{
		ID:                "reddit-rule",
		RegexFilter:       "https://www.reddit.com/r/(.*?)/",
		RegexSubstitution: "https://www.reddit.com/r/$1/top/",
	}

	result := CheckRuleChain([]CommonRule{rule}, "https://www.reddit.com/r/MadeMeSmile/", nil)

	// The pattern (.*?) is non-greedy, so it only matches up to the first /
	// Flow:
	//   1. https://www.reddit.com/r/MadeMeSmile/ -> https://www.reddit.com/r/MadeMeSmile/top/
	//   2. https://www.reddit.com/r/MadeMeSmile/top/ matches (.*?) as just "MadeMeSmile"
	//      -> https://www.reddit.com/r/MadeMeSmile/top/ (same URL = circular!)
	if result.Status != StatusCircularRedirect {
		t.Errorf("Expected Status to be %v, got %v", StatusCircularRedirect, result.Status)
	}

	if len(result.URLs) != 2 {
		t.Errorf("Expected 2 URLs, got %d", len(result.URLs))
		for i, url := range result.URLs {
			t.Logf("  [%d]: %s", i, url)
		}
	}
}

func TestCheckRuleChainTwoStepCircularRedirect(t *testing.T) {
	// Use different domains to avoid rule overlap
	rule1 := CommonRule{
		ID:                "circular-rule-1",
		RegexFilter:       "^https://a\\.example\\.com/(.*)$",
		RegexSubstitution: "https://b.example.com/$1",
	}

	rule2 := CommonRule{
		ID:                "circular-rule-2",
		RegexFilter:       "^https://b\\.example\\.com/(.*)$",
		RegexSubstitution: "https://a.example.com/$1",
	}

	result := CheckRuleChain([]CommonRule{rule1, rule2}, "https://a.example.com/test", nil)

	// This should be detected as circular redirect
	// Flow: a.example.com/test -> b.example.com/test -> a.example.com/test (circular)
	if result.Status != StatusCircularRedirect {
		t.Errorf("Expected Status to be %v, got %v", StatusCircularRedirect, result.Status)
	}

	// URLs should contain the redirects up to the point where circularity is detected
	expectedURLs := []string{
		"https://b.example.com/test",
		"https://a.example.com/test",
	}

	if len(result.URLs) != len(expectedURLs) {
		t.Errorf("Expected %d URLs, got %d", len(expectedURLs), len(result.URLs))
	}
}

func TestCheckRuleChainRedditCorrectedExample(t *testing.T) {
	// Corrected rule to avoid circular redirect
	rule := CommonRule{
		ID:                "reddit-rule-fixed",
		RegexFilter:       "https://www.reddit.com/r/([^/]+)/$",
		RegexSubstitution: "https://www.reddit.com/r/$1/top/",
	}

	result := CheckRuleChain([]CommonRule{rule}, "https://www.reddit.com/r/MadeMeSmile/", nil)

	expected := CheckResult{
		Status: StatusMatched,
		URLs:   []string{"https://www.reddit.com/r/MadeMeSmile/top/"},
	}

	if result.Status != expected.Status {
		t.Errorf("Expected Status to be %v, got %v", expected.Status, result.Status)
	}

	if len(result.URLs) != len(expected.URLs) {
		t.Errorf("Expected %d URLs, got %d", len(expected.URLs), len(result.URLs))
	}

	if len(result.URLs) > 0 && result.URLs[0] != expected.URLs[0] {
		t.Errorf("Expected URL to be %s, got %s", expected.URLs[0], result.URLs[0])
	}
}

func TestCheckRuleChainYouTubeExample(t *testing.T) {
	rule := CommonRule{
		ID:                "youtube-rule",
		RegexFilter:       "https://youtu.be/(.*)",
		RegexSubstitution: "https://www.youtube.com/watch?v=$1",
	}

	result := CheckRuleChain([]CommonRule{rule}, "https://youtu.be/dQw4w9WgXcQ", nil)

	expected := CheckResult{
		Status: StatusMatched,
		URLs:   []string{"https://www.youtube.com/watch?v=dQw4w9WgXcQ"},
	}

	if result.Status != expected.Status {
		t.Errorf("Expected Status to be %v, got %v", expected.Status, result.Status)
	}

	if len(result.URLs) != len(expected.URLs) {
		t.Errorf("Expected %d URLs, got %d", len(expected.URLs), len(result.URLs))
	}

	if len(result.URLs) > 0 && result.URLs[0] != expected.URLs[0] {
		t.Errorf("Expected URL to be %s, got %s", expected.URLs[0], result.URLs[0])
	}
}

func TestCheckRuleChainWithOptions(t *testing.T) {
	rule := CommonRule{
		ID:                "test-rule",
		RegexFilter:       "https://www.reddit.com/r/(.*)/(.*)",
		RegexSubstitution: "https://www.reddit.com/r/$1/top/$2",
	}

	options := &CheckOptions{MaxRedirects: 3}
	result := CheckRuleChain([]CommonRule{rule}, "https://www.reddit.com/r/MadeMeSmile/test", options)

	if result.Status != StatusInfiniteRedirect {
		t.Errorf("Expected Status to be %v, got %v", StatusInfiniteRedirect, result.Status)
	}

	if len(result.URLs) != 3 { // Custom maxRedirects is 3
		t.Errorf("Expected 3 URLs for infinite redirect with custom maxRedirects, got %d", len(result.URLs))
	}
}

func TestRegexp2NegativeLookahead(t *testing.T) {
	// Test negative lookahead functionality that's only available in regexp2
	// This rule matches URLs that contain "reddit.com" but NOT followed by "/top"
	rule := CommonRule{
		ID:                "negative-lookahead-rule",
		RegexFilter:       `^https://www\.reddit\.com/r/([^/]+)/(?!top)(.*)$`,
		RegexSubstitution: "https://www.reddit.com/r/$1/top/$2",
	}

	// This should match (no "/top" after subreddit)
	result1 := MatchRuleWithResult(rule, "https://www.reddit.com/r/golang/posts")
	expected1 := MatchResult{
		Match: true,
		URL:   "https://www.reddit.com/r/golang/top/posts",
	}

	if result1.Match != expected1.Match {
		t.Errorf("Expected Match to be %v, got %v", expected1.Match, result1.Match)
	}

	if result1.URL != expected1.URL {
		t.Errorf("Expected URL to be %s, got %s", expected1.URL, result1.URL)
	}

	// This should NOT match (already has "/top")
	result2 := MatchRuleWithResult(rule, "https://www.reddit.com/r/golang/top/posts")
	expected2 := MatchResult{
		Match: false,
		URL:   "",
	}

	if result2.Match != expected2.Match {
		t.Errorf("Expected Match to be %v, got %v", expected2.Match, result2.Match)
	}
}

func TestRegexp2PositiveLookahead(t *testing.T) {
	// Test positive lookahead functionality
	// This rule matches GitHub URLs that are followed by "/issues"
	rule := CommonRule{
		ID:                "positive-lookahead-rule",
		RegexFilter:       `^https://github\.com/([^/]+/[^/]+)(?=/issues)(.*)$`,
		RegexSubstitution: "https://github.com/$1/issues?state=open",
	}

	// This should match (has "/issues")
	result1 := MatchRuleWithResult(rule, "https://github.com/user/repo/issues")
	expected1 := MatchResult{
		Match: true,
		URL:   "https://github.com/user/repo/issues?state=open",
	}

	if result1.Match != expected1.Match {
		t.Errorf("Expected Match to be %v, got %v", expected1.Match, result1.Match)
	}

	if result1.URL != expected1.URL {
		t.Errorf("Expected URL to be %s, got %s", expected1.URL, result1.URL)
	}

	// This should NOT match (doesn't have "/issues")
	result2 := MatchRuleWithResult(rule, "https://github.com/user/repo/pull")
	expected2 := MatchResult{
		Match: false,
		URL:   "",
	}

	if result2.Match != expected2.Match {
		t.Errorf("Expected Match to be %v, got %v", expected2.Match, result2.Match)
	}
}

func TestRealCase1(t *testing.T) {
	rule := CommonRule{
		ID:                "positive-lookahead-rule",
		RegexFilter:       `^(https://www.google.com/search\?q=.+?)&.*$`,
		RegexSubstitution: "$1",
	}

	result := MatchRuleWithResult(rule, "https://www.google.com/search?q=%E6%B5%8B%E8%AF%95+JavaScript&newwindow=1&sxsrf=AE3TifMQ-KQvqyycI31J3_atlTT5jlc9Fg%3A1759421656393&uact=5")
	if !result.Match {
		t.Errorf("Expected Match to be %v, got %v", true, result.Match)
	}
	// Note: enhancedReplace decodes URL-encoded parameters, so %E6%B5%8B%E8%AF%95 becomes 测试
	// and + becomes space
	if result.URL != "https://www.google.com/search?q=测试 JavaScript" {
		t.Errorf("Expected URL to be %s, got %s", "https://www.google.com/search?q=测试 JavaScript", result.URL)
	}
}

func TestRealCase2(t *testing.T) {
	rule := CommonRule{
		ID:                "real-case-2",
		RegexFilter:       `^https://apps.apple.com/\w+?/app/.+?/(\w+)$`,
		RegexSubstitution: "https://apps.apple.com/app/$1",
	}

	result := MatchRuleWithResult(rule, "https://apps.apple.com/cn/app/cleaner-for-x/id6752027292")
	if !result.Match {
		t.Errorf("Expected Match to be %v, got %v", true, result.Match)
	}
	if result.URL != "https://apps.apple.com/app/id6752027292" {
		t.Errorf("Expected URL to be %s, got %s", "https://apps.apple.com/app/id6752027292", result.URL)
	}
}
