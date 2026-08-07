package redis_initialization

import (
	"billionmail-core/internal/service/public"
	"context"
	"crypto/tls"
	"fmt"
	"net"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/gogf/gf/v2/database/gredis"
	"github.com/gogf/gf/v2/frame/g"
)

func redisEnv(name, fallback string) string {
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

// InitRedis initializes the external Redis connection.
func InitRedis() (err error) {
	host := redisEnv("REDISHOST", "")
	port := redisEnv("REDISPORT", "6379")
	user := redisEnv("REDISUSER", "")
	passwd := redisEnv("REDISPASS", "")

	if host == "" {
		return fmt.Errorf("REDISHOST is required")
	}
	if passwd == "" {
		return fmt.Errorf("REDISPASS is required")
	}

	db := 1
	if dbVal, parseErr := strconv.Atoi(redisEnv("REDISDB", "1")); parseErr == nil {
		db = dbVal
	} else {
		return fmt.Errorf("invalid REDISDB: %v", parseErr)
	}

	useTLS, parseErr := strconv.ParseBool(redisEnv("REDIS_TLS", "false"))
	if parseErr != nil {
		return fmt.Errorf("invalid REDIS_TLS: %v", parseErr)
	}

	verifyMode := strings.ToLower(redisEnv("REDIS_TLS_VERIFY", "required"))
	if verifyMode != "required" && verifyMode != "none" {
		return fmt.Errorf("REDIS_TLS_VERIFY must be required or none")
	}
	skipVerify := verifyMode == "none"

	serverName := redisEnv("REDIS_TLS_SERVER_NAME", host)
	address := net.JoinHostPort(strings.Trim(host, "[]"), port)

	config := &gredis.Config{
		Address:       address,
		Db:            db,
		User:          user,
		Pass:          passwd,
		TLS:           useTLS,
		TLSSkipVerify: skipVerify,
	}
	if useTLS {
		config.TLSConfig = &tls.Config{
			MinVersion:         tls.VersionTLS12,
			ServerName:         serverName,
			InsecureSkipVerify: skipVerify, // controlled by REDIS_TLS_VERIFY
		}
	}

	gredis.SetConfig(config)

	connectionOK := false
	for i := 0; i < 10; i++ {
		key := "bm_test_connection"
		if err := g.Redis().SetEX(context.Background(), key, key, 1); err != nil {
			g.Log().Error(context.Background(), "Redis connection test failed: ", err, " Waiting for 5 seconds before retrying...")
			time.Sleep(5 * time.Second)
			continue
		}

		if _, err := g.Redis().Del(context.Background(), key); err != nil {
			g.Log().Error(context.Background(), "Redis connection test failed: ", err, " Waiting for 5 seconds before retrying...")
			time.Sleep(5 * time.Second)
			continue
		}

		connectionOK = true
		g.Log().Debugf(context.Background(), "Redis connection test successful: %s db=%d", address, db)
		break
	}

	if !connectionOK {
		return fmt.Errorf("redis connection test failed after 10 attempts")
	}

	return nil
}
