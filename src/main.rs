//! ddir - Desktop Director (Windows backend, v0.1)
//! Lease-based window / software orchestration for AI agents.

mod store;
mod win;

use std::process::exit;
use win::{Display, WinInfo};

const VERSION: &str = env!("CARGO_PKG_VERSION");
const GAP: i32 = 16;
const LEASE_TTL: u64 = 300;

fn esc(s: &str) -> String {
    let mut o = String::with_capacity(s.len() + 8);
    for c in s.chars() {
        match c {
            '"' => o.push_str("\\\""),
            '\\' => o.push_str("\\\\"),
            '\n' => o.push_str("\\n"),
            '\r' => o.push_str("\\r"),
            '\t' => o.push_str("\\t"),
            c if (c as u32) < 0x20 => o.push_str(&format!("\\u{:04x}", c as u32)),
            c => o.push(c),
        }
    }
    o
}

fn rect_json(r: &[i32; 4]) -> String {
    format!("[{},{},{},{}]", r[0], r[1], r[2], r[3])
}

fn arg(args: &[String], name: &str) -> Option<String> {
    let mut i = 0;
    while i < args.len() {
        if args[i] == name && i + 1 < args.len() {
            return Some(args[i + 1].clone());
        }
        if let Some(v) = args[i].strip_prefix(&format!("{}=", name)) {
            return Some(v.to_string());
        }
        i += 1;
    }
    None
}

fn has_flag(args: &[String], name: &str) -> bool {
    args.iter().any(|a| a == name)
}

fn positional(args: &[String]) -> Vec<String> {
    args.iter()
        .filter(|a| !a.starts_with("--"))
        .cloned()
        .collect()
}

// ---------- activity ----------

fn activity() -> (i64, i32, bool, bool) {
    let cur = win::cursor();
    let fg = win::foreground_hex();
    let p = store::home().join("activity.tsv");
    let prev = std::fs::read_to_string(&p).unwrap_or_default();
    let mut moved = 0;
    let mut fg_changed = false;
    if !prev.trim().is_empty() {
        let f: Vec<&str> = prev.trim().split('\t').collect();
        if f.len() >= 3 {
            let px: i32 = f[0].parse().unwrap_or(cur.0);
            let py: i32 = f[1].parse().unwrap_or(cur.1);
            let pfg = f[2];
            moved = (cur.0 - px).abs() + (cur.1 - py).abs();
            fg_changed = pfg != fg;
        }
    }
    let _ = std::fs::write(&p, format!("{}\t{}\t{}", cur.0, cur.1, fg));
    let idle = win::idle_seconds();
    let active = moved > 25 || fg_changed;
    (idle, moved, fg_changed, active)
}

// ---------- displays ----------

fn displays_json(ds: &[Display]) -> String {
    let items: Vec<String> = ds
        .iter()
        .map(|d| {
            format!(
                "{{\"uid\":\"{}\",\"gdi\":\"{}\",\"label\":\"{}\",\"primary\":{},\"managed\":{},\"monitor\":{},\"work\":{}}}",
                esc(&d.uid),
                esc(&d.gdi),
                esc(&d.label),
                d.primary,
                d.managed,
                rect_json(&d.monitor),
                rect_json(&d.work)
            )
        })
        .collect();
    format!("[{}]", items.join(","))
}

// ---------- layout ----------

/// Equal-width columns so windows sit **side by side** instead of stacking on top of each other.
fn layout_for(count: usize, work: [i32; 4]) -> Vec<[i32; 4]> {
    let (wx, wy, ww, wh) = (work[0], work[1], work[2], work[3]);
    let n = count.max(1) as i32;
    if n == 1 {
        return vec![[wx + GAP, wy + GAP, ww - 2 * GAP, wh - 2 * GAP]];
    }
    let col = (ww - (n + 1) * GAP) / n;
    (0..n)
        .map(|i| [wx + GAP + i * (col + GAP), wy + GAP, col, wh - 2 * GAP])
        .collect()
}

struct Need {
    name: String,
}

fn parse_needs(spec: &str) -> Vec<Need> {
    if spec.trim().is_empty() {
        return vec![Need { name: String::new() }];
    }
    spec.split(',')
        .map(|s| s.trim())
        .filter(|s| !s.is_empty())
        .map(|s| {
            let name = s.split(':').next().unwrap_or("").trim().to_string();
            Need { name }
        })
        .take(3)
        .collect()
}

