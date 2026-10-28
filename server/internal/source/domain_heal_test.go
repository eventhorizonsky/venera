package source

import (
	"strings"
	"testing"

	"github.com/eventhorizonsky/venera/server/internal/jshost"
)

// flakySourceJS 是一个"发布页能不能访问由设置控制"的源。
//
// 用 loadSetting 而不是全局变量控制，是因为服务端每次调用都新建 VM，
// 全局变量活不过一次调用；设置则从 source_data 里读，测试可以直接改库。
const flakySourceJS = `
class _Flaky extends ComicSource {
    key = "_flaky"
    name = "flaky"
    version = "1.0.0"

    static domains = []

    async refreshDomains(showDialog) {
        // publishUp 由测试通过设置控制，模拟"发布页可达 / 不可达"
        if (this.loadSetting("publishUp") === true) {
            _Flaky.domains = ["d1.example", "d2.example"]
        }
    }

    overwriteDomains(list) { if (list && list.length) _Flaky.domains = list }

    comic = {
        loadInfo: async (id) => {
            if (_Flaky.domains.length === 0) throw "Selected domain is unavailable"
            return new ComicDetails({
                id: id, title: "ok:" + _Flaky.domains[0], cover: "",
                chapters: new Map([["1", "c1"]]), tags: new Map(), description: "",
            })
        }
    }
}
`

// TestDomainHealRetriesAfterFailure 锁住这个真实缺陷：
//
//	早先 domainHealed 是一次性置位——刷新失败一次，这个源在**整个进程
//	生命周期内**再也不重试，用户点"重试下载"照样报
//	"Selected domain is unavailable"。而刷新失败在真实环境里很常见：
//	发布页（wn01.link）国内直连不通，必须走代理；NAS 刚启动时代理未必就绪。
//
//	现在失败只冷却 domainRetryCooldown，之后会重新尝试。
//
// 注意：这里直接断言"自愈状态"，不经过 loadInfo。
// 走 loadInfo 的话，服务端那条"发布页 301 时自己抓一次"的兜底会真的
// 去联网拿域名，CI 上恰好能连通 → 加载成功 → 测试前提失效。
func TestDomainHealRetriesAfterFailure(t *testing.T) {
	store := &initTestStore{d: map[string]map[string]any{
		"_flaky": {"settings": map[string]any{"publishUp": false}},
	}}
	m := newInitTestManager(t, "_flaky", flakySourceJS, store)

	// 第一次自愈：拿不到域名，状态必须记为失败
	runDomainHeal(t, m, "_flaky")
	if state := domainState(m, "_flaky"); state.ok {
		t.Fatal("failure must not be recorded as success")
	}

	// 失败后处在冷却期内：再调一次不应重新发网络请求，
	// 这里只验证状态没被误判成成功。
	runDomainHeal(t, m, "_flaky")
	if state := domainState(m, "_flaky"); state.ok {
		t.Fatal("still in cooldown, must not become ok")
	}

	// 发布页恢复 + 冷却结束 → 必须能重新刷出来
	setSetting(t, store, "_flaky", "publishUp", true)
	clearDomainState(m, "_flaky")
	runDomainHeal(t, m, "_flaky")

	state := domainState(m, "_flaky")
	if !state.ok {
		t.Fatalf("must retry after cooldown, state=%+v", state)
	}
	if len(state.domains) != 2 || state.domains[0] != "d1.example" {
		t.Fatalf("healed domains = %v", state.domains)
	}

	// 域名注入 JS 环境后 loadInfo 能跑通
	d, err := m.LoadDetail("_flaky", "2")
	if err != nil {
		t.Fatalf("loadInfo after heal: %v", err)
	}
	if !strings.Contains(d.Title, "d1.example") {
		t.Fatalf("healed domain should be used, got %q", d.Title)
	}
}

// TestDomainHealCachesSuccess 确认成功结果被复用，
// 不会每个任务都去打一次发布页。
func TestDomainHealCachesSuccess(t *testing.T) {
	store := &initTestStore{d: map[string]map[string]any{
		"_flaky": {"settings": map[string]any{"publishUp": true}},
	}}
	m := newInitTestManager(t, "_flaky", flakySourceJS, store)

	for i := 0; i < 3; i++ {
		if _, err := m.LoadDetail("_flaky", "1"); err != nil {
			t.Fatalf("attempt %d: %v", i, err)
		}
	}

	m.mu.RLock()
	state := m.domainTried["_flaky"]
	m.mu.RUnlock()
	if !state.ok {
		t.Fatal("success must be recorded")
	}
	if len(state.domains) != 2 || state.domains[0] != "d1.example" {
		t.Fatalf("cached domains = %v", state.domains)
	}
}

