//! Presentation queue: decouples "operation" (decide geometry) from "presentation" (apply it on screen).
//! instant  -> apply immediately (default, machine speed)
//! paced    -> enqueue ops, apply at step_ms cadence (human can follow)
//! The queue is a directory of tiny op files, so producer (CLI) and consumer (tray / flush / demo)
//! never rewrite a shared file.

use crate::{store, win};
use std::fs;
use std::path::PathBuf;

fn queue_dir() -> PathBuf {
    store::home().join("queue")
}

fn now_ms() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

pub fn step_ms() -> u64 {
    store::config_get("step_ms")
        .and_then(|v| v.parse::<u64>().ok())
        .map(|v| v.clamp(50, 5000))
        .unwrap_or(400)
}

pub fn presentation() -> String {
    store::config_get("presentation").unwrap_or_else(|| "instant".into())
}

/// Enqueue geometry changes; they will be applied at `step_ms` intervals.
pub fn enqueue(ops: &[(isize, [i32; 4])]) -> usize {
    let _ = fs::create_dir_all(queue_dir());
    let base = now_ms();
    let step = step_ms();
    let pid = std::process::id();
    for (i, (hwnd, r)) in ops.iter().enumerate() {
        let due = base + (i as u64 + 1) * step;
        let name = format!("{}-{}-{}.op", due, pid, i);
        let body = format!("{}\t{}\t{}\t{}\t{}\n", hwnd, r[0], r[1], r[2], r[3]);
        let _ = fs::write(queue_dir().join(name), body);
    }
    store::log(&format!("present: queued {} ops (step={}ms)", ops.len(), step));
    ops.len()
}

fn apply_one(path: &PathBuf) -> bool {
    let txt = fs::read_to_string(path).unwrap_or_default();
    let f: Vec<&str> = txt.trim().split('\t').collect();
    if f.len() < 5 {
        let _ = fs::remove_file(path);
        return false;
    }
    let hwnd = f[0].parse::<isize>().unwrap_or(0);
    let r: Vec<i32> = f[1..5].iter().filter_map(|s| s.parse().ok()).collect();
    if hwnd != 0 && r.len() == 4 {
        win::set_rect(hwnd, [r[0], r[1], r[2], r[3]]);
    }
    let _ = fs::remove_file(path);
    true
}

pub fn pending() -> usize {
    fs::read_dir(queue_dir())
        .map(|rd| rd.filter_map(|e| e.ok()).count())
        .unwrap_or(0)
}

/// Apply everything that is due; keep waiting until the queue is empty or the deadline passes.
pub fn drain(max_wait_ms: u64) -> usize {
    let deadline = now_ms() + max_wait_ms;
    let mut applied = 0;
    loop {
        let entries: Vec<(u64, PathBuf)> = fs::read_dir(queue_dir())
            .map(|rd| {
                rd.filter_map(|e| e.ok())
                    .filter_map(|e| {
                        let name = e.file_name().to_string_lossy().to_string();
                        let due = name.split('-').next()?.parse::<u64>().ok()?;
                        Some((due, e.path()))
                    })
                    .collect()
            })
            .unwrap_or_default();
        if entries.is_empty() {
            break;
        }
        let now = now_ms();
        let mut did = false;
        for (due, path) in &entries {
            if *due <= now {
                if apply_one(path) {
                    applied += 1;
                    did = true;
                }
            }
        }
        if now >= deadline {
            break;
        }
        if !did {
            std::thread::sleep(std::time::Duration::from_millis(40));
        }
    }
    if applied > 0 {
        store::log(&format!("present: applied {} ops", applied));
    }
    applied
}

/// Non-blocking tick for the tray: applies whatever is due right now.
pub fn tick() {
    if queue_dir().exists() {
        let _ = drain(0);
    }
}
