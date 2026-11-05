//! Native Win32 tray for ddir (no external crates).

use crate::{autostart_on, autostart_set, release_all, store, win};
use std::ffi::c_void;

type Hwnd = isize;

const WM_CREATE: u32 = 0x0001;
const WM_DESTROY: u32 = 0x0002;
const WM_CLOSE: u32 = 0x0010;
const WM_COMMAND: u32 = 0x0111;
const WM_TIMER: u32 = 0x0113;
const WM_DISPLAYCHANGE: u32 = 0x007E;
const WM_APP: u32 = 0x8000;
const TRAY_MSG: u32 = WM_APP + 1;
const WM_RBUTTONUP: u32 = 0x0205;
const WM_LBUTTONDBLCLK: u32 = 0x0203;
const WM_CONTEXTMENU: u32 = 0x007B;

const NIM_ADD: u32 = 0;
const NIM_MODIFY: u32 = 1;
const NIM_DELETE: u32 = 2;
const NIF_MESSAGE: u32 = 0x01;
const NIF_ICON: u32 = 0x02;
const IMAGE_ICON: u32 = 1;
const LR_LOADFROMFILE: u32 = 0x0010;
const LR_DEFAULTSIZE: u32 = 0x0040;
const NIF_TIP: u32 = 0x04;
const NIF_INFO: u32 = 0x10;
const NIIF_INFO: u32 = 0x01;

const MF_STRING: u32 = 0x0000;
const MF_GRAYED: u32 = 0x0001;
const MF_CHECKED: u32 = 0x0008;
const MF_POPUP: u32 = 0x0010;
const MF_SEPARATOR: u32 = 0x0800;
const TPM_RETURNCMD: u32 = 0x0100;
const TPM_RIGHTBUTTON: u32 = 0x0002;
const TPM_BOTTOMALIGN: u32 = 0x0020;
const TPM_LEFTALIGN: u32 = 0x0000;

const IDI_APPLICATION: isize = 32512;
const IDC_ARROW: isize = 32512;

const CMD_OFF: usize = 100;
const CMD_SEMI: usize = 101;
const CMD_AUTO: usize = 102;
const CMD_RELEASE: usize = 103;
const CMD_LIST: usize = 104;
const CMD_AUTOSTART: usize = 105;
const CMD_FOLDER: usize = 106;
const CMD_EXIT: usize = 107;
const CMD_LOG: usize = 108;
const CMD_AC_OFF: usize = 109;
const CMD_AC_MIN: usize = 110;
const CMD_AC_CLOSE: usize = 111;
const CMD_DISPLAY_BASE: usize = 200;
static mut DISPLAY_IDS: Vec<String> = Vec::new();

#[repr(C)]
struct WndClassW {
    style: u32,
    lpfn_wnd_proc: isize,
    cb_cls_extra: i32,
    cb_wnd_extra: i32,
    h_instance: isize,
    h_icon: isize,
    h_cursor: isize,
    hbr_background: isize,
    lpsz_menu_name: *const u16,
    lpsz_class_name: *const u16,
}

#[repr(C)]
struct Msg {
    hwnd: isize,
    message: u32,
    w_param: usize,
    l_param: isize,
    time: u32,
    pt: [i32; 2],
}

#[repr(C)]
struct NotifyIconDataW {
    cb_size: u32,
    hwnd: isize,
    uid: u32,
    uflags: u32,
    callback_message: u32,
    hicon: isize,
    sz_tip: [u16; 128],
    dw_state: u32,
    dw_state_mask: u32,
    sz_info: [u16; 256],
    u_version: u32,
    sz_info_title: [u16; 64],
    dw_info_flags: u32,
    guid_item: [u8; 16],
    h_balloon_icon: isize,
}