// TestClampDomainSelectionWhenOutOfRange 锁住越界这一层：
//
//	domainSelection 是从手机同步来的（例如 3），而发布页这次只给出 2 个
//	域名。源脚本的 get baseUrl() 里 `index >= domains.length` 会直接抛
//	"Selected domain is unavailable"。域名数量由外部决定，我们控制不了，
//	因此把选择落回第 1 个。
func TestClampDomainSelectionWhenOutOfRange(t *testing.T) {
	store := &initTestStore{d: map[string]map[string]any{
		"_flaky": {"settings": map[string]any{
			"publishUp":             true,
			"domainSelection":       "3",
			"domain0":               "keep.me",
			"refreshDomainsOnStart": true,
		}},
	}}
	js := `
class _Flaky extends ComicSource {
    key = "_flaky"
    name = "flaky"
    version = "1.0.0"

    static domains = []

    async refreshDomains(showDialog) {
        _Flaky.domains = ["a.example", "b.example"]
    }

    overwriteDomains(list) { if (list && list.length) _Flaky.domains = list }

    comic = {
        loadInfo: async (id) => {
            let sel = this.loadSetting("domainSelection")
            sel = parseInt(sel)
            if (sel > 0 && sel - 1 >= _Flaky.domains.length) {
                throw "Selected domain is unavailable"
            }
            const idx = sel === 0 ? 0 : sel - 1
            return new ComicDetails({
                id: id, title: "url:" + _Flaky.domains[idx], cover: "",
                chapters: new Map([["1", "c1"]]), tags: new Map(), description: "",
            })
        }
    }
}
`
	m := newInitTestManager(t, "_flaky", js, store)

	// 选择 3 越界 → 这次加载失败，但必须把修正值写回库里
	_, _ = m.LoadDetail("_flaky", "1")

	got, _ := store.GetSourceData("_flaky")
	settings, _ := got["settings"].(map[string]any)
	if settings == nil {
		t.Fatal("settings must survive clamping")
	}
	if settings["domainSelection"] != "1" {
		t.Fatalf("domainSelection should be clamped to 1, got %v", settings["domainSelection"])
	}
	// 同级的其他设置不能被冲掉
	if settings["domain0"] != "keep.me" {
		t.Fatalf("other settings must be preserved, got %v", settings["domain0"])
	}
	if settings["refreshDomainsOnStart"] != true {
		t.Fatalf("refreshDomainsOnStart must be preserved, got %v", settings["refreshDomainsOnStart"])
	}

	// 修正之后应能正常取到第 1 个域名
	clearDomainState(m, "_flaky")
	d, err := m.LoadDetail("_flaky", "2")
	if err != nil {
		t.Fatalf("after clamp, loadInfo should succeed: %v", err)
	}
	if !strings.Contains(d.Title, "a.example") {
		t.Fatalf("expected first domain, got %q", d.Title)
	}
}

func setSetting(t *testing.T, store *initTestStore, key, k string, v any) {
	t.Helper()
	data, _ := store.GetSourceData(key)
	settings, _ := data["settings"].(map[string]any)
	if settings == nil {
		settings = map[string]any{}
	}
	settings[k] = v
	if err := store.MergeSourceData(key, map[string]any{"settings": settings}); err != nil {
		t.Fatalf("set setting: %v", err)
	}
}

// clearDomainState 清掉某源的域名自愈缓存，模拟"冷却时间已过"。
func clearDomainState(m *Manager, key string) {
	m.mu.Lock()
	delete(m.domainTried, key)
	m.mu.Unlock()
}

// runDomainHeal 直接跑一次域名自愈，不经过 loadInfo。
//
// 单独抽出来是因为 loadInfo 会顺带触发服务端那条"发布页 301 时自己抓
// 一次"的兜底，那个动作会真的联网；测试要观察的是自愈状态本身，
// 不能被真实网络影响。
func runDomainHeal(t *testing.T, m *Manager, key string) {
	t.Helper()
	err := m.withHost(key, func(h *jshost.Host) error {
		// withHost 内部已经跑过 ensureDomains，这里无需额外动作
		return nil
	})
	if err != nil {
		t.Fatalf("withHost(%s): %v", key, err)
	}
}

// domainState 读某源的自愈状态。
func domainState(m *Manager, key string) domainHealState {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return m.domainTried[key]
}
