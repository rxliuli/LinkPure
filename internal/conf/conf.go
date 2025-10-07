package conf

import (
	"encoding/json"
	"linkpure/internal/envpaths"
	"linkpure/internal/logger"
	"os"
	"path/filepath"
)

type Conf struct {
	name string
	data map[string]interface{}
	path string
}

func GetConf(name string) (*Conf, error) {
	paths, err := envpaths.EnvPaths("com.rxliuli.linkpure2")
	if err != nil {
		return nil, err
	}
	if err := os.MkdirAll(paths.Config, 0755); err != nil {
		return nil, err
	}
	conf := &Conf{
		name: name,
		data: make(map[string]interface{}),
		path: filepath.Join(paths.Config, name+".json"),
	}
	// Log the config file path for debugging
	logger.Info("Config file path: %s", conf.path)
	if data, err := os.ReadFile(conf.path); err == nil {
		json.Unmarshal(data, &conf.data)
	}
	return conf, nil
}

// Get retrieves a value and unmarshals it into the provided type
func (c *Conf) Get(key string, v interface{}) error {
	value, exists := c.data[key]
	if !exists {
		return nil
	}

	bytes, err := json.Marshal(value)
	if err != nil {
		return err
	}

	return json.Unmarshal(bytes, v)
}

func (c *Conf) Set(key string, value interface{}) error {
	c.data[key] = value
	return c.save()
}

func (c *Conf) Delete(key string) error {
	delete(c.data, key)
	return c.save()
}

func (c *Conf) save() error {
	data, err := json.MarshalIndent(c.data, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(c.path, data, 0644)
}