fn matches(w: &WinInfo, name: &str) -> bool {
    if name.is_empty() {
        return true;
    }
    let n = name.to_lowercase();
    w.app.to_lowercase().contains(&n)
        || w.title.to_lowercase().contains(&n)
        || w.class.to_lowercase().contains(&n)
}

// ---------- commands ----------

fn cmd_mode(args: &[String]) -> i32 {
    if let Some(m) = positional(args).first() {
        if let Err(e) = store::set_mode(m) {
            println!("{{\"ok\":false,\"error\":\"{}\"}}", esc(&e));
            return 1;
        }
        store::audit("mode", m);
    }
    let (idle, moved, fg, active) = activity();
    println!(
        "{{\"ok\":true,\"mode\":\"{}\",\"agent\":\"{}\",\"input_age_s\":{},\"user_active\":{},\"cursor_moved_px\":{},\"foreground_changed\":{},\"signal\":\"cursor+foreground\"}}",
        store::mode(),
        esc(&win::agent_id()),
        idle,
        active,
        moved,
        fg
    );
    0
}

fn cmd_displays() -> i32 {
    let ds = win::displays();
    let managed: Vec<Display> = ds.iter().filter(|d| d.managed).cloned().collect();
    let user: Vec<Display> = ds.iter().filter(|d| !d.managed).cloned().collect();
    println!(
        "{{\"ok\":true,\"platform\":\"windows\",\"managed\":{},\"user\":{}}}",
        displays_json(&managed),
        displays_json(&user)
    );
    0
}

fn cmd_list(args: &[String]) -> i32 {
    let ws = win::list_windows();
    if has_flag(args, "--text") {
        for w in &ws {
            println!(
                "{}\t{}\t{}\t{}\t{}",
                w.hex,
                w.app,
                w.display,
                format!("{},{},{},{}", w.frame[0], w.frame[1], w.frame[2], w.frame[3]),
                w.title
            );
        }
        return 0;
    }
    let items: Vec<String> = ws
        .iter()
        .map(|w| {
            format!(
                "{{\"hwnd\":\"{}\",\"app\":\"{}\",\"class\":\"{}\",\"title\":\"{}\",\"display\":\"{}\",\"rect\":{},\"win\":{},\"dpi\":{},\"maximized\":{},\"minimized\":{},\"foreground\":{}}}",
                w.hex,
                esc(&w.app),
                esc(&w.class),
                esc(&w.title),
                esc(&w.display),
                rect_json(&w.frame),
                rect_json(&w.win),
                w.dpi,
                w.maximized,
                w.minimized,
                w.foreground
            )
        })
        .collect();
    println!("{{\"ok\":true,\"count\":{},\"windows\":[{}]}}", items.len(), items.join(","));
    0
}

fn caps_json() -> String {
    "{\"window_move\":true,\"window_hide\":\"window\",\"window_close\":true,\"focus_control\":true,\"display_enumerate\":true,\"thumbnail\":true,\"idle_signal\":\"input\"}".into()
}

fn cmd_status() -> i32 {
    let me = win::agent_id();
    let now = store::now_unix();
    let all = store::leases();
    let live: Vec<_> = all.iter().filter(|l| l.expires > now).cloned().collect();
    let mine: Vec<_> = live.iter().filter(|l| l.agent == me).cloned().collect();
    let others = live.len() - mine.len();
    let apps = store::apps();
    let owns: Vec<String> = apps
        .iter()
        .filter(|a| a.owner == me && a.since + a.ttl > now)
        .map(|a| format!("\"{}\"", esc(&a.app)))
        .collect();
    let wins: Vec<String> = mine
        .iter()
        .map(|l| format!("{{\"window\":\"{}\",\"action\":\"{}\",\"expires\":{}}}", esc(&l.window), esc(&l.action), l.expires))
        .collect();
    let (idle, moved, fg, active) = activity();
    println!(
        "{{\"ok\":true,\"platform\":\"windows\",\"mode\":\"{}\",\"you\":\"{}\",\"leases\":{},\"lease\":\"{}\",\"windows\":[{}],\"held_by_others\":{},\"owns\":[{}],\"focus_holder\":\"none\",\"input_age_s\":{},\"user_active\":{},\"cursor_moved_px\":{},\"foreground_changed\":{},\"version\":\"{}\",\"caps\":{}}}",
        store::mode(),
        esc(&me),
        mine.len(),
        mine.first().map(|l| esc(&l.lease)).unwrap_or_default(),
        wins.join(","),
        others,
        owns.join(","),
        idle,
        active,
        moved,
        fg,
        VERSION,
        caps_json()
    );
    0
}

