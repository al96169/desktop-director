//! Win32 backend: windows, displays, processes, input, geometry.

use std::ffi::OsString;
use std::os::windows::ffi::OsStringExt;

pub type Hwnd = isize;

#[repr(C)]
#[derive(Clone, Copy, Default)]
pub struct Rect {
    pub left: i32,
    pub top: i32,
    pub right: i32,
    pub bottom: i32,
}

impl Rect {
    pub fn xywh(&self) -> [i32; 4] {
        [self.left, self.top, self.right - self.left, self.bottom - self.top]
    }
}

#[repr(C)]
#[derive(Clone, Copy, Default)]
struct MonitorInfo {
    cb_size: u32,
    rc_monitor: Rect,
    rc_work: Rect,
    flags: u32,
    sz_device: [u16; 32],
}

#[repr(C)]
#[derive(Clone, Copy, Default)]
struct Point {
    x: i32,
    y: i32,
}

#[repr(C)]
#[derive(Clone, Copy, Default)]
struct LastInputInfo {
    cb_size: u32,
    dw_time: u32,
}

#[repr(C)]
struct ProcessEntry32W {
    dw_size: u32,
    cnt_usage: u32,
    th32_process_id: u32,
    th32_default_heap_id: usize,
    th32_module_id: u32,
    cnt_threads: u32,
    th32_parent_process_id: u32,
    pc_pri_class_base: i32,
    dw_flags: u32,
    sz_exe_file: [u16; 260],
}

impl Default for ProcessEntry32W {
    fn default() -> Self {
        Self {
            dw_size: 0,
            cnt_usage: 0,
            th32_process_id: 0,
            th32_default_heap_id: 0,
            th32_module_id: 0,
            cnt_threads: 0,
            th32_parent_process_id: 0,
            pc_pri_class_base: 0,
            dw_flags: 0,
            sz_exe_file: [0u16; 260],
        }
    }
}

#[link(name = "user32")]
extern "system" {
    fn EnumWindows(cb: extern "system" fn(Hwnd, isize) -> i32, lparam: isize) -> i32;
    fn IsWindowVisible(hwnd: Hwnd) -> i32;
    fn IsWindow(hwnd: Hwnd) -> i32;
    fn IsIconic(hwnd: Hwnd) -> i32;
    fn IsZoomed(hwnd: Hwnd) -> i32;
    fn GetWindowTextW(hwnd: Hwnd, buf: *mut u16, max: i32) -> i32;
    fn GetClassNameW(hwnd: Hwnd, buf: *mut u16, max: i32) -> i32;
    fn GetWindowThreadProcessId(hwnd: Hwnd, pid: *mut u32) -> u32;
    fn GetWindowRect(hwnd: Hwnd, rect: *mut Rect) -> i32;
    fn GetWindowLongPtrW(hwnd: Hwnd, index: i32) -> isize;
    fn GetAncestor(hwnd: Hwnd, flags: u32) -> Hwnd;
    fn GetDpiForWindow(hwnd: Hwnd) -> u32;
    fn SetWindowPos(hwnd: Hwnd, after: Hwnd, x: i32, y: i32, cx: i32, cy: i32, flags: u32) -> i32;
    fn ShowWindow(hwnd: Hwnd, cmd: i32) -> i32;
    fn GetForegroundWindow() -> Hwnd;
    fn GetLastInputInfo(li: *mut LastInputInfo) -> i32;
    fn GetCursorPos(p: *mut Point) -> i32;
    fn PostMessageW(hwnd: Hwnd, msg: u32, w: usize, l: isize) -> i32;
    fn EnumDisplayMonitors(hdc: isize, clip: *const Rect, cb: extern "system" fn(isize, isize, *mut Rect, isize) -> i32, data: isize) -> i32;
    fn GetMonitorInfoW(mon: isize, mi: *mut MonitorInfo) -> i32;
}

#[link(name = "dwmapi")]
extern "system" {
    fn DwmGetWindowAttribute(hwnd: Hwnd, attr: u32, pv: *mut std::ffi::c_void, size: u32) -> i32;
}

#[link(name = "kernel32")]
extern "system" {
    fn GetTickCount() -> u32;
    fn OpenProcess(access: u32, inherit: i32, pid: u32) -> isize;
    fn CloseHandle(h: isize) -> i32;
    fn QueryFullProcessImageNameW(h: isize, flags: u32, buf: *mut u16, size: *mut u32) -> i32;
    fn CreateToolhelp32Snapshot(flags: u32, pid: u32) -> isize;
    fn Process32FirstW(snap: isize, entry: *mut ProcessEntry32W) -> i32;
    fn Process32NextW(snap: isize, entry: *mut ProcessEntry32W) -> i32;
    fn GetCurrentProcessId() -> u32;
}

