package permission

import (
	"log"
	"os/exec"
	"runtime"

	"github.com/wailsapp/wails/v3/pkg/services/notifications"
)

func CheckNotifierPermission(notifier *notifications.NotificationService) bool {
	authorized, err := notifier.CheckNotificationAuthorization()
	if err != nil {
		log.Printf("Failed to check notification authorization: %v", err)
		return false
	}
	return authorized
}

func RequestNotifierPermission(notifier *notifications.NotificationService) bool {
	authorized, err := notifier.RequestNotificationAuthorization()
	if err != nil {
		log.Printf("Failed to request notification authorization: %v", err)
		// If request failed (likely because user previously denied), open system settings
		if err := OpenNotificationSettings(); err != nil {
			log.Printf("Failed to open notification settings: %v", err)
		}
		return false
	}
	return authorized
}

func OpenNotificationSettings() error {
	var cmd *exec.Cmd

	switch runtime.GOOS {
	case "darwin":
		// macOS: Open System Settings > Notifications
		cmd = exec.Command("open", "x-apple.systempreferences:com.apple.preference.notifications")
	case "windows":
		// Windows: Open Settings > System > Notifications
		cmd = exec.Command("cmd", "/c", "start", "ms-settings:notifications")
	case "linux":
		// Linux: Try common settings apps
		// Try GNOME first
		if err := exec.Command("gnome-control-center", "notifications").Run(); err == nil {
			return nil
		}
		// Try KDE
		if err := exec.Command("systemsettings5", "kcm_notifications").Run(); err == nil {
			return nil
		}
		// Fallback: open general settings
		cmd = exec.Command("xdg-open", "settings:")
	default:
		log.Printf("Unsupported platform: %s", runtime.GOOS)
		return nil
	}

	if cmd != nil {
		if err := cmd.Start(); err != nil {
			log.Printf("Failed to open notification settings: %v", err)
			return err
		}
	}

	return nil
}