#[link(name = "user32")]
extern "system" {
    fn RegisterClassW(wc: *const WndClassW) -> u16;
    fn CreateWindowExW(
        ex: u32, class: *const u16, name: *const u16, style: u32,
        x: i32, y: i32, w: i32, h: i32,
        parent: Hwnd, menu: isize, inst: isize, param: *mut c_void,
    ) -> Hwnd;
    fn DefWindowProcW(hwnd: Hwnd, msg: u32, wp: usize, lp: isize) -> isize;
    fn DestroyWindow(hwnd: Hwnd) -> i32;
    fn PostQuitMessage(code: i32);
    fn GetMessageW(msg: *mut Msg, hwnd: Hwnd, min: u32, max: u32) -> i32;
    fn TranslateMessage(msg: *const Msg) -> i32;
    fn DispatchMessageW(msg: *const Msg) -> isize;
    fn LoadIconW(inst: isize, name: isize) -> isize;
    fn LoadImageW(inst: isize, name: *const u16, typ: u32, cx: i32, cy: i32, flags: u32) -> isize;
    fn LoadCursorW(inst: isize, name: isize) -> isize;
    fn CreatePopupMenu() -> isize;
    fn DestroyMenu(menu: isize) -> i32;
    fn AppendMenuW(menu: isize, flags: u32, id: usize, item: *const u16) -> i32;
    fn TrackPopupMenu(menu: isize, flags: u32, x: i32, y: i32, reserved: i32, hwnd: Hwnd, rect: *const c_void) -> i32;
    fn SetForegroundWindow(hwnd: Hwnd) -> i32;

    fn SetTimer(hwnd: Hwnd, id: usize, ms: u32, proc: isize) -> usize;

    fn MessageBoxW(hwnd: Hwnd, text: *const u16, caption: *const u16, flags: u32) -> i32;
    fn PostMessageW(hwnd: Hwnd, msg: u32, wp: usize, lp: isize) -> i32;

}

#[link(name = "shell32")]
extern "system" {
    fn Shell_NotifyIconW(msg: u32, data: *const NotifyIconDataW) -> i32;
}

#[link(name = "kernel32")]
extern "system" {
    fn GetModuleHandleW(name: *const u16) -> isize;
    fn CreateMutexW(attr: *const c_void, owner: i32, name: *const u16) -> isize;
    fn GetLastError() -> u32;
}

fn tlog(msg: &str) {
    let p = store::home().join("tray.log");
    let line = format!("{}  {}{}", store::now_unix(), msg, "\n");
    use std::io::Write;
    if let Ok(mut f) = std::fs::OpenOptions::new().create(true).append(true).open(p) {
        let _ = f.write_all(line.as_bytes());
    }
}

fn wide(s: &str) -> Vec<u16> {
    s.encode_utf16().chain(std::iter::once(0)).collect()
}

fn fill_tip(dst: &mut [u16; 128], text: &str) {
    for (i, c) in dst.iter_mut().enumerate() {
        *c = if i < 127 { 0 } else { *c };
    }
    for (i, u) in text.encode_utf16().take(127).enumerate() {
        dst[i] = u;
    }
}

fn leases_count() -> usize {
    let now = store::now_unix();
    store::leases().into_iter().filter(|l| l.expires > now).count()
}

fn tip_text() -> String {
    format!("ddir - {} - {} lease(s)", store::mode(), leases_count())
}

fn load_app_icon() -> isize {
    // icon ships next to the exe (or in %LOCALAPPDATA%\ddir\bin); fall back to the system icon
    let mut candidates: Vec<std::path::PathBuf> = Vec::new();
    if let Ok(exe) = std::env::current_exe() {
        if let Some(dir) = exe.parent() {
            candidates.push(dir.join("ddir.ico"));
        }
    }
    if let Ok(local) = std::env::var("LOCALAPPDATA") {
        candidates.push(std::path::Path::new(&local).join("ddir").join("bin").join("ddir.ico"));
    }
    for path in candidates {
        if !path.exists() { tlog(&format!("icon: {} not found", path.display())); continue; }
        let w = wide(&path.to_string_lossy());
        unsafe {
            let h = LoadImageW(0, w.as_ptr(), IMAGE_ICON, 32, 32, LR_LOADFROMFILE | LR_DEFAULTSIZE);
            if h != 0 { tlog(&format!("icon: loaded 32px from {}", path.display())); return h; }
            let h16 = LoadImageW(0, w.as_ptr(), IMAGE_ICON, 16, 16, LR_LOADFROMFILE);
            if h16 != 0 { tlog(&format!("icon: loaded 16px from {}", path.display())); return h16; }
        }
    }
    tlog("icon: falling back to the system application icon");
    unsafe { LoadIconW(0, IDI_APPLICATION) }
}
unsafe fn add_icon(hwnd: Hwnd) -> NotifyIconDataW {
    let mut nid: NotifyIconDataW = std::mem::zeroed();
    nid.cb_size = std::mem::size_of::<NotifyIconDataW>() as u32;
    nid.hwnd = hwnd;
    nid.uid = 1;
    nid.uflags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
    nid.callback_message = TRAY_MSG;
    nid.hicon = load_app_icon();
    fill_tip(&mut nid.sz_tip, &tip_text());
    let r = Shell_NotifyIconW(NIM_ADD, &nid);
    tlog(&format!("NIM_ADD ret={} size={} tip={}", r, nid.cb_size, tip_text()));
    nid
}

