package ctx

import (
	"os"

	"github.com/wailsapp/wails/v3/pkg/application"
	"github.com/wailsapp/wails/v3/pkg/services/notifications"
)

var (
	app      *application.App
	tray     *application.SystemTray
	trayMenu *application.Menu
	notifier *notifications.NotificationService
)

// Init initializes the context
func Init(a *application.App, t *application.SystemTray, n *notifications.NotificationService) {
	app = a
	tray = t
	notifier = n
}

// IsDevMode returns true if the app is running in development mode
func IsDevMode() bool {
	return os.Getenv("WAILS_VITE_PORT") != ""
}

// GetApp returns the application instance
func GetApp() *application.App {
	return app
}

// GetTray returns the tray instance
func GetTray() *application.SystemTray {
	return tray
}

func GetNotifier() *notifications.NotificationService {
	return notifier
}

func SetTrayMenu(tm *application.Menu) {
	trayMenu = tm
}

func GetTrayMenu() *application.Menu {
	return trayMenu
}
