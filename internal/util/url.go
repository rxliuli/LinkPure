package util

import (
	"net/url"
	"strings"
)

// IsURL checks if a string is a valid URL
func IsURL(str string) bool {
	str = strings.TrimSpace(str)
	if str == "" {
		return false
	}

	// Parse the URL
	parsedURL, err := url.ParseRequestURI(str)
	if err != nil {
		return false
	}

	// Check if it has a valid scheme and host
	return parsedURL.Scheme != "" &&
		(parsedURL.Scheme == "http" || parsedURL.Scheme == "https") &&
		parsedURL.Host != ""
}

func DecodeURIComponent(encoded string) (string, error) {
	return url.PathUnescape(encoded)
}
