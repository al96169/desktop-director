//! Persistent state: mode, leases, app ownership, audit trail.
//! Plain TSV files under ~/.ddir so they are easy to inspect and hand-edit.

use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::PathBuf;

pub fn home() -> PathBuf {
    if let Ok(v) = std::env::var("DDIR_HOME") {
        if !v.is_empty() {
            return PathBuf::from(v);
        }
    }
    let mut p = PathBuf::from(std::env::var("USERPROFILE").unwrap_or_else(|_| ".".into()));
    p.push(".ddir");
    p
}

pub fn atomic_write(path: &std::path::Path, data: &str) -> std::io::Result<()> {
    let tmp = path.with_extension("tmp");
    fs::write(&tmp, data)?;
    fs::rename(&tmp, path)
}

/// Cross-process lock around state mutation: a lock file created with create_new + retry.
pub struct Guard(std::path::PathBuf);
impl Drop for Guard {
    fn drop(&mut self) { let _ = fs::remove_file(&self.0); }
}
pub fn lock() -> Guard {
    ensure_home();
    let p = home().join("state.lock");
    let mut waited = 0u64;
    loop {
        match fs::OpenOptions::new().create_new(true).write(true).open(&p) {
            Ok(_) => return Guard(p),
            Err(_) => {
                std::thread::sleep(std::time::Duration::from_millis(15));
                waited += 15;
                if waited > 3000 {
                    let _ = fs::remove_file(&p); // stale lock from a crashed process
                }
            }
        }
    }
}

pub fn ensure_home() {
    let _ = fs::create_dir_all(home());
}

pub fn mode() -> String {
    let p = home().join("mode.txt");
    match fs::read_to_string(p) {
        Ok(s) => {
            let t = s.trim().to_string();
            if t.is_empty() {
                "off".into()
            } else {
                t
            }
        }
        Err(_) => "off".into(),
    }
}

pub fn set_mode(m: &str) -> Result<(), String> {
    if !["off", "semi", "auto"].contains(&m) {
        return Err("mode must be off|semi|auto".into());
    }
    ensure_home();
    fs::write(home().join("mode.txt"), m).map_err(|e| e.to_string())
}

#[derive(Clone)]
pub struct Lease {
    pub window: String,
    pub agent: String,
    pub action: String,
    pub from: [i32; 4],
    pub to: [i32; 4],
    pub expires: u64,
    pub lease: String,
    pub priority: String,
    pub since: u64,
}

fn leases_path() -> PathBuf {
    home().join("leases.tsv")
}

fn parse_rect(s: &str) -> [i32; 4] {
    let mut r = [0i32; 4];
    for (i, part) in s.split(',').take(4).enumerate() {
        r[i] = part.trim().parse().unwrap_or(0);
    }
    r
}

pub fn leases() -> Vec<Lease> {
    let mut out = Vec::new();
    if let Ok(txt) = fs::read_to_string(leases_path()) {
        for line in txt.lines() {
            let f: Vec<&str> = line.split('\t').collect();
            if f.len() < 8 {
                continue;
            }
            out.push(Lease {
                window: f[0].into(),
                agent: f[1].into(),
                action: f[2].into(),
                from: parse_rect(f[3]),
                to: parse_rect(f[4]),
                expires: f[5].parse().unwrap_or(0),
                lease: f[6].into(),
                priority: f.get(7).map(|s| s.to_string()).unwrap_or_else(|| "normal".into()),
                since: f.get(8).and_then(|s| s.parse().ok()).unwrap_or(0),
            });
        }
    }
    out
}

pub fn save_leases(items: &[Lease]) {
    ensure_home();
    let mut s = String::new();
    for l in items {
        s.push_str(&format!(
            "{}\t{}\t{}\t{},{},{},{}\t{},{},{},{}\t{}\t{}\t{}\t{}\n",
            l.window, l.agent, l.action, l.from[0], l.from[1], l.from[2], l.from[3],
            l.to[0], l.to[1], l.to[2], l.to[3], l.expires, l.lease, l.priority, l.since
        ));
    }
    let _ = atomic_write(&leases_path(), &s);
}

pub fn now_unix() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

#[allow(dead_code)]
pub fn live_leases() -> Vec<Lease> {
    let now = now_unix();
    leases().into_iter().filter(|l| l.expires > now).collect()
}

#[derive(Clone)]
pub struct AppOwner {
    pub app: String,
    pub owner: String,
    pub since: u64,
    pub ttl: u64,
}

fn apps_path() -> PathBuf {
    home().join("apps.tsv")
}