unsafe fn refresh_icon(nid: &mut NotifyIconDataW) {
    fill_tip(&mut nid.sz_tip, &tip_text());
    nid.uflags = NIF_TIP;
    nid.u_version = 0;
    Shell_NotifyIconW(NIM_MODIFY, nid);
}

unsafe fn balloon(nid: &mut NotifyIconDataW, title: &str, body: &str) {
    nid.uflags = NIF_INFO;
    nid.dw_info_flags = NIIF_INFO;
    let t = wide(title);
    let b = wide(body);
    for i in 0..64 { nid.sz_info_title[i] = *t.get(i).unwrap_or(&0); }
    for i in 0..256 { nid.sz_info[i] = *b.get(i).unwrap_or(&0); }
    let r = Shell_NotifyIconW(NIM_MODIFY, nid);
    tlog(&format!("balloon ret={} title={}", r, title));
    nid.uflags = NIF_TIP;
}

unsafe fn menu_item_str(menu: isize, flags: u32, id: usize, text: &str) {
    let w = wide(text);
    AppendMenuW(menu, flags, id, w.as_ptr());
}

unsafe fn build_menu() -> isize {
    let menu = CreatePopupMenu();
    let mode = store::mode();
    let n = leases_count();
    let status = format!("状态：{}   leases={}", mode, n);
    menu_item_str(menu, MF_STRING | MF_GRAYED, 0, &status);
    AppendMenuW(menu, MF_SEPARATOR, 0, std::ptr::null());

    let sub = CreatePopupMenu();
    menu_item_str(sub, MF_STRING | if mode == "off" { MF_CHECKED } else { 0 }, CMD_OFF, "off（不碰窗口）");
    menu_item_str(sub, MF_STRING | if mode == "semi" { MF_CHECKED } else { 0 }, CMD_SEMI, "semi（半自动）");
    menu_item_str(sub, MF_STRING | if mode == "auto" { MF_CHECKED } else { 0 }, CMD_AUTO, "auto（全自动）");
    let sub_w = wide("模式");
    AppendMenuW(menu, MF_POPUP, sub as usize, sub_w.as_ptr());

    menu_item_str(menu, MF_STRING, CMD_RELEASE, "全部还原");
    let ac = store::config_get("auto_close").unwrap_or_else(|| "off".into());
    let acmenu = CreatePopupMenu();
    menu_item_str(acmenu, MF_STRING | if ac == "off" { MF_CHECKED } else { 0 }, CMD_AC_OFF, "off（永不自动关窗口）");
    menu_item_str(acmenu, MF_STRING | if ac == "minimize" { MF_CHECKED } else { 0 }, CMD_AC_MIN, "minimize（最小化代替关闭）");
    menu_item_str(acmenu, MF_STRING | if ac == "close" { MF_CHECKED } else { 0 }, CMD_AC_CLOSE, "close（允许关闭，需先武装）");
    let acw = wide("自动关闭");
    AppendMenuW(menu, MF_POPUP, acmenu as usize, acw.as_ptr());
    menu_item_str(menu, MF_STRING, CMD_LOG, "查看日志");
    let dmenu = CreatePopupMenu();
    let mut dmap: Vec<String> = Vec::new();
    for (i, d) in win::displays().iter().enumerate() {
        menu_item_str(dmenu, MF_STRING | if d.managed { MF_CHECKED } else { 0 }, CMD_DISPLAY_BASE + i, &format!("{} ({})", d.gdi, d.label));
        dmap.push(d.uid.clone());
    }
    unsafe { DISPLAY_IDS = dmap; }
    let dw = wide("屏幕");
    AppendMenuW(menu, MF_POPUP, dmenu as usize, dw.as_ptr());
    menu_item_str(menu, MF_STRING, CMD_LIST, "窗口列表（前 8 个）");
    let auto_flag = if autostart_on() { MF_CHECKED } else { 0 };
    menu_item_str(menu, MF_STRING | auto_flag, CMD_AUTOSTART, "开机自启");
    menu_item_str(menu, MF_STRING, CMD_FOLDER, "打开项目目录");
    AppendMenuW(menu, MF_SEPARATOR, 0, std::ptr::null());
    menu_item_str(menu, MF_STRING, CMD_EXIT, "退出");
    menu
}