fn quota_exceeded() -> i32 {
    println!("{{\"ok\":false,\"error\":\"quota_exceeded\",\"hint\":\"单 Agent 最多 3 个窗口；先 release 不用的\"}}");
    0
}

fn cmd_claim(args: &[String], dry: bool) -> i32 {
    let mode = store::mode();
    if mode == "off" {
        println!("{{\"ok\":false,\"error\":\"mode_off\",\"hint\":\"用户没开启 ddir\"}}");
        return 0;
    }
    let me = win::agent_id();
    let (_, _, _, active) = activity();
    if active && !has_flag(args, "--force") {
        println!("{{\"ok\":false,\"error\":\"user_active\",\"hint\":\"用户正在操作；等它空闲，或加 --force\"}}");
        return 0;
    }
    let managed = win::managed_displays();
    if managed.is_empty() {
        println!("{{\"ok\":false,\"error\":\"display_not_managed\",\"hint\":\"没有托管屏\"}}");
        return 0;
    }
    let spec = arg(args, "--needs").or_else(|| positional(args).first().cloned()).unwrap_or_default();
    let needs = parse_needs(&spec);
    let now = store::now_unix();
    let live: Vec<store::Lease> = store::leases().into_iter().filter(|l| l.expires > now).collect();
    let busy: Vec<store::Lease> = live.iter().filter(|l| l.agent != me).cloned().collect();

    let managed_ids: Vec<String> = managed.iter().map(|d| d.uid.clone()).collect();
    let wins: Vec<WinInfo> = win::list_windows()
        .into_iter()
        .filter(|w| managed_ids.contains(&w.display))
        .collect();

    // Start from what this agent already holds, then add whatever the new request needs.
    // Everything gets laid out again, so opening a new window never buries the old ones.
    let mut targets: Vec<(WinInfo, Option<store::Lease>)> = Vec::new();
    for l in live.iter().filter(|l| l.agent == me) {
        if let Some(w) = wins.iter().find(|w| w.hex.eq_ignore_ascii_case(&l.window)) {
            if !w.minimized {
                targets.push((w.clone(), Some(l.clone())));
            }
        }
    }
    let mut blocked: Option<store::Lease> = None;
    for need in needs.iter() {
        let mut chosen: Option<&WinInfo> = None;
        for w in &wins {
            if targets.iter().any(|(t, _)| t.hwnd == w.hwnd) || w.minimized || !matches(w, &need.name) {
                continue;
            }
            if let Some(b) = busy.iter().find(|b| b.window == w.hex) {
                blocked = Some(b.clone());
                continue;
            }
            chosen = Some(w);
            break;
        }
        if let Some(w) = chosen {
            targets.push((w.clone(), None));
        }
    }
    if targets.len() > 3 {
        return quota_exceeded();
    }
    if targets.is_empty() {
        if let Some(b) = blocked {
            let left = b.expires.saturating_sub(now);
            println!(
                "{{\"ok\":false,\"error\":\"window_owned_by\",\"window\":\"{}\",\"owner_agent\":\"{}\",\"expires_in_s\":{},\"hint\":\"该窗口正被另一个 Agent 使用；换窗口，或等它 release\"}}",
                esc(&b.window), esc(&b.agent), left
            );
        } else {
            println!("{{\"ok\":false,\"error\":\"no_window\",\"hint\":\"没有匹配到托管屏上的窗口；先打开目标软件\"}}");
        }
        return 0;
    }

    let cells = layout_for(targets.len(), managed[0].work);
    let plan: Vec<(WinInfo, [i32; 4], Option<store::Lease>, [i32; 4])> = targets
        .iter()
        .enumerate()
        .map(|(i, (w, l))| {
            let from = l.as_ref().map(|x| x.from).unwrap_or(w.win);
            (w.clone(), cells[i], l.clone(), from)
        })
        .collect();

    let assign_json: Vec<String> = plan
        .iter()
        .map(|(w, r, l, f)| {
            format!(
                "{{\"window\":\"{}\",\"app\":\"{}\",\"title\":\"{}\",\"display\":\"{}\",\"from\":{},\"rect\":{},\"retiled\":{}}}",
                w.hex, esc(&w.app), esc(&w.title), esc(&w.display), rect_json(f), rect_json(r), l.is_some()
            )
        })
        .collect();
    let managed_uid_json = managed_ids.iter().map(|s| format!("\"{}\"", esc(s))).collect::<Vec<_>>().join(",");

    if dry {
        println!(
            "{{\"ok\":true,\"dry_run\":true,\"mode\":\"{}\",\"displays_managed\":[{}],\"assign\":[{}],\"focus\":\"none\"}}",
            esc(&mode), managed_uid_json, assign_json.join(",")
        );
        return 0;
    }

    let lease_id = format!("ls_{:06x}", (now as u32) ^ std::process::id());
    let mut all: Vec<store::Lease> = Vec::new();
    for l in live.iter() {
        if l.agent == me {
            if let Some((_, r, _, _)) = plan.iter().find(|(w, _, _, _)| w.hex.eq_ignore_ascii_case(&l.window)) {
                // refresh the lease, keep its original `from` so release still restores the user's layout
                all.push(store::Lease { to: *r, expires: now + LEASE_TTL, ..l.clone() });
                continue;
            }
            // window is gone: drop the stale lease
            if wins.iter().all(|w| !w.hex.eq_ignore_ascii_case(&l.window)) {
                continue;
            }
        }
        all.push(l.clone());
    }
    for (w, r, l, f) in &plan {
        win::set_rect(w.hwnd, *r);
        if l.is_none() {
            all.push(store::Lease {
                window: w.hex.clone(),
                agent: me.clone(),
                action: "move".into(),
                from: *f,
                to: *r,
                expires: now + LEASE_TTL,
                lease: lease_id.clone(),
            });
        }
    }
    store::save_leases(&all);
    let retiled = plan.iter().filter(|(_, _, l, _)| l.is_some()).count();
    store::audit("claim", &format!("lease={} windows={} retiled={}", lease_id, plan.len(), retiled));
    println!(
        "{{\"ok\":true,\"lease\":\"{}\",\"mode\":\"{}\",\"displays_managed\":[{}],\"assign\":[{}],\"retiled\":{},\"focus\":\"none\",\"ttl_s\":{}}}",
        lease_id, esc(&mode), managed_uid_json, assign_json.join(","), retiled, LEASE_TTL
    );
    0
}
fn cmd_move(args: &[String]) -> i32 {
    let hwnd = match arg(args, "--window").and_then(|s| win::parse_hwnd(&s)) {
        Some(h) => h,
        None => {
            println!("{{\"ok\":false,\"error\":\"invalid_args\",\"hint\":\"move --window 0x... --rect x,y,w,h\"}}");
            return 0;
        }
    };
    let rect_s = arg(args, "--rect").unwrap_or_default();
    let parts: Vec<i32> = rect_s.split(',').filter_map(|s| s.trim().parse().ok()).collect();
    if parts.len() != 4 {
        println!("{{\"ok\":false,\"error\":\"invalid_args\",\"hint\":\"--rect x,y,w,h\"}}");
        return 0;
    }
    let (_, _, _, active) = activity();
    if active && !has_flag(args, "--force") {
        println!("{{\"ok\":false,\"error\":\"user_active\",\"hint\":\"用户正在操作；等它空闲，或加 --force\"}}");
        return 0;
    }
    let ok = win::set_rect(hwnd, [parts[0], parts[1], parts[2], parts[3]]);
    store::audit("move", &format!("{} {:?}", hwnd, parts));
    println!(
        "{{\"ok\":{},\"window\":\"0x{:08X}\",\"rect\":{}}}",
        ok, hwnd as u64, rect_json(&[parts[0], parts[1], parts[2], parts[3]])
    );
    0
}

