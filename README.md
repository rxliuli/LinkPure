# LinkPure

A cross-platform application that monitors clipboard URL changes and rewrites them based on user-defined rules.

<img width="1830" height="1158" alt="image" src="https://github.com/user-attachments/assets/2d39acbc-01a4-42d8-bf7f-0b3cc6ec0d40" />

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

## Features

- 🔄 **Automatic URL Rewriting**: Monitors clipboard and rewrites URLs based on matching rules
- 📋 **Rule Management**: Visual interface for managing redirect rules
- 🌐 **Built-in Shared Rules**: 1000+ pre-configured rules for cleaning tracking parameters and unwrapping redirects from popular sites (Google, Amazon, YouTube, Facebook, Twitter, etc.)
- 🧪 **Rule Testing**: Test rule before applying
- 🔔 **System Notifications**: Notifies when URLs are rewritten
- 🌓 **Dark Mode**: System dark mode support

## How It Works

1. The application monitors the system clipboard in the background
2. When a URL is detected, it checks against enabled rules in order
3. If a match is found, the clipboard content is automatically rewritten
4. A system notification is sent to inform the user of the redirect

## Quick Start

### Development Mode

```bash
# Start full application (backend + frontend)
task dev

# Frontend only (browser debugging)
cd frontend
pnpm dev
```

### Build

```bash
# Build application
task build

# Build frontend only
cd frontend
pnpm build
```

## Usage Examples

### Built-in Shared Rules

LinkPure comes with 1000+ pre-configured rules that automatically:

#### Clean Tracking Parameters

- Remove `utm_*`, `fbclid`, `gclid`, and other tracking parameters
- Clean Amazon affiliate tags and tracking IDs
- Strip YouTube tracking parameters (`feature`, `si`, etc.)
- Remove social media tracking codes

#### Unwrap Redirects

- Extract actual URLs from Google redirect links (`/url?q=...`)
- Unwrap Facebook link shim (`l.facebook.com/l.php`)
- Decode Reddit outbound links
- Remove tracking from email links

These rules are embedded in the application and work out of the box. No configuration needed!

### Custom Rule Configuration

You can also create your own rules using regular expressions:

**Example 1: Redirect Google Search to DuckDuckGo**

- From: `^https://www\.google\.com/search\?q=(.*)$`
- To: `https://duckduckgo.com/?q=$1`

**Example 2: Convert YouTube Shorts to Regular Videos**

- From: `https://www\.youtube\.com/shorts/([\w-]+)`
- To: `https://www.youtube.com/watch?v=$1`

**Example 3: Simplify Reddit Notification Links**

- From: `https://www\.reddit\.com/r/(.*?)/comments/(.*?)\?.*&ref_source=email`
- To: `https://www.reddit.com/r/$1/comments/$2`

### Interface Operations

1. **Add Rule**: Click the "Add Rule" button
2. **Edit Rule**: Click the edit icon on the rule card
3. **Enable/Disable**: Use the toggle switch to change rule status
4. **Test Rules**: Click "Test Rules" and enter a URL to see redirect results
5. **Delete Rule**: Click the delete icon to remove a rule

## Tech Stack

### Backend

- **Wails 3**: Cross-platform desktop application framework
- **Golang**: Backend logic and rule matching
- **regexp2**: Advanced regex features support

### Frontend

- **React**: UI framework
- **TanStack Router**: Routing
- **shadcn/ui**: UI component library
- **Tailwind CSS**: Styling
- **next-themes**: Dark mode support

## Project Structure

```txt
.
├── frontend/               # Frontend code
│   ├── src/
│   │   ├── components/    # UI components
│   │   ├── lib/native/    # Native API wrappers
│   │   └── routes/        # Page routes
│   └── bindings/          # Wails-generated TypeScript bindings
├── internal/              # Backend internal packages
│   ├── rules/            # Rule storage and matching logic
│   │   ├── assets/
│   │   │   └── shared-rules.json  # Built-in shared rules (embedded)
│   │   └── sources/      # Rule source files
│   │       ├── custom-rules.json     # Custom rules (tracked in git)
│   │       ├── clearurls-rules.json  # Auto-downloaded ClearURLs rules
│   │       └── linkumori-rules.json  # Auto-downloaded Linkumori rules
│   ├── conf/             # Configuration management
│   └── tray/             # System tray
├── scripts/              # Maintenance scripts
│   ├── download_rules.js  # Download external rules
│   └── merge_sources.js   # Merge rule sources
└── main.go               # Application entry point
```

## Contributing

### Updating Shared Rules

To update the built-in shared rules from external sources:

```bash
# Update all rules
npm run update-rules

# Or step by step
npm run download-rules  # Download latest rules from ClearURLs and Linkumori
npm run merge-sources   # Merge with custom rules
```

The shared rules are sourced from:

- [ClearURLs](https://github.com/ClearURLs/Addon): Comprehensive tracking parameter database
- [Linkumori](https://github.com/Linkumori/Linkumori-Extension): Community-maintained URL parameter removal rules
- [Custom Rules](./internal/rules/sources/custom-rules.json): Manually maintained rules