const GWL_EXSTYLE: i32 = -20;
const WS_EX_TOOLWINDOW: isize = 0x0000_0080;
const GA_ROOTOWNER: u32 = 3;
const DWMWA_CLOAKED: u32 = 14;
const DWMWA_EXTENDED_FRAME_BOUNDS: u32 = 9;
const SWP_NOMOVE: u32 = 0x0002;
const SWP_NOSIZE: u32 = 0x0001;
const SWP_NOZORDER: u32 = 0x0004;
const SWP_NOACTIVATE: u32 = 0x0010;
const SWP_SHOWWINDOW: u32 = 0x0040;
const SW_SHOWNOACTIVATE: i32 = 4;
const SW_HIDE: i32 = 0;
const SW_RESTORE: i32 = 9;
const WM_CLOSE: u32 = 0x0010;
const TH32CS_SNAPPROCESS: u32 = 0x0000_0002;
const PROCESS_QUERY_LIMITED_INFORMATION: u32 = 0x1000;

const EXCLUDE_CLASSES: &[&str] = &[
    "Progman",
    "Shell_TrayWnd",
    "Shell_SecondaryTrayWnd",
    "Windows.UI.Core.CoreWindow",
    "ApplicationFrameInputSinkWindow",
    "MSCTFIME UI",
    "IME",
    "SoPY_Hint",
    "Sogou_TSF_UI",
    "Default IME",
    "NVIDIA GeForce Overlay DT",
    "CEF-OSC-WIDGET",
    "ForegroundStaging",
    "MultitaskingViewFrame",
];

#[derive(Clone)]
pub struct WinInfo {
    pub hwnd: Hwnd,
    pub hex: String,
    pub title: String,
    pub class: String,
    pub app: String,
    pub pid: u32,
    pub frame: [i32; 4],
    pub win: [i32; 4],
    pub dpi: u32,
    pub maximized: bool,
    pub minimized: bool,
    pub display: String,
    pub foreground: bool,
}

#[derive(Clone)]
pub struct Display {
    pub uid: String,
    pub gdi: String,
    pub label: String,
    pub primary: bool,
    pub monitor: [i32; 4],
    pub work: [i32; 4],
    pub managed: bool,
}

fn wide_to_string(buf: &[u16]) -> String {
    let end = buf.iter().position(|&c| c == 0).unwrap_or(buf.len());
    OsString::from_wide(&buf[..end]).to_string_lossy().to_string()
}

pub fn exe_name(pid: u32) -> String {
    unsafe {
        let h = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, 0, pid);
        if h == 0 {
            return "?".into();
        }
        let mut buf = [0u16; 1024];
        let mut size = buf.len() as u32;
        let ok = QueryFullProcessImageNameW(h, 0, buf.as_mut_ptr(), &mut size);
        CloseHandle(h);
        if ok == 0 {
            return "?".into();
        }
        let path = wide_to_string(&buf[..size as usize]);
        path.rsplit('\\').next().unwrap_or(&path).trim_end_matches(".exe").to_string()
    }
}

fn parent_pid(pid: u32) -> Option<(u32, String)> {
    unsafe {
        let snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
        if snap == -1 {
            return None;
        }
        let mut e = ProcessEntry32W {
            dw_size: std::mem::size_of::<ProcessEntry32W>() as u32,
            ..Default::default()
        };
        let mut found: Option<(u32, String)> = None;
        if Process32FirstW(snap, &mut e) != 0 {
            loop {
                if e.th32_process_id == pid {
                    found = Some((e.th32_parent_process_id, wide_to_string(&e.sz_exe_file)));
                    break;
                }
                if Process32NextW(snap, &mut e) == 0 {
                    break;
                }
            }
        }
        CloseHandle(snap);
        found
    }
}

/// Agent identity = the "host" process up the parent chain (Trae/terminal/agent runner),
/// so several CLI invocations from the same agent share ownership.
pub fn agent_id() -> String {
    if let Ok(v) = std::env::var("DDIR_AGENT") {
        if !v.is_empty() {
            return v;
        }
    }
    let mut cur = unsafe { GetCurrentProcessId() };
    let mut name = "ddir".to_string();
    for _ in 0..10 {
        match parent_pid(cur) {
            Some((ppid, pname)) => {
                let lower = pname.to_lowercase();
                if lower == "explorer.exe" || lower == "services.exe" || lower == "wininit.exe" || ppid == 0 {
                    break;
                }
                cur = ppid;
                name = pname.trim_end_matches(".exe").to_string();
            }
            None => break,
        }
    }
    format!("{}-{}", name, cur)
}