fn cmd_show_hide(args: &[String], hide: bool) -> i32 {
    let hwnd = match arg(args, "--window").and_then(|s| win::parse_hwnd(&s)) {
        Some(h) => h,
        None => {
            println!("{{\"ok\":false,\"error\":\"invalid_args\"}}");
            return 0;
        }
    };
    if hide {
        win::hide(hwnd);
    } else {
        win::show(hwnd);
    }
    store::audit(if hide { "hide" } else { "show" }, &format!("{}", hwnd));
    println!("{{\"ok\":true,\"window\":\"0x{:08X}\",\"hidden\":{}}}", hwnd as u64, hide);
    0
}

fn owned_by_me(app: &str, me: &str) -> Result<(), String> {
    let now = store::now_unix();
    let apps = store::apps();
    match apps.iter().find(|a| a.app.eq_ignore_ascii_case(app)) {
        None => Err("not_owned".into()),
        Some(a) if a.since + a.ttl <= now => Err("not_owned".into()),
        Some(a) if a.owner != me => Err(format!("owned_by_other:{}", a.owner)),
        Some(_) => Ok(()),
    }
}

fn cmd_close(args: &[String]) -> i32 {
    let hwnd = match arg(args, "--window").and_then(|s| win::parse_hwnd(&s)) {
        Some(h) => h,
        None => {
            println!("{{\"ok\":false,\"error\":\"invalid_args\"}}");
            return 0;
        }
    };
    let ws = win::list_windows();
    let w = match ws.iter().find(|w| w.hwnd == hwnd) {
        Some(w) => w.clone(),
        None => {
            println!("{{\"ok\":false,\"error\":\"no_window\"}}");
            return 0;
        }
    };
    let me = win::agent_id();
    match owned_by_me(&w.app, &me) {
        Err(e) if e.starts_with("owned_by_other") => {
            let owner = e.split(':').nth(1).unwrap_or("?");
            println!("{{\"ok\":false,\"error\":\"owned_by_other\",\"owner_agent\":\"{}\"}}", esc(owner));
            return 0;
        }
        Err(_) => {
            println!("{{\"ok\":false,\"error\":\"not_owned\",\"hint\":\"先 ddir own --app \\\"{}\\\" 认领\"}}", esc(&w.app));
            return 0;
        }
        Ok(_) => {}
    }
    win::close_graceful(hwnd);
    let mut dead = false;
    for _ in 0..30 {
        std::thread::sleep(std::time::Duration::from_millis(100));
        if !win::is_window(hwnd) {
            dead = true;
            break;
        }
    }
    store::audit("close", &format!("{} {} dead={}", w.hex, w.app, dead));
    if dead {
        println!("{{\"ok\":true,\"closed\":true,\"window\":\"{}\",\"app\":\"{}\"}}", esc(&w.hex), esc(&w.app));
    } else {
        println!(
            "{{\"ok\":false,\"error\":\"close_blocked\",\"window\":\"{}\",\"reason\":\"3 秒内未退出（可能有未保存内容），不重试、不强杀\"}}",
            esc(&w.hex)
        );
    }
    0
}

