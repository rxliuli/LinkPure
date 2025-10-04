package window

import (
	"fmt"
	"time"

	"github.com/wailsapp/wails/v3/pkg/application"
	"github.com/wailsapp/wails/v3/pkg/events"
)

var preferencesWindow *application.WebviewWindow

// OpenPreferencesWindow opens the preferences window if it's not already open
func OpenPreferencesWindow(app *application.App) {
	if preferencesWindow != nil {
		fmt.Println("Window exists, showing and focusing")
		preferencesWindow.Show()
		preferencesWindow.Focus()
		return
	}

	fmt.Println("Creating new window")
	preferencesWindow = app.Window.NewWithOptions(application.WebviewWindowOptions{
		Title: "LinkPure Preferences",
		URL:   "/",
	})

	preferencesWindow.Show()
	// 延迟聚焦，避免有时无法聚焦的问题
	go func(w *application.WebviewWindow) {
		time.Sleep(100 * time.Millisecond)
		if w != nil {
			w.Focus()
		}
	}(preferencesWindow)

	// Set up window close handler
	preferencesWindow.OnWindowEvent(events.Common.WindowClosing, func(event *application.WindowEvent) {
		fmt.Println("Window closing")
		preferencesWindow = nil
	})
}