pub fn exe_path(pid: u32) -> String {
    unsafe {
        let h = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, 0, pid);
        if h == 0 { return String::new(); }
        let mut buf = [0u16; 1024];
        let mut size = buf.len() as u32;
        let ok = QueryFullProcessImageNameW(h, 0, buf.as_mut_ptr(), &mut size);
        CloseHandle(h);
        if ok == 0 { return String::new(); }
        wide_to_string(&buf[..size as usize])
    }
}

pub fn displays() -> Vec<Display> {
    extern "system" fn cb(mon: isize, _hdc: isize, _clip: *mut Rect, data: isize) -> i32 {
        unsafe {
            let out = &mut *(data as *mut Vec<isize>);
            out.push(mon);
        }
        1
    }
    let mut mons: Vec<isize> = Vec::new();
    unsafe {
        EnumDisplayMonitors(0, std::ptr::null(), cb, &mut mons as *mut _ as isize);
    }
    let mut result = Vec::new();
    for (i, m) in mons.iter().enumerate() {
        let mut mi = MonitorInfo {
            cb_size: std::mem::size_of::<MonitorInfo>() as u32,
            ..Default::default()
        };
        let ok = unsafe { GetMonitorInfoW(*m, &mut mi) };
        if ok == 0 {
            continue;
        }
        let primary = (mi.flags & 1) != 0;
        let mon = mi.rc_monitor.xywh();
        let work = mi.rc_work.xywh();
        let dev = wide_to_string(&mi.sz_device);
        let uid = if dev.is_empty() { format!("mon{}", i) } else { dev.clone() };
        result.push(Display {
            uid,
            gdi: format!("DISPLAY{}", i + 1),
            label: format!("{}x{} @ {},{}", mon[2], mon[3], mon[0], mon[1]),
            primary,
            monitor: mon,
            work,
            managed: false,
        });
    }
    // managed set comes from config: "all" | "all_except_primary" | comma separated uids
    let cfg = crate::store::config_get("managed_displays").unwrap_or_else(|| "all_except_primary".into());
    let single = result.len() <= 1;
    let list: Vec<String> = cfg.split(',').map(|s| s.trim().to_string()).filter(|s| !s.is_empty()).collect();
    for d in result.iter_mut() {
        d.managed = if cfg == "all" {
            true
        } else if cfg == "all_except_primary" {
            single || !d.primary
        } else {
            list.iter().any(|u| u == &d.uid || u == &d.gdi)
        };
    }
    // explicit "none" means the user turned everything off; otherwise fall back so semi stays usable
    if cfg == "none" {
        for d in result.iter_mut() {
            d.managed = false;
        }
        return result;
    }
    if !result.iter().any(|d| d.managed) {
        for d in result.iter_mut() {
            d.managed = single || !d.primary;
        }
    }
    result
}

pub fn managed_displays() -> Vec<Display> {
    displays().into_iter().filter(|d| d.managed).collect()
}

pub fn list_windows() -> Vec<WinInfo> {
    extern "system" fn cb(hwnd: Hwnd, lparam: isize) -> i32 {
        unsafe {
            let out = &mut *(lparam as *mut Vec<Hwnd>);
            out.push(hwnd);
        }
        1
    }
    let mut hwnds: Vec<Hwnd> = Vec::new();
    unsafe {
        EnumWindows(cb, &mut hwnds as *mut _ as isize);
    }
    let fg = unsafe { GetForegroundWindow() };
    let ds = displays();
    let mut out = Vec::new();
    for hwnd in hwnds {
        unsafe {
            if IsWindowVisible(hwnd) == 0 {
                continue;
            }
            let ex = GetWindowLongPtrW(hwnd, GWL_EXSTYLE);
            if ex & WS_EX_TOOLWINDOW != 0 {
                continue;
            }
            if GetAncestor(hwnd, GA_ROOTOWNER) != hwnd {
                continue;
            }
            let mut cloaked: u32 = 0;
            if DwmGetWindowAttribute(
                hwnd,
                DWMWA_CLOAKED,
                &mut cloaked as *mut u32 as *mut std::ffi::c_void,
                std::mem::size_of::<u32>() as u32,
            ) == 0
                && cloaked != 0
            {
                continue;
            }
            let mut tbuf = [0u16; 512];
            GetWindowTextW(hwnd, tbuf.as_mut_ptr(), 512);
            let title = wide_to_string(&tbuf);
            if title.trim().is_empty() {
                continue;
            }
            let mut cbuf = [0u16; 256];
            GetClassNameW(hwnd, cbuf.as_mut_ptr(), 256);
            let class = wide_to_string(&cbuf);
            if EXCLUDE_CLASSES.contains(&class.as_str()) {
                continue;
            }
            let mut pid: u32 = 0;
            GetWindowThreadProcessId(hwnd, &mut pid);
            let app = exe_name(pid);
            let mut wr = Rect::default();
            GetWindowRect(hwnd, &mut wr);
            let mut fr = Rect::default();
            if DwmGetWindowAttribute(
                hwnd,
                DWMWA_EXTENDED_FRAME_BOUNDS,
                &mut fr as *mut Rect as *mut std::ffi::c_void,
                std::mem::size_of::<Rect>() as u32,
            ) != 0
            {
                fr = wr;
            }
            let fid = fr.xywh();
            let wid = wr.xywh();
            let cx = fid[0] + fid[2] / 2;
            let cy = fid[1] + fid[3] / 2;
            let mut disp = ds.first().map(|d| d.uid.clone()).unwrap_or_default();
            for d in &ds {
                if cx >= d.monitor[0] && cx < d.monitor[0] + d.monitor[2] && cy >= d.monitor[1] && cy < d.monitor[1] + d.monitor[3] {
                    disp = d.uid.clone();
                    break;
                }
            }
            out.push(WinInfo {
                hwnd,
                hex: format!("0x{:08X}", hwnd as u64),
                title,
                class,
                app,
                pid,
                frame: fid,
                win: wid,
                dpi: GetDpiForWindow(hwnd),
                maximized: IsZoomed(hwnd) != 0,
                minimized: IsIconic(hwnd) != 0,
                display: disp,
                foreground: hwnd == fg,
            });
        }
    }
    out
}

