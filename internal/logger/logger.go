package logger

import (
	"fmt"
	"io"
	"log"
	"os"
	"path/filepath"
	"time"
)

var (
	infoLogger  *log.Logger
	errorLogger *log.Logger
)

// Init initializes the logger with both console and file output
func Init(logDir string) error {
	// Create log directory if it doesn't exist
	if err := os.MkdirAll(logDir, 0755); err != nil {
		return fmt.Errorf("failed to create log directory: %w", err)
	}

	// Create log file with timestamp
	logFile := filepath.Join(logDir, fmt.Sprintf("app-%s.log", time.Now().Format("2006-01-02")))
	file, err := os.OpenFile(logFile, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0666)
	if err != nil {
		return fmt.Errorf("failed to open log file: %w", err)
	}

	// Create multi-writer for both console and file output
	multiWriter := io.MultiWriter(os.Stdout, file)

	// Initialize loggers
	infoLogger = log.New(multiWriter, "INFO: ", log.Ldate|log.Ltime|log.Lshortfile)
	errorLogger = log.New(multiWriter, "ERROR: ", log.Ldate|log.Ltime|log.Lshortfile)

	return nil
}

// Info logs an info message
func Info(format string, v ...interface{}) {
	infoLogger.Printf(format, v...)
}

// Error logs an error message
func Error(format string, v ...interface{}) {
	errorLogger.Printf(format, v...)
}
