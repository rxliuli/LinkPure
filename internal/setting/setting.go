package setting

import (
	"linkpure/internal/conf"
	"linkpure/internal/logger"
)

var config *conf.Conf

func SetConfName(filename string) {
	var err error
	config, err = conf.GetConf(filename)
	if err != nil {
		logger.Error("Failed to get conf: %v", err)
	}
}

func GetNotificationEnabled() bool {
	var enabled bool
	if err := config.Get("notificationEnabled", &enabled); err != nil {
		return false
	}
	return enabled
}

func SetNotificationEnabled(enabled bool) error {
	return config.Set("notificationEnabled", enabled)
}