pub fn set_rect(hwnd: Hwnd, xywh: [i32; 4]) -> bool {
    unsafe {
        if IsZoomed(hwnd) != 0 {
            ShowWindow(hwnd, SW_RESTORE);
            std::thread::sleep(std::time::Duration::from_millis(60));
        }
        SetWindowPos(
            hwnd,
            0,
            xywh[0],
            xywh[1],
            xywh[2],
            xywh[3],
            SWP_NOZORDER | SWP_NOACTIVATE | SWP_SHOWWINDOW,
        ) != 0
    }
}

/// Bring the window to the top of the normal z-order without stealing focus.
pub fn raise_noactivate(hwnd: Hwnd) {
    unsafe {
        SetWindowPos(hwnd, 0, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
    }
}

pub fn hide(hwnd: Hwnd) {
    unsafe {
        ShowWindow(hwnd, SW_HIDE);
    }
}

pub fn show(hwnd: Hwnd) {
    unsafe {
        ShowWindow(hwnd, SW_SHOWNOACTIVATE);
    }
}

pub unsafe fn show_raw(hwnd: Hwnd) {
    let _ = ShowWindow(hwnd, 9); // SW_RESTORE
}

pub unsafe fn minimize(hwnd: Hwnd) {
    let _ = ShowWindow(hwnd, 6); // SW_MINIMIZE
}

pub fn close_graceful(hwnd: Hwnd) -> bool {
    unsafe { PostMessageW(hwnd, WM_CLOSE, 0, 0) != 0 }
}

pub fn is_window(hwnd: Hwnd) -> bool {
    unsafe { IsWindow(hwnd) != 0 }
}

pub fn idle_seconds() -> i64 {
    unsafe {
        let mut li = LastInputInfo::default();
        li.cb_size = std::mem::size_of::<LastInputInfo>() as u32;
        if GetLastInputInfo(&mut li) == 0 {
            return -1;
        }
        let now = GetTickCount();
        ((now.wrapping_sub(li.dw_time)) / 1000) as i64
    }
}

pub fn cursor() -> (i32, i32) {
    unsafe {
        let mut p = Point::default();
        if GetCursorPos(&mut p) == 0 {
            return (-1, -1);
        }
        (p.x, p.y)
    }
}

pub fn foreground_hex() -> String {
    unsafe { format!("0x{:08X}", GetForegroundWindow() as u64) }
}

#[repr(C)]
#[derive(Clone, Copy, Default)]
struct SystemTimeW {
    year: u16,
    month: u16,
    day_of_week: u16,
    day: u16,
    hour: u16,
    minute: u16,
    second: u16,
    milliseconds: u16,
}

#[link(name = "kernel32")]
extern "system" {
    fn GetLocalTime(st: *mut SystemTimeW);
}

pub fn now_string() -> String {
    unsafe {
        let mut st = SystemTimeW::default();
        GetLocalTime(&mut st);
        format!(
            "{:04}-{:02}-{:02} {:02}:{:02}:{:02}",
            st.year, st.month, st.day, st.hour, st.minute, st.second
        )
    }
}

pub fn parse_hwnd(s: &str) -> Option<Hwnd> {
    let t = s.trim();
    if let Some(hex) = t.strip_prefix("0x").or_else(|| t.strip_prefix("0X")) {
        isize::from_str_radix(hex, 16).ok()
    } else {
        t.parse::<isize>().ok()
    }
}

pub fn work_size() -> (i32, i32) {
    displays().first().map(|d| (d.work[2], d.work[3])).unwrap_or((1920, 1080))
}
