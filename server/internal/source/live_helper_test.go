package source

import (
	"database/sql"
	"os"
	"path/filepath"
	"sync"
	"testing"
	"time"

	_ "modernc.org/sqlite"

	"github.com/eventhorizonsky/venera/server/assets"
	"github.com/eventhorizonsky/venera/server/internal/jshost"
	"github.com/eventhorizonsky/venera/server/internal/model"
)

// liveRoot 是本地联调用的数据目录（含 sources/*.js 与 nas.db）。
//
// 这些 live 测试要连真实 nas.db、真实源脚本与真实 Cookie，CI 上不可能具备，
// 所以默认返回空字符串 → 调用方跳过。本地想跑：
//
//	VENERA_LIVE_ROOT=D:/MyProject/venera/_runtime/data go test ./internal/source -run Live
func liveRoot() string {
	return os.Getenv("VENERA_LIVE_ROOT")
}

// readSourceScript 读取服务端磁盘上已安装的源脚本。
func readSourceScript(key string) ([]byte, error) {
	root := liveRoot()
	if root == "" {
		return nil, os.ErrNotExist
	}
	return os.ReadFile(filepath.Join(root, "sources", key+".js"))
}

// liveDBPath 拼出只读打开的 nas.db 路径；没有配置时返回空串。
func liveDBPath() string {
	root := liveRoot()
	if root == "" {
		return ""
	}
	return "file:" + filepath.ToSlash(filepath.Join(root, "nas.db")) + "?mode=ro"
}

// liveCookieStore 从真实 nas.db 读 cookie，用于需要登录态的源。
type liveCookieStore struct {
	db *sql.DB
	mu sync.Mutex
}

func (s *liveCookieStore) GetSourceData(string) (map[string]any, error) {
	return map[string]any{}, nil
}
func (s *liveCookieStore) MergeSourceData(string, map[string]any) error { return nil }

func (s *liveCookieStore) GetCookies(key string) ([]model.CookieRecord, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	rows, err := s.db.Query(
		`SELECT name, value, domain, path, expires FROM source_cookies WHERE source_key = ?`, key)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []model.CookieRecord
	for rows.Next() {
		var name, value, domain, path string
		var expires sql.NullInt64
		if err := rows.Scan(&name, &value, &domain, &path, &expires); err != nil {
			return nil, err
		}
		c := model.CookieRecord{Name: name, Value: value, Domain: domain, Path: path}
		if expires.Valid && expires.Int64 > 0 {
			e := expires.Int64
			c.Expires = &e
		}
		out = append(out, c)
	}
	return out, rows.Err()
}

func (s *liveCookieStore) PutCookies(string, []model.CookieRecord) error { return nil }

// withHostForTest 在测试里以脚本方式执行一段 JS（拿到已 init 的 Host）。
//
// 生产代码不该暴露这种入口；测试需要观测源内部函数，因此单独提供。
func (m *Manager) withHostForTest(key, expr string) (interface{ String() string }, error) {
	var out interface{ String() string }
	err := m.withHost(key, func(h *jshost.Host) error {
		v, err := h.Call(expr)
		if err != nil {
			return err
		}
		out = v
		return nil
	})
	return out, err
}

// newLiveEhentaiManager 构造一个能用真实 ehentai 脚本 + 真实 Cookie 的管理器。
// 条件不具备时返回 ok=false（调用方跳过）。
func newLiveEhentaiManager(t *testing.T) (*Manager, bool) {
	t.Helper()
	dbPath := liveDBPath()
	if dbPath == "" {
		t.Logf("VENERA_LIVE_ROOT not set, skipping live test")
		return nil, false
	}
	db, err := sql.Open("sqlite", dbPath)
	if err != nil {
		t.Logf("no live db: %v", err)
		return nil, false
	}
	store := &liveCookieStore{db: db}
	cks, err := store.GetCookies("ehentai")
	if err != nil || len(cks) == 0 {
		db.Close()
		t.Logf("no ehentai cookies (err=%v n=%d)", err, len(cks))
		return nil, false
	}
	js, err := readSourceScript("ehentai")
	if err != nil {
		db.Close()
		t.Logf("no ehentai script on disk: %v", err)
		return nil, false
	}
	// 代理可选：本地联调通常挂一个，CI 上没有就直连
	proxy := jshost.ProxyConfig{Raw: os.Getenv("VENERA_LIVE_PROXY")}
	m, err := NewManager(Options{
		DataDir:  t.TempDir(),
		Store:    store,
		InitJS:   assets.InitJS,
		Timeout:  120 * time.Second,
		Platform: "linux",
		Locale:   "zh_CN",
		Proxy:    proxy,
	})
	if err != nil {
		db.Close()
		t.Fatalf("new manager: %v", err)
	}
	m.scripts["ehentai"] = scriptEntry{
		Key: "ehentai", Name: "e-hentai", Version: "test", JS: string(js),
	}
	t.Cleanup(func() { db.Close() })
	return m, true
}
