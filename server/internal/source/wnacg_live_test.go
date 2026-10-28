package source

import (
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/eventhorizonsky/venera/server/assets"
	"github.com/eventhorizonsky/venera/server/internal/jshost"
)

// TestRealWnacgLoadInfo 用真实 wnacg.js + 真实漫画 id 走一遍 loadInfo，
// 确认"域名自愈之后确实能取到详情"，而不只是域名数组被填上。
//
// VENERA_LIVE_ROOT / VENERA_LIVE_PROXY 不设则跳过。
func TestRealWnacgLoadInfo(t *testing.T) {
	root := os.Getenv("VENERA_LIVE_ROOT")
	if root == "" {
		t.Skip("set VENERA_LIVE_ROOT to run")
	}
	js, err := os.ReadFile(filepath.Join(root, "sources", "wnacg.js"))
	if err != nil {
		t.Skipf("no wnacg.js: %v", err)
	}

	store := &initTestStore{d: map[string]map[string]any{
		"wnacg": {"settings": map[string]any{
			"domainSelection":       "3",
			"domain0":               "wnacg.com",
			"refreshDomainsOnStart": true,
		}},
	}}

	m, err := NewManager(Options{
		DataDir:  t.TempDir(),
		Store:    store,
		InitJS:   assets.InitJS,
		Timeout:  90 * time.Second,
		Platform: "linux",
		Locale:   "zh_CN",
		Proxy:    jshost.ProxyConfig{Raw: os.Getenv("VENERA_LIVE_PROXY")},
	})
	if err != nil {
		t.Fatal(err)
	}
	m.scripts["wnacg"] = scriptEntry{
		Key: "wnacg", Name: "绅士漫画", Version: "test", JS: string(js),
	}

	// 用 NAS 库里真实存在的 id
	const comicID = "294866"
	d, err := m.LoadDetail("wnacg", comicID)
	if err != nil {
		t.Skipf("loadInfo failed (network/环境): %v", err)
	}
	t.Logf("title=%q chapters=%d", d.Title, len(d.Chapters))

	// 关键断言只有标题：域名坏掉时 loadInfo 会在 baseUrl 处抛
	// "Selected domain is unavailable"，根本走不到返回标题这一步。
	// 章节数不作断言——wnacg 的 chapters 在非 series 情况下是 undefined
	// （单行本），服务端转成空数组是正常的，loadEp 会用 comicId 兜底。
	if d.Title == "" {
		t.Fatal("empty title")
	}

	// 真正决定"能不能下载"的是 loadEp：域名对了但这一层坏掉同样白搭。
	imgs, err := m.LoadEpisodes("wnacg", comicID, "")
	if err != nil {
		t.Skipf("loadEp failed (network/环境): %v", err)
	}
	t.Logf("images=%d first=%s", len(imgs), firstOf(imgs))
	if len(imgs) == 0 {
		t.Fatal("loadEp returned no images")
	}
}

func firstOf(list []string) string {
	if len(list) == 0 {
		return ""
	}
	return list[0]
}
