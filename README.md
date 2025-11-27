# LinkPure

A cross-platform application that monitors clipboard URL changes and rewrites them based on user-defined rules.

<img width="1830" height="1158" alt="image" src="https://github.com/user-attachments/assets/2d39acbc-01a4-42d8-bf7f-0b3cc6ec0d40" />

## Features

- 🔄 **Automatic URL Rewriting**: Monitors clipboard and rewrites URLs based on matching rules
- 📋 **Rule Management**: Visual interface for managing redirect rules
- 🌐 **Built-in Shared Rules**: 1000+ pre-configured rules for cleaning tracking parameters and unwrapping redirects from popular sites (Google, Amazon, YouTube, Facebook, Twitter, etc.)
- 🧪 **Rule Testing**: Test rule before applying
- 🔔 **System Notifications**: Notifies when URLs are rewritten
- 🌓 **Dark Mode**: System dark mode support

## Download

### Desktop

- **macOS**: Intel (AMD64) and Apple Silicon (ARM64)
  - [GitHub Releases](https://github.com/rxliuli/LinkPure/releases/latest)
  - [App Store](https://apps.apple.com/app/id6753670551)
- **Windows**: AMD64 and ARM64
  - [GitHub Releases](https://github.com/rxliuli/LinkPure/releases/latest)
- **Linux**: AMD64 and ARM64
  - [GitHub Releases](https://github.com/rxliuli/LinkPure/releases/latest)

### Mobile

- **Android**: [GitHub Releases](https://github.com/rxliuli/LinkPure/releases/latest)
- **iOS**: [App Store](https://apps.apple.com/app/id6753670551)

### Web

- **Web App**: [linkpure.rxliuli.com](https://linkpure.rxliuli.com)

## How It Works

1. The application monitors the system clipboard in the background
2. When a URL is detected, it checks against enabled rules in order
3. If a match is found, the clipboard content is automatically rewritten
4. A system notification is sent to inform the user of the redirect

## Built-in Shared Rules

LinkPure comes with 1000+ pre-configured rules that work out of the box. No configuration needed!

### Clean Tracking Parameters

Automatically remove common tracking parameters:

- `utm_*`, `fbclid`, `gclid` and other marketing tracking codes
- Amazon affiliate tags and tracking IDs
- YouTube tracking parameters (`feature`, `si`, etc.)
- Social media tracking codes

### Unwrap Redirects

Extract actual URLs from redirect wrappers:

- Google redirect links (`/url?q=...`)
- Facebook link shim (`l.facebook.com/l.php`)
- Reddit outbound links
- Email tracking links

### Update Shared Rules

The shared rules are sourced from:

- [ClearURLs](https://github.com/ClearURLs/Addon): Comprehensive tracking parameter database
- [Linkumori](https://github.com/Linkumori/Linkumori-Extension): Community-maintained URL parameter removal rules
- [Custom Rules](./internal/rules/sources/custom-rules.json): Manually maintained rules

## Custom Rules

Create your own URL rewriting rules using regular expressions.

### Rule Examples

**Redirect Google Search to DuckDuckGo**

- From: `^https://www\.google\.com/search\?q=(.*)$`
- To: `https://duckduckgo.com/?q=$1`

**Convert YouTube Shorts to Regular Videos**

- From: `https://www\.youtube\.com/shorts/([\w-]+)`
- To: `https://www.youtube.com/watch?v=$1`

**Simplify Reddit Notification Links**

- From: `https://www\.reddit\.com/r/(.*?)/comments/(.*?)\?.*&ref_source=email`
- To: `https://www.reddit.com/r/$1/comments/$2`

### Managing Rules

- **Add Rule**: Click the "Add Rule" button
- **Edit Rule**: Click the edit icon on the rule card
- **Enable/Disable**: Use the toggle switch to change rule status
- **Test Rules**: Click "Test Rules" and enter a URL to see redirect results
- **Delete Rule**: Click the delete icon to remove a rule
