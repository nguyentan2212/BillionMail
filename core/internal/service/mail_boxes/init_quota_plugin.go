package mail_boxes

import (
	"billionmail-core/internal/consts"
	"billionmail-core/internal/service/dockerapi"
	"billionmail-core/internal/service/public"
	"context"
	"errors"
	"fmt"
	"io/ioutil"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"

	"github.com/gogf/gf/v2/frame/g"
	"github.com/gogf/gf/v2/os/gfile"
)

// InitQuotaPluginAndUpdateUsedSpace initializes Dovecot quota support and
// creates maildirsize files for existing mailboxes.
func InitQuotaPluginAndUpdateUsedSpace(ctx context.Context) error {
	if public.HostWorkDir == "" {
		return errors.New("HostWorkDir not set")
	}

	markPath := public.AbsPath("../core/data/quota_init_done.mark")
	if gfile.Exists(markPath) {
		return nil
	}

	confRoot := public.AbsPath("../conf/dovecot")
	if _, err := os.Stat(confRoot); os.IsNotExist(err) {
		return fmt.Errorf("dovecot conf dir not found: %s", confRoot)
	}

	if err := ensureDovecotConf(confRoot); err != nil {
		return err
	}
	if err := ensurePop3Conf(confRoot); err != nil {
		g.Log().Debug(ctx, "Modify 20-pop3.conf err:", err)
		return err
	}
	if err := ensureQuotaConf(confRoot); err != nil {
		g.Log().Debug(ctx, "Modify 90-quota.conf err:", err)
		return err
	}
	if err := recreateSqlConf(confRoot); err != nil {
		g.Log().Debug(ctx, "Rebuild dovecot-sql.conf.ext err:", err)
		return err
	}
	if err := AddMaildirsizeFileForAllMailboxes(ctx); err != nil {
		return err
	}

	if err := gfile.PutContents(markPath, fmt.Sprintf("First sync completed at %s", time.Now().Format("2006-01-02 15:04:05"))); err != nil {
		g.Log().Warningf(ctx, "Failed to create the quota marker file: %v", err)
	}

	if err := reloadDovecot(ctx); err != nil {
		g.Log().Warning(ctx, "reload dovecot failed", err)
	}

	g.Log().Info(ctx, "Quota plugin initialization completed")
	return nil
}

func ensureDovecotConf(confRoot string) error {
	path := filepath.Join(confRoot, "dovecot.conf")
	data, err := ioutil.ReadFile(path)
	if err != nil {
		return fmt.Errorf("read dovecot.conf failed: %w", err)
	}
	content := string(data)

	mailPluginsRe := regexp.MustCompile(`(?m)^\s*mail_plugins\s*=.*$`)
	if mailPluginsRe.MatchString(content) {
		content = mailPluginsRe.ReplaceAllStringFunc(content, func(line string) string {
			if strings.Contains(line, "quota") {
				return line
			}
			return line + " quota"
		})
	} else {
		includeIdx := strings.Index(content, "!include")
		if includeIdx > -1 {
			content = content[:includeIdx] + "mail_plugins = quota\n" + content[includeIdx:]
		} else {
			content = "mail_plugins = quota\n" + content
		}
	}
	return ioutil.WriteFile(path, []byte(content), 0644)
}

func ensurePop3Conf(confRoot string) error {
	path := filepath.Join(confRoot, "conf.d", "20-pop3.conf")

	data, err := ioutil.ReadFile(path)
	if os.IsNotExist(err) {
		tpl := "protocol pop3 {\n  mail_plugins = $mail_plugins\n}\n"
		return ioutil.WriteFile(path, []byte(tpl), 0644)
	}
	if err != nil {
		return err
	}

	content := string(data)
	if !strings.Contains(content, "\n  mail_plugins = $mail_plugins") &&
		!strings.Contains(content, "\n\tmail_plugins = $mail_plugins") &&
		!strings.Contains(content, "^mail_plugins = \\$mail_plugins$") {
		content = strings.ReplaceAll(content, "#mail_plugins = $mail_plugins", "  mail_plugins = $mail_plugins")
		if !strings.Contains(content, "mail_plugins = $mail_plugins") {
			content = strings.Replace(content, "protocol pop3 {", "protocol pop3 {\n  mail_plugins = $mail_plugins", 1)
		}
	}

	return ioutil.WriteFile(path, []byte(content), 0644)
}

func ensureQuotaConf(confRoot string) error {
	path := filepath.Join(confRoot, "conf.d", "90-quota.conf")

	if _, err := os.Stat(path); os.IsNotExist(err) {
		return ioutil.WriteFile(path, []byte("plugin {\n  quota = maildir\n}\n"), 0644)
	}

	data, err := ioutil.ReadFile(path)
	if err != nil {
		return err
	}
	content := string(data)

	if strings.Contains(content, "quota = maildir") &&
		!strings.Contains(content, "#quota = maildir") &&
		!strings.Contains(content, "/*quota = maildir") {
		return nil
	}

	if strings.Contains(content, "plugin {") && !strings.Contains(content, "quota = maildir") {
		content = strings.Replace(content, "plugin {", "plugin {\n  quota = maildir", 1)
	} else {
		content += "\nplugin {\n  quota = maildir\n}\n"
	}

	return ioutil.WriteFile(path, []byte(content), 0644)
}

