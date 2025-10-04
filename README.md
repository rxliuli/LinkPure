# LinkPure

A cross-platform application that monitors clipboard URL changes and rewrites them based on user-defined rules.

## Features

- 🔄 **Automatic URL Rewriting**: Monitors clipboard and rewrites URLs based on matching rules
- 📋 **Rule Management**: Visual interface for managing redirect rules
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

### Rule Configuration

Rules use regular expressions for matching and rewriting:

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
│   ├── conf/             # Configuration management
│   └── tray/             # System tray
└── main.go               # Application entry point
```
