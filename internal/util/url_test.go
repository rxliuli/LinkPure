package util

import (
	"testing"
)

func TestIsURL(t *testing.T) {
	tests := []struct {
		input    string
		expected bool
	}{
		{"http://example.com", true},
		{"https://example.com", true},
		{"https://localhost:8080", true},
		{"ftp://example.com", false},
		{"example.com", false},
		{"", false},
		{"   ", false},
		{"http:/example.com", false},
	}

	for _, test := range tests {
		result := IsURL(test.input)
		if result != test.expected {
			t.Errorf("IsURL(%q) = %v; want %v", test.input, result, test.expected)
		}
	}
}

func TestDecodeURIComponent(t *testing.T) {
	tests := []struct {
		input    string
		expected string
	}{
		{"hello%20world", "hello world"},
		{"%E4%BD%A0%E5%A5%BD", "你好"},
		{"simple", "simple"},
		{"", ""},
		{"https://www.google.com/search?q=%E6%B5%8B%E8%AF%95+JavaScript", "https://www.google.com/search?q=测试+JavaScript"},
	}

	for _, test := range tests {
		result, err := DecodeURIComponent(test.input)
		if err != nil {
			t.Errorf("DecodeURIComponent(%q) returned error: %v", test.input, err)
			continue
		}
		if result != test.expected {
			t.Errorf("DecodeURIComponent(%q) = %q; want %q", test.input, result, test.expected)
		}
	}
}
