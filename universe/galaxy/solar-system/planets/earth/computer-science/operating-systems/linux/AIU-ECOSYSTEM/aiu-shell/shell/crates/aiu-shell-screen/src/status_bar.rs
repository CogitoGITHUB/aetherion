use std::process::{Command, Stdio};
use std::sync::{Mutex, OnceLock};
static SERVER: Mutex<String> = Mutex::new(String::new());
static STARTED: OnceLock<()> = OnceLock::new();
fn home() -> String { std::env::var("HOME").unwrap_or_default() }
fn check_server() -> String {
    let bin = format!("{}/.local/share/aiu-pm/prefix/ecosystem-server/current/bin/ecosystem-server", home());
    if !std::path::Path::new(&bin).exists() { return String::from("not installed"); }
    let ok = Command::new(&bin).arg("ping").stdin(Stdio::null()).stdout(Stdio::null()).stderr(Stdio::null()).status().map(|s| s.success()).unwrap_or(false);
    String::from(if ok { "running" } else { "stopped" })
}
fn start_watcher() {
    STARTED.get_or_init(|| {
        std::thread::spawn(|| loop {
            let state = check_server();
            if let Ok(mut guard) = SERVER.lock() { *guard = state; }
            std::thread::sleep(std::time::Duration::from_secs(2));
        });
    });
}
fn error_count() -> usize {
    std::fs::read_dir(format!("{}/.local/state/aiu-ecosystem/dev-errors", home())).map(|entries| entries.count()).unwrap_or(0)
}
fn box3(text: &str) -> Vec<String> {
    let inner = text.chars().count() + 2;
    vec![format!("╭{}╮", "─".repeat(inner)), format!("│ {} │", text), format!("╰{}╯", "─".repeat(inner))]
}
pub fn status_lines(width: usize, spare: usize) -> Vec<String> {
    if std::env::var_os("AIU_IN_MULTIPLEXER").is_some() || spare < 7 || width < 30 { return Vec::new(); }
    start_watcher();
    let known = SERVER.lock().map(|guard| guard.clone()).unwrap_or_default();
    let server = if known.is_empty() { String::from("checking") } else { known };
    let count = error_count();
    let left = box3(&format!("AIU server: {}", server));
    let right = if crate::command_runner::dev_mode_active() {
        Some(box3(&if count > 0 { format!("DEV MODE ACTIVE  errors {}", count) } else { String::from("DEV MODE ACTIVE") }))
    } else if count > 0 {
        Some(box3(&format!("BUILD ERRORS {}", count)))
    } else {
        None
    };
    (0..3).map(|i| match &right { Some(r) => format!("{}  \u{1}{}", left[i], r[i]), None => left[i].clone() }).collect()
}
