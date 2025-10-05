package main

import (
	"linkpure/internal/ctx"
	"linkpure/internal/logger"
	"linkpure/internal/permission"
	"linkpure/internal/rules"
	"linkpure/internal/setting"
	"os"

	"github.com/wailsapp/wails/v3/pkg/application"
)

type GreetService struct{}

func (g *GreetService) GetRules() []rules.LocalRule {
	logger.Info("GreetService.GetRules() called")
	result := rules.GetLocalRules()
	return result
}

func (g *GreetService) NewRule(rule rules.LocalRule) error {
	return rules.NewRule(rule)
}

func (g *GreetService) UpdateRule(rule rules.LocalRule) error {
	return rules.UpdateRule(rule)
}

func (g *GreetService) DeleteRule(id string) error {
	return rules.DeleteRule(id)
}

func (g *GreetService) CheckRuleChain(list []rules.LocalRule, from string) rules.CheckResult {
	return rules.CheckRuleChain(rules.GetEnabledRules(), from, &rules.CheckOptions{MaxRedirects: 5})
}

func (g *GreetService) SaveJsonFile(content string, fileName string) bool {
	app := ctx.GetApp()
	dialog := app.Dialog.SaveFileWithOptions(&application.SaveFileDialogOptions{
		Filename:   fileName,
		Title:      "Save Rules",
		Message:    "Select a location to save the rules",
		ButtonText: "Save",
		Filters: []application.FileFilter{
			{
				DisplayName: "JSON Files",
				Pattern:     "*.json",
			},
		},
	})
	if path, err := dialog.PromptForSingleSelection(); err == nil {
		// Write data to the selected file
		err = os.WriteFile(path, []byte(content), 0644)
		if err != nil {
			return false
		}
		return true
	}
	return false
}

func (g *GreetService) OpenJsonFile() string {
	app := ctx.GetApp()
	dialog := app.Dialog.OpenFileWithOptions(&application.OpenFileDialogOptions{
		Title:          "Open Rules File",
		CanChooseFiles: true,
		Filters: []application.FileFilter{
			{
				DisplayName: "JSON Files (*.json)",
				Pattern:     "*.json",
			},
		},
	})
	if path, err := dialog.PromptForSingleSelection(); err == nil {
		data, err := os.ReadFile(path)
		if err != nil {
			return ""
		}
		return string(data)
	}
	return ""
}

func (g *GreetService) GetNotificationEnabled() bool {
	return setting.GetNotificationEnabled()
}

func (g *GreetService) SetNotificationEnabled(enabled bool) error {
	return setting.SetNotificationEnabled(enabled)
}

func (g *GreetService) CheckNotificationPermission() bool {
	return permission.CheckNotifierPermission(ctx.GetNotifier())
}

func (g *GreetService) RequestNotificationPermission() bool {
	return permission.RequestNotifierPermission(ctx.GetNotifier())
}
