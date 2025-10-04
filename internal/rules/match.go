package rules

import (
	"net/url"
	"strconv"
	"strings"

	"github.com/dlclark/regexp2"
)

// MatchResult represents the result of a rule match
type MatchResult struct {
	Match bool   `json:"match"`
	URL   string `json:"url"`
}

// CheckStatus represents the status of rule chain checking
type CheckStatus string

const (
	StatusMatched          CheckStatus = "matched"
	StatusNotMatched       CheckStatus = "not-matched"
	StatusCircularRedirect CheckStatus = "circular-redirect"
	StatusInfiniteRedirect CheckStatus = "infinite-redirect"
)

// CheckResult represents the result of checking a rule chain
type CheckResult struct {
	Status CheckStatus `json:"status"`
	URLs   []string    `json:"urls"`
}

// CheckOptions contains options for checking rule chains
type CheckOptions struct {
	MaxRedirects int `json:"maxRedirects"`
}

// enhancedReplace performs URL-decoding aware replacement
// It decodes captured groups before replacing them in the output
func enhancedReplace(re *regexp2.Regexp, from string, replacement string) (string, error) {
	// Get the match with capture groups
	match, err := re.FindStringMatch(from)
	if err != nil || match == nil {
		return "", err
	}

	result := replacement
	groups := match.Groups()

	// Iterate through captured groups (skip group 0 which is the full match)
	for i := 1; i < len(groups); i++ {
		capturedValue := groups[i].String()

		// Try to decode the URL component
		decodedValue, err := url.QueryUnescape(capturedValue)
		if err != nil {
			// If decoding fails, use the original value
			decodedValue = capturedValue
		}

		// Replace $1, $2, etc. with the decoded value
		placeholder := "$" + strconv.Itoa(i)
		result = strings.ReplaceAll(result, placeholder, decodedValue)
	}

	return result, nil
}

// MatchRuleWithResult checks if any rule matches the given URL and returns the rewritten URL
func MatchRuleWithResult(rule Rule, from string) MatchResult {
	if !rule.Enabled {
		return MatchResult{Match: false, URL: ""}
	}

	re, err := regexp2.Compile(rule.From, 0)
	if err != nil {
		return MatchResult{Match: false, URL: ""}
	}

	matched, err := re.MatchString(from)
	if err != nil {
		return MatchResult{Match: false, URL: ""}
	}

	if matched {
		// Use enhanced replace with URL decoding
		rewrittenURL, err := enhancedReplace(re, from, rule.To)
		if err != nil {
			return MatchResult{Match: false, URL: ""}
		}
		return MatchResult{Match: true, URL: rewrittenURL}
	}

	return MatchResult{Match: false, URL: ""}
}

// getEnabledRules filters and returns only enabled rules
func getEnabledRules(rules []Rule) []Rule {
	var enabledRules []Rule
	for _, rule := range rules {
		if rule.Enabled {
			enabledRules = append(enabledRules, rule)
		}
	}
	return enabledRules
}

// contains checks if a slice contains a specific string
func contains(slice []string, item string) bool {
	for _, s := range slice {
		if s == item {
			return true
		}
	}
	return false
}

// CheckRuleChain checks a chain of rules and detects circular redirects and infinite redirects
func CheckRuleChain(rules []Rule, url string, options *CheckOptions) CheckResult {
	maxRedirects := 5
	if options != nil && options.MaxRedirects > 0 {
		maxRedirects = options.MaxRedirects
	}

	enabledRules := getEnabledRules(rules)
	println("Enabled rules count:", len(enabledRules))
	var redirectURLs []string
	currentURL := url

	for i := 0; i < maxRedirects; i++ {
		// Find matching rule
		var matchingRule *Rule
		for _, rule := range enabledRules {
			result := MatchRuleWithResult(rule, currentURL)
			if result.Match {
				matchingRule = &rule
				break
			}
		}

		if matchingRule == nil {
			// If first iteration doesn't match, return not-matched
			if i == 0 {
				return CheckResult{Status: StatusNotMatched, URLs: []string{}}
			}
			// If second iteration and beyond doesn't match, return matched
			return CheckResult{Status: StatusMatched, URLs: redirectURLs}
		}

		// Apply the rule
		result := MatchRuleWithResult(*matchingRule, currentURL)
		// This should not happen since we found a matching rule above
		if !result.Match {
			// This is an unexpected error case
			return CheckResult{Status: StatusNotMatched, URLs: redirectURLs}
		}

		// Check for circular redirect - check against original URL and all previous URLs
		if result.URL == url || contains(redirectURLs, result.URL) {
			redirectURLs = append(redirectURLs, result.URL)
			return CheckResult{Status: StatusCircularRedirect, URLs: redirectURLs}
		}

		redirectURLs = append(redirectURLs, result.URL)
		currentURL = result.URL
	}

	// If we exit the loop, it means infinite redirect
	return CheckResult{Status: StatusInfiniteRedirect, URLs: redirectURLs}
}