fn cmd_own(args: &[String], disown: bool) -> i32 {
    let app = match arg(args, "--app") {
        Some(a) => a,
        None => {
            println!("{{\"ok\":false,\"error\":\"invalid_args\",\"hint\":\"own --app <name>\"}}");
            return 0;
        }
    };
    let me = win::agent_id();
    let now = store::now_unix();
    let mut apps = store::apps();
    let idx = apps.iter().position(|a| a.app.eq_ignore_ascii_case(&app));
    if disown {
        if let Some(i) = idx {
            apps.remove(i);
            store::save_apps(&apps);
        }
        store::audit("disown", &app);
        println!("{{\"ok\":true,\"app\":\"{}\"}}", esc(&app));
        return 0;
    }
    if let Some(i) = idx {
        let a = &apps[i];
        let alive = a.since + a.ttl > now;
        if alive && a.owner != me {
            println!(
                "{{\"ok\":false,\"error\":\"owned_by_other\",\"owner_agent\":\"{}\",\"owner_since\":{},\"hint\":\"换实例或等它 disown\"}}",
                esc(&a.owner),
                a.since
            );
            return 0;
        }
        apps.remove(i);
    }
    apps.push(store::AppOwner { app: app.clone(), owner: me.clone(), since: now, ttl: 1800 });
    store::save_apps(&apps);
    store::audit("own", &app);
    println!("{{\"ok\":true,\"app\":\"{}\",\"owner\":\"{}\"}}", esc(&app), esc(&me));
    0
}

fn cmd_release() -> i32 {
    let me = win::agent_id();
    let now = store::now_unix();
    let all = store::leases();
    let (mine, others): (Vec<_>, Vec<_>) = all.into_iter().partition(|l| l.agent == me && l.expires > now);
    let mut n = 0;
    for l in &mine {
        if let Some(h) = win::parse_hwnd(&l.window) {
            if l.action == "hide" {
                win::show(h);
            } else {
                win::set_rect(h, l.from);
            }
            n += 1;
        }
    }
    store::save_leases(&others);
    store::audit("release", &format!("restored={}", n));
    println!("{{\"ok\":true,\"released\":{},\"other_leases_kept\":{}}}", n, others.len());
    0
}

