package database_initialization

import (
	"billionmail-core/internal/service/public"
	"context"
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/gogf/gf/v2/database/gdb"
	"github.com/gogf/gf/v2/frame/g"
)

var registeredHandlers = make([]func(), 0, 256)

func databaseEnv(name, fallback string) string {
	if value := strings.TrimSpace(os.Getenv(name)); value != "" {
		return value
	}
	if value, err := public.DockerEnv(name); err == nil {
		if value = strings.TrimSpace(value); value != "" {
			return value
		}
	}
	return fallback
}

// InitDatabase initializes the database configuration.
func InitDatabase() (err error) {
	dbHost := databaseEnv("DBHOST", "")
	dbPort := databaseEnv("DBPORT", "5432")
	dbName := databaseEnv("DBNAME", "billionmail")
	dbUser := databaseEnv("DBUSER", "billionmail")
	dbPass := databaseEnv("DBPASS", "")
	sslMode := strings.ToLower(databaseEnv("DB_SSLMODE", "disable"))

	if dbHost == "" {
		return fmt.Errorf("DBHOST is required")
	}
	if dbPass == "" {
		return fmt.Errorf("DBPASS is required")
	}

	switch sslMode {
	case "disable", "allow", "prefer", "require", "verify-ca", "verify-full":
	default:
		return fmt.Errorf("unsupported DB_SSLMODE: %s", sslMode)
	}

	err = gdb.SetConfig(gdb.Config{
		"default": gdb.ConfigGroup{
			gdb.ConfigNode{
				Host:             dbHost,
				Port:             dbPort,
				User:             dbUser,
				Pass:             dbPass,
				Name:             dbName,
				Type:             "pgsql",
				Extra:            "sslmode=" + sslMode,
				Role:             "master",
				MaxOpenConnCount: 100,
			},
		},
	})
	if err != nil {
		return fmt.Errorf("set database configuration failed: %v", err)
	}

	connectionOK := false
	for i := 0; i < 10; i++ {
		_, err = g.DB().Exec(context.Background(), "SELECT 1")
		if err != nil {
			g.Log().Debug(context.Background(), "Database connection failed, retrying in 5 seconds...")
			time.Sleep(5 * time.Second)
			continue
		}

		connectionOK = true
		g.Log().Debugf(context.Background(), "Database connection successful: %s:%s/%s", dbHost, dbPort, dbName)
		break
	}

	if !connectionOK {
		return fmt.Errorf("database connection test failed after 10 attempts")
	}

	for _, handler := range registeredHandlers {
		if handler != nil {
			handler()
		}
	}

	registeredHandlers = registeredHandlers[:0]
	return nil
}

// registerHandler registers a handler for the database initialization.
func registerHandler(handler func()) {
	if handler == nil {
		return
	}
	registeredHandlers = append(registeredHandlers, handler)
}
