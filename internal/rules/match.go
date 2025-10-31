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

type CommonRule struct {
	ID                string   `json:"id"`
	RegexFilter       string   `json:"regexFilter"`
	RegexSubstitution string   `json:"regexSubstitution"`
	RemoveParams      []string `json:"removeParams"`
	Test              []string `json:"test"`
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
func enhancedReplace(re *regexp2.Regexp, from string, rule CommonRule) (string, error) {
	// Get the match with capture groups
	match, err := re.FindStringMatch(from)
	if err != nil || match == nil {
		return "", err
	}

	if rule.RegexSubstitution != "" {
		result := rule.RegexSubstitution
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
	if len(rule.RemoveParams) > 0 {
		parsedURL, err := url.Parse(from)
		if err != nil {
			return "", err
		}
		query := parsedURL.Query()

		// Track which params to remove
		paramsToRemove := make([]string, 0)

		// Match params using regex patterns
		for paramName := range query {
			for _, pattern := range rule.RemoveParams {
				// For exact parameter name matching, add anchors if not present
				// This prevents "t" from matching "text"
				finalPattern := pattern
				if !strings.ContainsAny(pattern, "^$()[]{}*+?|\\") {
					// Simple string without regex special chars - match exactly
					finalPattern = "^" + pattern + "$"
				}

				re, err := regexp2.Compile(finalPattern, 0)
				if err != nil {
					continue
				}
				matched, err := re.MatchString(paramName)
				if err == nil && matched {
					paramsToRemove = append(paramsToRemove, paramName)
					break
				}
			}
		}

		// If no params to remove, return empty
		if len(paramsToRemove) == 0 {
			return "", nil
		}

		// Remove the matched params
		for _, param := range paramsToRemove {
			query.Del(param)
		}

		// Manually rebuild the query string to preserve existing encoding
		// Instead of using query.Encode() which re-encodes everything
		if len(query) == 0 {
			parsedURL.RawQuery = ""
		} else {
			// Build query string manually from the original RawQuery
			// by removing only the matched parameters
			originalQuery := parsedURL.RawQuery
			newQueryParts := make([]string, 0)

			// Split by & and filter out removed params
			for _, part := range strings.Split(originalQuery, "&") {
				if part == "" {
					continue
				}
				// Get param name (before = or the whole part if no =)
				paramName := part
				if idx := strings.Index(part, "="); idx != -1 {
					paramName = part[:idx]
				}
				// Decode param name to match against our removed list
				decodedName, err := url.QueryUnescape(paramName)
				if err != nil {
					decodedName = paramName
				}

				// Check if this param should be kept
				shouldKeep := true
				for _, removeParam := range paramsToRemove {
					if decodedName == removeParam {
						shouldKeep = false
						break
					}
				}

				if shouldKeep {
					newQueryParts = append(newQueryParts, part)
				}
			}

			parsedURL.RawQuery = strings.Join(newQueryParts, "&")
		}

		result := parsedURL.String()
		if result == from {
			return "", nil
		}
		return result, nil
	}
	return "", nil
}

// MatchRuleWithResult checks if any rule matches the given URL and returns the rewritten URL
func MatchRuleWithResult(rule CommonRule, from string) MatchResult {
	re, err := regexp2.Compile(rule.RegexFilter, 0)
	if err != nil {
		return MatchResult{Match: false, URL: ""}
	}

	matched, err := re.MatchString(from)
	if err != nil {
		return MatchResult{Match: false, URL: ""}
	}

	if matched {
		// Use enhanced replace with URL decoding
		rewrittenURL, err := enhancedReplace(re, from, rule)
		if err != nil {
			return MatchResult{Match: false, URL: ""}
		}

		// For RemoveParams rules, only match if the URL actually changed
		if len(rule.RemoveParams) > 0 {
			if rewrittenURL == "" || rewrittenURL == from {
				return MatchResult{Match: false, URL: ""}
			}
			return MatchResult{Match: true, URL: rewrittenURL}
		}

		return MatchResult{Match: true, URL: rewrittenURL}
	}

	return MatchResult{Match: false, URL: ""}
}

// GetEnabledRules filters and returns only enabled rules
func GetEnabledRules() []CommonRule {
	var enabledRules []CommonRule
	for _, rule := range GetLocalRules() {
		if rule.Enabled {
			enabledRules = append(enabledRules, CommonRule{
				ID:                rule.ID,
				RegexFilter:       rule.From,
				RegexSubstitution: rule.To,
			})
		}
	}
	for _, rule := range GetShareRules() {
		enabledRules = append(enabledRules, CommonRule{
			ID:                rule.ID,
			RegexFilter:       rule.RegexFilter,
			RegexSubstitution: rule.RegexSubstitution,
			RemoveParams:      rule.RemoveParams,
		})
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
func CheckRuleChain(rules []CommonRule, url string, options *CheckOptions) CheckResult {
	maxRedirects := 5
	if options != nil && options.MaxRedirects > 0 {
		maxRedirects = options.MaxRedirects
	}

	var redirectURLs []string
	currentURL := url

	for i := 0; i < maxRedirects; i++ {
		// Find matching rule
		var matchingRule *CommonRule
		for _, rule := range rules {
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
