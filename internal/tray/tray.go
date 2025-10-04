package tray

import (
	"embed"

	"linkpure/internal/ctx"
	"linkpure/internal/window"

	"github.com/wailsapp/wails/v3/pkg/application"
)

//go:embed assets/tray-icon.png
var trayIcon embed.FS

var tray *application.SystemTray

func CreateTray(app *application.App) *application.SystemTray {
	if app == nil {
		panic("app cannot be nil")
	}
	
	tray = app.SystemTray.New()
	if tray == nil {
		panic("failed to create system tray")
	}
	
	iconBytes, _ := trayIcon.ReadFile("assets/tray-icon.png")
	tray.SetTemplateIcon(iconBytes)

	menu := application.NewMenu()
	if menu == nil {
		panic("failed to create menu")
	}
	
	RefreshTrayMenus(app, menu)
	ctx.SetTrayMenu(menu)
	tray.SetMenu(menu)
	return tray
}

func RefreshTrayMenus(app *application.App, menu *application.Menu) {
	menu.Clear()
	menu.Add("Preferences").SetAccelerator("CmdOrCtrl+,").OnClick(func(ctx *application.Context) {
		window.OpenPreferencesWindow(app)
	})
	menu.Add("Quit").SetAccelerator("CmdOrCtrl+Q").OnClick(func(ctx *application.Context) {
		app.Quit()
	})

	// 移除重复的 menu.Update() 调用，因为 tray.SetMenu() 会自动更新
	tray.SetMenu(menu)
}