fn cmd_board() -> i32 {
    let me = win::agent_id();
    let now = store::now_unix();
    let live: Vec<_> = store::leases().into_iter().filter(|l| l.expires > now).collect();
    let (idle, moved, _fg, active) = activity();
    println!("== ddir v{}  mode {}  you {}  input_age={}s user_active={} cursor_moved={}px", VERSION, store::mode(), me, idle, active, moved);
    let ws = win::list_windows();
    println!("== windows {}  displays {}", ws.len(), win::displays().len());
    if live.is_empty() {
        println!("== no lease");
    } else {
        for l in &live {
            println!("== lease {}  {}  {}  expires_in {}s", l.lease, l.agent, l.window, l.expires.saturating_sub(now));
        }
    }
    for a in store::apps() {
        if a.since + a.ttl > now {
            println!("== owned {} -> {}", a.app, a.owner);
        }
    }
    0
}

fn cmd_selftest() -> i32 {
    let mut pass = 0;
    let mut fail = 0;
    let mut check = |name: &str, ok: bool, detail: &str| {
        if ok {
            pass += 1;
            println!("PASS  {}", name);
        } else {
            fail += 1;
            println!("FAIL  {}  {}", name, detail);
        }
    };
    let ds = win::displays();
    check("displays>=1", !ds.is_empty(), "no display");
    check("managed displays>=1", ds.iter().any(|d| d.managed), "no managed display");
    let ws = win::list_windows();
    check("windows>0", !ws.is_empty(), "no visible window");
    check("geometry sane", ws.iter().all(|w| w.frame[2] > -10000), "insane rect");
    check("mode valid", ["off", "semi", "auto"].contains(&store::mode().as_str()), "bad mode");
    check("idle readable", win::idle_seconds() >= 0, "GetLastInputInfo failed");
    let (w, h) = win::work_size();
    check("work area", w > 0 && h > 0, "bad work area");
    println!("---\nRESULT: {} passed, {} failed", pass, fail);
    if fail > 0 { 1 } else { 0 }
}

fn usage() {
    println!("ddir {} - Desktop Director (Windows backend)", VERSION);
    println!();
    println!("  ddir mode [off|semi|auto]        show/switch mode");
    println!("  ddir displays                    managed/user displays (json)");
    println!("  ddir list [--text]               windows (filtered to Alt-Tab level)");
    println!("  ddir status                      leases / owned apps / activity (json)");
    println!("  ddir plan [--needs \"a,b\"]        dry-run layout");
    println!("  ddir claim [--needs \"a,b\"] [--force]");
    println!("  ddir move --window 0x.. --rect x,y,w,h [--force]");
    println!("  ddir hide|show --window 0x..");
    println!("  ddir close --window 0x..         WM_CLOSE, owned apps only");
    println!("  ddir own --app <name> | disown --app <name>");
    println!("  ddir release                     restore my leases");
    println!("  ddir board                       human readable overview");
    println!("  ddir selftest                    platform conformance checks");
    println!();
    println!("env: DDIR_HOME (default ~/.ddir), DDIR_AGENT (identity override)");
}

fn main() {
    store::ensure_home();
    let args: Vec<String> = std::env::args().skip(1).collect();
    let cmd = args.first().map(|s| s.to_lowercase()).unwrap_or_else(|| "help".into());
    let rest = &args[1..];
    let code = match cmd.as_str() {
        "mode" => cmd_mode(rest),
        "displays" => cmd_displays(),
        "list" => cmd_list(rest),
        "status" => cmd_status(),
        "plan" => cmd_claim(rest, true),
        "claim" => cmd_claim(rest, false),
        "move" => cmd_move(rest),
        "hide" => cmd_show_hide(rest, true),
        "show" => cmd_show_hide(rest, false),
        "close" => cmd_close(rest),
        "own" => cmd_own(rest, false),
        "disown" => cmd_own(rest, true),
        "release" => cmd_release(),
        "board" => cmd_board(),
        "selftest" => cmd_selftest(),
        "version" | "--version" | "-V" => {
            println!("ddir {} (windows)", VERSION);
            0
        }
        _ => {
            usage();
            0
        }
    };
    exit(code);
}