unsafe fn show_menu(hwnd: Hwnd, nid: &mut NotifyIconDataW) {
    let menu = build_menu();
    let (px, py) = win::cursor();
    SetForegroundWindow(hwnd);
    let cmd = TrackPopupMenu(
        menu,
        TPM_RETURNCMD | TPM_RIGHTBUTTON | TPM_BOTTOMALIGN | TPM_LEFTALIGN,
        px, py, 0, hwnd, std::ptr::null(),
    ) as usize;
    DestroyMenu(menu);
    PostMessageW(hwnd, 0, 0, 0);
    if cmd == 0 { return; }
    match cmd {
        CMD_OFF | CMD_SEMI | CMD_AUTO => {
            let m = match cmd { CMD_OFF => "off", CMD_SEMI => "semi", _ => "auto" };
            let _ = store::set_mode(m);
            store::audit("mode", m);
            refresh_icon(nid);
            balloon(nid, "ddir", &format!("模式已切换：{}", m));
        }
        CMD_RELEASE => {
            let (n, kept) = release_all();
            refresh_icon(nid);
            balloon(nid, "ddir", &format!("已还原 {} 个窗口（保留他人租约 {}）", n, kept));
        }
        CMD_LIST => {
            let ws = win::list_windows();
            let mut txt = String::new();
            for w in ws.iter().take(8) {
                txt.push_str(&format!("{}  {:<24} {},{},{},{}\n", w.hex, w.app, w.frame[0], w.frame[1], w.frame[2], w.frame[3]));
            }
            let t = wide(&txt);
            let c = wide("ddir - 窗口（前 8 个）");
            MessageBoxW(hwnd, t.as_ptr(), c.as_ptr(), 0x40);
        }
        CMD_AUTOSTART => {
            let now = autostart_on();
            let enabled = autostart_set(!now);
            refresh_icon(nid);
            balloon(nid, "ddir", if enabled { "已设置开机自启" } else { "已取消开机自启" });
        }
        c if c >= CMD_DISPLAY_BASE => {
            let idx = c - CMD_DISPLAY_BASE;
            let ids = unsafe { DISPLAY_IDS.clone() };
            if let Some(uid) = ids.get(idx) {
                let ds = win::displays();
                let mut list: Vec<String> = store::config_get("managed_displays")
                    .unwrap_or_else(|| "all_except_primary".into())
                    .split(',')
                    .map(|s| s.trim().to_string())
                    .filter(|s| !s.is_empty() && s != "none")
                    .collect();
                if list.len() == 1 && (list[0] == "all" || list[0] == "all_except_primary") {
                    list = ds.iter().filter(|d| d.managed).map(|d| d.uid.clone()).collect();
                }
                if list.iter().any(|u| u == uid) {
                    list.retain(|u| u != uid);
                } else {
                    list.push(uid.clone());
                }
                let value = if list.is_empty() { "none".to_string() } else { list.join(",") };
                let _ = store::config_set("managed_displays", &value);
                store::log(&format!("tray: managed_displays -> {}", value));
                refresh_icon(nid);
                balloon(nid, "ddir", &format!("托管屏已更新：{}", value));
            }
        }
        CMD_LOG => {
            let p = store::log_path();
            let _ = std::process::Command::new("notepad.exe").arg(&p).spawn();
            balloon(nid, "ddir", "已打开日志：~/.ddir/ddir.log");
        }
        CMD_AC_OFF | CMD_AC_MIN | CMD_AC_CLOSE => {
            let v = match cmd { CMD_AC_OFF => "off", CMD_AC_MIN => "minimize", _ => "close" };
            let _ = store::config_set("auto_close", v);
            store::log(&format!("tray: auto_close={}", v));
            balloon(nid, "ddir", &format!("自动关闭策略：{}", v));
        }
        CMD_FOLDER => {
            let _ = std::process::Command::new("explorer.exe").arg(project_dir()).spawn();
        }
        CMD_EXIT => {
            Shell_NotifyIconW(NIM_DELETE, nid);
            DestroyWindow(hwnd);
        }
        _ => {}
    }
}

fn project_dir() -> String {
    let exe = std::env::current_exe().unwrap_or_default();
    exe.parent().map(|p| p.display().to_string()).unwrap_or_else(|| ".".into())
}

static mut WATCH: Option<Vec<(isize, String)>> = None;

fn recent_close_audit(app: &str) -> bool {
    // look for a close / auto_close audit line for this app in the last 20 seconds
    let now = store::now_unix();
    let txt = std::fs::read_to_string(store::home().join("audit.tsv")).unwrap_or_default();
    for line in txt.lines().rev().take(200) {
        let f: Vec<&str> = line.split('\t').collect();
        if f.len() < 3 { continue; }
        let ts: u64 = f[0].parse().unwrap_or(0);
        if now.saturating_sub(ts) > 20 { break; }
        if (f[1] == "close" || f[1] == "auto_close" || f[1] == "auto_minimize") && f[2].contains(app) {
            return true;
        }
    }
    false
}