func mailDatabaseEnv(name, fallback string) string {
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

func recreateSqlConf(confRoot string) error {
	path := filepath.Join(confRoot, "conf.d", "dovecot-sql.conf.ext")

	dbHost := mailDatabaseEnv("DBHOST", "")
	dbPort := mailDatabaseEnv("DBPORT", "5432")
	dbName := mailDatabaseEnv("DBNAME", "billionmail")
	dbUser := mailDatabaseEnv("DBUSER", "billionmail")
	dbPass := mailDatabaseEnv("DBPASS", "")
	sslMode := mailDatabaseEnv("DB_SSLMODE", "disable")

	if dbHost == "" {
		return errors.New("DBHOST is required")
	}
	if dbPass == "" {
		return errors.New("DBPASS is required")
	}

	content := fmt.Sprintf(`driver = pgsql
connect = host=%s port=%s dbname=%s user=%s password=%s sslmode=%s

default_pass_scheme = MD5-CRYPT

user_query = SELECT '/var/vmail/%%d/%%n' as home, 'maildir:/var/vmail/%%d/%%n' as mail, 150 AS uid, 8 AS gid, 'maildir:storage=' || quota AS quota FROM mailbox WHERE username = '%%u' AND active = 1

password_query = SELECT username as user, password, '/var/vmail/%%d/%%n' as userdb_home, 'maildir:/var/vmail/%%d/%%n' as userdb_mail, 150 as userdb_uid, 8 as userdb_gid FROM mailbox WHERE username = '%%u' AND active = 1
`, dbHost, dbPort, dbName, dbUser, dbPass, sslMode)

	if err := ioutil.WriteFile(path, []byte(content), 0644); err != nil {
		return fmt.Errorf("write new dovecot-sql.conf.ext failed: %w", err)
	}
	return nil
}

func AddMaildirsizeFileForAllMailboxes(ctx context.Context) error {
	if _, err := g.DB().Exec(ctx, "ALTER TABLE mailbox ADD COLUMN IF NOT EXISTS quota_active SMALLINT NOT NULL DEFAULT 1"); err != nil {
		g.Log().Warning(ctx, "ensure quota_active column failed", err)
	}

	type Row struct {
		Username    string
		LocalPart   string
		Domain      string
		Quota       int64
		QuotaActive int
	}
	var rows []Row
	if err := g.DB().Model("mailbox").Fields("username, local_part, domain, quota, COALESCE(quota_active,1) as quota_active").Scan(&rows); err != nil {
		return err
	}
	if len(rows) == 0 {
		return nil
	}

	vmailRoot := public.AbsPath("../vmail-data")
	for _, row := range rows {
		userDir := filepath.Join(vmailRoot, row.Domain, row.LocalPart)
		maildirsizePath := filepath.Join(userDir, "maildirsize")

		if err := os.MkdirAll(userDir, 0755); err != nil {
			g.Log().Warning(ctx, "create userDir failed", row.Username, err)
			continue
		}
		if err := public.ChownDovecot(userDir); err != nil {
			g.Log().Warning(ctx, "chown userDir failed", row.Username, err)
		}

		if gfile.Exists(maildirsizePath) {
			if err := public.ChownDovecot(userDir); err != nil {
				g.Log().Warning(ctx, "chown maildirsize failed", row.Username, err)
			}
			continue
		}

		firstLineQuota := int64(0)
		if row.QuotaActive == 1 && row.Quota > 0 {
			firstLineQuota = row.Quota
		}
		content := fmt.Sprintf("%dS\n0 0\n", firstLineQuota)
		if err := gfile.PutContents(maildirsizePath, content); err != nil {
			g.Log().Warning(ctx, "write maildirsize failed", row.Username, err)
			continue
		}
		if err := public.ChownDovecot(userDir); err != nil {
			g.Log().Warning(ctx, "chown maildirsize failed after write", row.Username, err)
		}
		g.Log().Debug(ctx, "created maildirsize", row.Username, maildirsizePath)
	}

	dk, err := docker.NewDockerAPI()
	if err != nil {
		g.Log().Warning(ctx, "docker api init failed", err)
		return err
	}
	defer dk.Close()

	for _, row := range rows {
		if row.QuotaActive == 1 && row.Quota > 0 {
			cmd := []string{"doveadm", "quota", "recalc", "-u", row.Username}
			if _, err = dk.ExecCommandByName(context.Background(), consts.SERVICES.Dovecot, cmd, "root"); err != nil {
				g.Log().Warning(ctx, "doveadm recalc failed", row.Username, err)
			}
		}
	}

	return nil
}

func reloadDovecot(ctx context.Context) error {
	dk, err := docker.NewDockerAPI()
	if err != nil {
		return err
	}
	defer dk.Close()
	_, err = dk.ExecCommandByName(ctx, consts.SERVICES.Dovecot, []string{"dovecot", "reload"}, "root")
	return err
}
