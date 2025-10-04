package conf

import (
	"testing"
)

func TestConfForString(t *testing.T) {
	conf, err := GetConf("test")
	if err != nil {
		t.Errorf("failed to get conf: %v", err)
	}
	var r1 string
	conf.Get("test", &r1)
	if r1 != "" {
		t.Errorf("test should be empty")
	}
	conf.Set("test", "hello")
	var r2 string
	conf.Get("test", &r2)
	if r2 != "hello" {
		t.Errorf("test should be hello")
	}
	conf.Delete("test")
	var r3 string
	conf.Get("test", &r3)
	if r3 != "" {
		t.Errorf("test should be empty")
	}
}

func TestConfForInt(t *testing.T) {
	conf, err := GetConf("test")
	if err != nil {
		t.Errorf("failed to get conf: %v", err)
	}
	var r1 int
	conf.Get("test", &r1)
	if r1 != 0 {
		t.Errorf("test should be 0")
	}
	conf.Set("test", 100)
	var r2 int
	conf.Get("test", &r2)
	if r2 != 100 {
		t.Errorf("test should be 100")
	}
	conf.Delete("test")
	var r3 int
	conf.Get("test", &r3)
	if r3 != 0 {
		t.Errorf("test should be 0")
	}
}

func TestConfForBool(t *testing.T) {
	conf, err := GetConf("test")
	if err != nil {
		t.Errorf("failed to get conf: %v", err)
	}
	var r1 bool
	conf.Get("test", &r1)
	if r1 != false {
		t.Errorf("test should be false")
	}
	conf.Set("test", true)
	var r2 bool
	conf.Get("test", &r2)
	if r2 != true {
		t.Errorf("test should be true")
	}
	conf.Delete("test")
	var r3 bool
	conf.Get("test", &r3)
	if r3 != false {
		t.Errorf("test should be false")
	}
}

func TestConfForStringArray(t *testing.T) {
	conf, err := GetConf("test")
	if err != nil {
		t.Errorf("failed to get conf: %v", err)
	}
	var r1 []string
	conf.Get("test", &r1)
	if len(r1) != 0 {
		t.Errorf("test should be empty")
	}
	conf.Set("test", []string{"hello", "world"})
	var r2 []string
	conf.Get("test", &r2)
	if len(r2) != 2 || r2[0] != "hello" || r2[1] != "world" {
		t.Errorf("test should be hello,world")
	}
	conf.Delete("test")
	var r3 []string
	conf.Get("test", &r3)
	if len(r3) != 0 {
		t.Errorf("test should be empty")
	}
}

func TestConfForStructArray(t *testing.T) {
	conf, err := GetConf("test")
	if err != nil {
		t.Errorf("failed to get conf: %v", err)
	}
	type TestStruct struct {
		ID   int    `json:"id"`
		Name string `json:"name"`
	}
	var r1 []TestStruct
	conf.Get("test", &r1)
	if len(r1) != 0 {
		t.Errorf("test should be empty")
	}
	conf.Set("test", []TestStruct{{ID: 1, Name: "hello"}, {ID: 2, Name: "world"}})
	var r2 []TestStruct
	conf.Get("test", &r2)
	if len(r2) != 2 || r2[0].ID != 1 || r2[0].Name != "hello" || r2[1].ID != 2 || r2[1].Name != "world" {
		t.Errorf("test should be 1,hello and 2,world")
	}
	conf.Delete("test")
	var r3 []TestStruct
	conf.Get("test", &r3)
	if len(r3) != 0 {
		t.Errorf("test should be empty")
	}
}