fn watch_unmanaged_kills() {
    let cur: Vec<(isize, String)> = win::list_windows().into_iter().map(|w| (w.hwnd, w.app)).collect();
    unsafe {
        if let Some(prev) = WATCH.as_ref() {
            for (hwnd, app) in prev.iter() {
                if cur.iter().any(|(h, _)| h == hwnd) { continue; }
                // window vanished: was it a window of an app that is now gone entirely?
                let still_has = cur.iter().any(|(_, a)| a == app);
                if still_has { continue; }
                if app.eq_ignore_ascii_case("ddir") || app.eq_ignore_ascii_case("explorer") { continue; }
                if recent_close_audit(app) { continue; }
                store::log(&format!("unmanaged_kill: {} (window {} disappeared without ddir close)", app, hwnd));
                store::audit("unmanaged_kill", app);
                if store::config_get("downgrade_on_unmanaged_kill").as_deref() == Some("true") {
                    let _ = store::set_mode("semi");
                    store::log("unmanaged_kill: downgraded to semi");
                }
            }
        }
        WATCH = Some(cur);
    }
}
extern "system" fn wnd_proc(hwnd: Hwnd, msg: u32, wp: usize, lp: isize) -> isize {
    unsafe {
        match msg {
            WM_CREATE => {
                let mut nid = add_icon(hwnd);
                SetTimer(hwnd, 1, 3000, 0);
                refresh_icon(&mut nid);
                0
            }
            WM_DISPLAYCHANGE => {
                store::log("display configuration changed");
                0
            }
            WM_TIMER => {
                crate::present::tick();
                watch_unmanaged_kills();
                let mut probe: NotifyIconDataW = std::mem::zeroed();
                probe.cb_size = std::mem::size_of::<NotifyIconDataW>() as u32;
                probe.hwnd = hwnd;
                probe.uid = 1;
                probe.hicon = LoadIconW(0, IDI_APPLICATION);
                refresh_icon(&mut probe);
                0
            }
            TRAY_MSG => {
                let wm = lp as u32 & 0xFFFF;
                if wm == WM_RBUTTONUP || wm == WM_CONTEXTMENU || wm == WM_LBUTTONDBLCLK {
                    let mut nid: NotifyIconDataW = std::mem::zeroed();
                    nid.cb_size = std::mem::size_of::<NotifyIconDataW>() as u32;
                    nid.hwnd = hwnd;
                    nid.uid = 1;
                    nid.hicon = load_app_icon();
                    if wm == WM_LBUTTONDBLCLK {
                        balloon(&mut nid, "ddir", &format!("{} · 双击已刷新", tip_text()));
                    } else {
                        show_menu(hwnd, &mut nid);
                    }
                }
                0
            }
            WM_COMMAND => {
                DefWindowProcW(hwnd, msg, wp, lp)
            }
            WM_CLOSE | WM_DESTROY => {
                PostQuitMessage(0);
                0
            }
            _ => DefWindowProcW(hwnd, msg, wp, lp),
        }
    }
}

pub fn run() -> i32 {
    unsafe {
        let name = wide("Global\\ddir_tray_mutex");
        let _mutex = CreateMutexW(std::ptr::null(), 0, name.as_ptr());
        if GetLastError() == 183 {
            let t = wide("ddir 托盘已经在运行了。");
            let c = wide("ddir");
            MessageBoxW(0, t.as_ptr(), c.as_ptr(), 0x40);
            return 0;
        }
        let hinst = GetModuleHandleW(std::ptr::null());
        let class_name = wide("ddir_tray_wnd");
        let wc = WndClassW {
            style: 0,
            lpfn_wnd_proc: wnd_proc as *const () as usize as isize,
            cb_cls_extra: 0,
            cb_wnd_extra: 0,
            h_instance: hinst,
            h_icon: LoadIconW(0, IDI_APPLICATION),
            h_cursor: LoadCursorW(0, IDC_ARROW),
            hbr_background: 0,
            lpsz_menu_name: std::ptr::null(),
            lpsz_class_name: class_name.as_ptr(),
        };
        RegisterClassW(&wc);
        let hwnd = CreateWindowExW(
            0, class_name.as_ptr(), class_name.as_ptr(), 0,
            0, 0, 0, 0, 0, 0, hinst, std::ptr::null_mut(),
        );
        if hwnd == 0 {
            return 1;
        }
        let mut msg: Msg = std::mem::zeroed();
        while GetMessageW(&mut msg, 0, 0, 0) > 0 {
            TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }
    }
    0
}