pub fn apps() -> Vec<AppOwner> {
    let mut out = Vec::new();
    if let Ok(txt) = fs::read_to_string(apps_path()) {
        for line in txt.lines() {
            let f: Vec<&str> = line.split('\t').collect();
            if f.len() < 4 {
                continue;
            }
            out.push(AppOwner {
                app: f[0].into(),
                owner: f[1].into(),
                since: f[2].parse().unwrap_or(0),
                ttl: f[3].parse().unwrap_or(1800),
            });
        }
    }
    out
}

pub fn save_apps(v: &[AppOwner]) {
    ensure_home();
    let mut s = String::new();
    for a in v {
        s.push_str(&format!("{}\t{}\t{}\t{}\n", a.app, a.owner, a.since, a.ttl));
    }
    let _ = atomic_write(&apps_path(), &s);
}

pub fn audit(op: &str, detail: &str) {
    ensure_home();
    let line = format!("{}\t{}\t{}\n", now_unix(), op, detail.replace('\t', " ").replace('\n', " "));
    if let Ok(mut f) = OpenOptions::new().create(true).append(true).open(home().join("audit.tsv")) {
        let _ = f.write_all(line.as_bytes());
    }
}
// ---------- config (key=value) ----------

pub fn config_path() -> PathBuf { home().join("config.ini") }

pub fn config_get(key: &str) -> Option<String> {
    let txt = fs::read_to_string(config_path()).ok()?;
    for line in txt.lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') { continue; }
        if let Some((k, v)) = line.split_once('=') {
            if k.trim() == key { return Some(v.trim().to_string()); }
        }
    }
    None
}

pub fn config_all() -> Vec<(String, String)> {
    let mut out = Vec::new();
    if let Ok(txt) = fs::read_to_string(config_path()) {
        for line in txt.lines() {
            let line = line.trim();
            if line.is_empty() || line.starts_with('#') { continue; }
            if let Some((k, v)) = line.split_once('=') {
                out.push((k.trim().to_string(), v.trim().to_string()));
            }
        }
    }
    out
}

pub fn config_set(key: &str, value: &str) -> Result<(), String> {
    match key {
        "auto_close" => {
            if !["off", "minimize", "close"].contains(&value) {
                return Err("auto_close must be off|minimize|close".into());
            }
        }
        "show_policy" => {
            if !["always", "prefer", "auto", "critical"].contains(&value) {
                return Err("show_policy must be always|prefer|auto|critical".into());
            }
        }
        "presentation" => {
            if !["instant", "paced"].contains(&value) {
                return Err("presentation must be instant|paced".into());
            }
        }
        "managed_displays" => { /* any string accepted */ }
        "downgrade_on_unmanaged_kill" => {
            if !["true", "false"].contains(&value) {
                return Err("downgrade_on_unmanaged_kill must be true|false".into());
            }
        }
        "step_ms" => {
            if value.parse::<u64>().map(|n| (50..=5000).contains(&n)).unwrap_or(false) == false {
                return Err("step_ms must be 50..5000".into());
            }
        }
        "countdown_seconds" => {
            if value.parse::<u64>().map(|n| n <= 300).unwrap_or(false) == false {
                return Err("countdown_seconds must be 0..300".into());
            }
        }
        _ => return Err(format!("unknown key: {}", key)),
    }
    let mut map: Vec<(String, String)> = config_all();
    match map.iter_mut().find(|(k, _)| k == key) {
        Some(e) => e.1 = value.to_string(),
        None => map.push((key.to_string(), value.to_string())),
    }
    ensure_home();
    let mut s = String::from("# ddir config (edited by `ddir config`)\n");
    s.push_str("# auto_close: off = 永不自动关窗口 / minimize = 最小化代替关闭 / close = WM_CLOSE\n");
    for (k, v) in map { s.push_str(&format!("{}={}\n", k, v)); }
    atomic_write(&config_path(), &s).map_err(|e| e.to_string())
}

// ---------- user-facing log ----------

pub fn log_path() -> PathBuf { home().join("ddir.log") }

pub fn log(msg: &str) {
    ensure_home();
    let p = log_path();
    if let Ok(md) = fs::metadata(&p) {
        if md.len() > 2 * 1024 * 1024 {
            let _ = fs::rename(&p, home().join("ddir.log.1"));
        }
    }
    let line = format!("{}  {}\n", crate::win::now_string(), msg.replace('\n', " "));
    use std::io::Write;
    if let Ok(mut f) = OpenOptions::new().create(true).append(true).open(&p) {
        let _ = f.write_all(line.as_bytes());
    }
}

pub fn log_tail(n: usize) -> Vec<String> {
    let txt = fs::read_to_string(log_path()).unwrap_or_default();
    let lines: Vec<&str> = txt.lines().collect();
    let start = lines.len().saturating_sub(n);
    lines[start..].iter().map(|s| s.to_string()).collect()
}