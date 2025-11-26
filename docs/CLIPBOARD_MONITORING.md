# Clipboard Monitoring Feature

## Overview
The clipboard monitoring feature automatically detects and cleans URLs when they are copied to the clipboard on desktop platforms (Windows, macOS, Linux).

## How It Works

1. **Automatic Detection**: When enabled, the app monitors clipboard changes in the background
2. **URL Validation**: Only processes valid HTTP/HTTPS URLs
3. **URL Cleaning**: Applies all enabled rules to clean the URL
4. **Auto-Replace**: Automatically replaces the clipboard content with the cleaned URL
5. **Notification**: Shows a system notification with before/after comparison
6. **Click Action**: Tap the notification to copy the cleaned URL again

## Usage

### Enable/Disable
1. Go to Settings page
2. Toggle "Auto Monitor Clipboard" switch (Desktop only)
3. The setting is persisted across app restarts

### Features
- **Platform Restriction**: Only available on Windows, macOS, and Linux
- **Debouncing**: 300ms debounce to avoid duplicate processing
- **Smart Detection**: Skips non-URL content and already-processed URLs
- **Background Operation**: Works even when app is not in foreground

## Implementation Details

### Key Components
- `ClipboardService`: Manages clipboard monitoring lifecycle
- `clipboard_watcher`: Third-party package for clipboard events
- `NotificationService`: Handles notification display and interactions

### Settings Storage
- Uses `SharedPreferences` to persist the enabled/disabled state
- Key: `clipboard_monitoring_enabled`

### Notification Behavior
- **Auto-dismiss**: 5 seconds on desktop
- **Clickable**: Tap to copy cleaned URL back to clipboard
- **Payload**: Contains the cleaned URL for later access

## Limitations

1. **Mobile Platforms**: Not available on iOS/Android due to privacy restrictions
2. **Permission**: May require clipboard access permission on some systems
3. **Performance**: Continuous monitoring may have minor battery impact

## Privacy & Security

- Only processes clipboard content locally
- No data is sent to external servers
- Users have full control via the settings toggle
- Only activates when explicitly enabled by user
