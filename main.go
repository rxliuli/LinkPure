package main

import (
	"context"
	"crypto/rand"
	"embed"
	"log"
	"time"

	"linkpure/internal/conf"
	"linkpure/internal/ctx"
	"linkpure/internal/envpaths"
	"linkpure/internal/logger"
	"linkpure/internal/permission"
	"linkpure/internal/rules"
	"linkpure/internal/setting"
	"linkpure/internal/tray"
	"linkpure/internal/util"

	"github.com/oklog/ulid/v2"
	"github.com/wailsapp/wails/v3/pkg/application"
	"github.com/wailsapp/wails/v3/pkg/services/notifications"
	"golang.design/x/clipboard"
)

// Wails uses Go's `embed` package to embed the frontend files into the binary.
// Any files in the frontend/dist folder will be embedded into the binary and
// made available to the frontend.
// See https://pkg.go.dev/embed for more information.

//go:embed all:frontend/dist
var assets embed.FS

// main function serves as the application's entry point. It initializes the application, creates a window,
// and starts a goroutine that emits a time-based event every second. It subsequently runs the application and
// logs any error that might occur.
func main() {
	paths, _ := envpaths.EnvPaths("com.rxliuli.linkpure")
	logger.Init(paths.Log)
	logger.Info("Application started")
	rules.SetConfName("LinkPure")
	setting.SetConfName("LinkPure")

	// Create a new Wails application by providing the necessary options.
	// Variables 'Name' and 'Description' are for application metadata.
	// 'Assets' configures the asset server with the 'FS' variable pointing to the frontend files.
	// 'Bind' is a list of Go struct instances. The frontend has access to the methods of these instances.
	// 'Mac' options tailor the application when running an macOS.
	notifier := notifications.New()
	app := application.New(application.Options{
		Name:        "LinePure",
		Description: "A cross-platform application that automatically monitors clipboard URL changes and rewrites them according to rules.",
		Services: []application.Service{
			application.NewService(notifier),
			application.NewService(&GreetService{}),
		},
		Assets: application.AssetOptions{
			Handler: application.AssetFileServerFS(assets),
		},
		Mac: application.MacOptions{
			ApplicationShouldTerminateAfterLastWindowClosed: false,
			ActivationPolicy: application.ActivationPolicyAccessory,
		},
	})

	tray := tray.CreateTray(app)

	ctx.Init(app, tray, notifier)

	// Create a goroutine that emits an event containing the current time every second.
	// The frontend can listen to this event and update the UI accordingly.
	go func() {
		for {
			now := time.Now().Format(time.RFC1123)
			app.Event.Emit("time", now)
			time.Sleep(time.Second)
		}
	}()

	// Initialize clipboard
	err := clipboard.Init()
	if err != nil {
		logger.Info("Failed to initialize clipboard: %v", err)
	} else {
		allow := permission.CheckNotifierPermission(ctx.GetNotifier())
		if !allow {
			logger.Info("No notification permission")
			setting.SetNotificationEnabled(false)
		}
		// Create a goroutine that monitors clipboard changes for URLs
		go monitorClipboard(notifier)
	}

	// Removed automatic permission check - notifications are non-blocking

	// Run the application. This blocks until the application has been exited.
	err = app.Run()

	// If an error occurred while running the application, log it and exit.
	if err != nil {
		log.Fatal(err)
	}
}

// monitorClipboard monitors clipboard changes and applies URL rewrite rules
func monitorClipboard(notifier *notifications.NotificationService) {
	ch := clipboard.Watch(context.Background(), clipboard.FmtText)
	var lastContent string
	for data := range ch {
		if data == nil {
			continue
		}
		content := string(data)
		if content == "" {
			continue
		}
		if content == lastContent {
			continue
		}
		lastContent = content
		if !util.IsURL(content) {
			continue
		}
		// Check if content is a URL and different from the last one
		logger.Info("New URL detected in clipboard: %s", content)

		// Load rules from storage
		rulesList := rules.GetEnabledRules()
		if rulesList == nil {
			logger.Info("No rules configured, skipping URL rewrite")
			continue
		}

		// Try to match and rewrite the URL
		var rewrittenURL string
		var matched bool

		result := rules.CheckRuleChain(rulesList, content, &rules.CheckOptions{MaxRedirects: 5})
		if result.Status == rules.StatusMatched && len(result.URLs) > 0 {
			rewrittenURL = result.URLs[len(result.URLs)-1]
			matched = true
			logger.Info("Rule chain matched: %v", result.URLs)
			logger.Info("URL rewritten: %s -> %s", content, rewrittenURL)
		} else if result.Status == rules.StatusCircularRedirect {
			logger.Info("Circular redirect detected for URL: %s, chain: %v", content, result.URLs)
		} else if result.Status == rules.StatusInfiniteRedirect {
			logger.Info("Infinite redirect detected for URL: %s, chain: %v", content, result.URLs)
		} else {
			logger.Info("No matching rule found for URL: %s", content)
		}

		if matched && rewrittenURL != "" && rewrittenURL != content {
			// Update clipboard with rewritten URL
			clipboard.Write(clipboard.FmtText, []byte(rewrittenURL))
			lastContent = rewrittenURL // Update lastURL to avoid re-processing

			// Send notification about the rewrite only if enabled
			c, err := conf.GetConf("linkpure")
			if err == nil {
				var enabled bool
				c.Get("notificationEnabled", &enabled)
				if enabled {
					notificationID := ulid.MustNew(ulid.Timestamp(time.Now()), rand.Reader).String()
					err := notifier.SendNotification(notifications.NotificationOptions{
						ID:    notificationID,
						Title: "URL Rewritten",
						Body:  rewrittenURL,
					})
					if err != nil {
						logger.Info("Failed to send notification: %v", err)
					}
				}
			}
		}
	}

}
