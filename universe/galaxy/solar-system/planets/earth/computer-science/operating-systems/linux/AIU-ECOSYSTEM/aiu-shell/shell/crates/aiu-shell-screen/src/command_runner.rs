use std::path::PathBuf;
use std::io::{BufRead, BufReader, Read};
use std::process::{Child, Command, Stdio};
use std::sync::mpsc::{Receiver, Sender, TryRecvError, channel};

const MAX_ROWS: usize = 200;

fn strip_escapes(text: &str) -> String {
    let escape = char::from(27u8);
    let mut out = String::new();
    let mut inside = false;
    for c in text.chars() {
        if c == escape {
            inside = true;
            continue;
        }
        if inside {
            if c.is_ascii_alphabetic() {
                inside = false;
            }
            continue;
        }
        out.push(c);
    }
    out
}

pub fn format_output(stdout: &[u8], stderr: &[u8], code: Option<i32>) -> Vec<String> {
    let mut rows: Vec<String> = Vec::new();
    for bytes in [stdout, stderr] {
        let text = String::from_utf8_lossy(bytes)
            .replace("\t", "    ")
            .replace("\r", "");
        for row in text.lines() {
            rows.push(strip_escapes(row));
        }
    }
    if rows.len() > MAX_ROWS {
        rows.truncate(MAX_ROWS);
        rows.push(String::from("... output cut"));
    }
    match code {
        Some(0) => {}
        Some(number) => rows.push(format!("exit {}", number)),
        None => rows.push(String::from("stopped by signal")),
    }
    if rows.is_empty() {
        rows.push(String::new());
    }
    rows
}

fn sibling_of(path: &std::path::Path) -> Option<PathBuf> {
    let directory = path.parent()?;
    let sibling = directory.join("aiu-shell");
    if sibling.is_file() {
        Some(sibling)
    } else {
        None
    }
}

fn shell_binary() -> PathBuf {
    if let Some(chosen) = std::env::var_os("AIU_SHELL_BINARY") {
        return PathBuf::from(chosen);
    }
    if let Ok(exe) = std::env::current_exe() {
        if let Some(found) = sibling_of(&exe) {
            return found;
        }
    }
    if let Some(first) = std::env::args_os().next() {
        let path = PathBuf::from(first);
        if let Ok(full) = std::fs::canonicalize(&path) {
            if let Some(found) = sibling_of(&full) {
                return found;
            }
        }
        if let Some(found) = sibling_of(&path) {
            return found;
        }
    }
    PathBuf::from("aiu-shell")
}

pub fn run_line(line: &str) -> Vec<String> {
    let binary = shell_binary();
    let mut command = Command::new(&binary);
    command
        .arg("--no-config-file")
        .arg("-c")
        .arg(line)
        .stdin(Stdio::null());
    match command.output() {
        Ok(output) => format_output(&output.stdout, &output.stderr, output.status.code()),
        Err(error) => vec![format!("could not start {}: {}", binary.display(), error)],
    }
}

pub struct RunningJob {
    child: Child,
    receiver: Receiver<String>,
    status: Option<Option<i32>>,
    quiet_polls: usize,
    pub exit: Option<Option<i32>>,
    master: Option<std::fs::File>,
    pub last_space: bool,
    alt: std::sync::Arc<std::sync::atomic::AtomicBool>,
    pending: std::sync::Arc<std::sync::Mutex<Vec<u8>>>,
}

impl RunningJob {
    pub fn poll(&mut self) -> Vec<String> {
        let mut rows = Vec::new();
        let mut disconnected = false;
        loop {
            match self.receiver.try_recv() {
                Ok(row) => rows.push(row),
                Err(TryRecvError::Empty) => break,
                Err(TryRecvError::Disconnected) => {
                    disconnected = true;
                    break;
                }
            }
        }
        if self.status.is_none() {
            if let Ok(Some(status)) = self.child.try_wait() {
                self.status = Some(status.code());
            }
        }
        if let Some(code) = self.status {
            if rows.is_empty() {
                self.quiet_polls += 1;
            } else {
                self.quiet_polls = 0;
            }
            if disconnected || self.quiet_polls >= 2 {
                self.exit = Some(code);
            }
        }
        rows
    }

    pub fn stop(&mut self) {
        let _ = self.child.kill();
    }
}

impl Drop for RunningJob {
    fn drop(&mut self) {
        if self.exit.is_none() {
            let _ = self.child.kill();
        }
        let _ = self.child.wait();
    }
}

fn pump_rows(reader: Box<dyn Read + Send>, sender: Sender<String>) {
    std::thread::spawn(move || {
        for chunk in BufReader::new(reader).split(10u8) {
            let Ok(bytes) = chunk else { break };
            let text = String::from_utf8_lossy(&bytes).replace("\t", "    ").replace("\r", "");
            if sender.send(strip_escapes(&text)).is_err() {
                break;
            }
        }
    });
}

pub fn spawn_job(mut command: Command) -> Result<RunningJob, String> {
    command.stdin(Stdio::null()).stdout(Stdio::piped()).stderr(Stdio::piped());
    let mut child = command.spawn().map_err(|error| error.to_string())?;
    let (sender, receiver) = channel();
    if let Some(stream) = child.stdout.take() {
        pump_rows(Box::new(stream), sender.clone());
    }
    if let Some(stream) = child.stderr.take() {
        pump_rows(Box::new(stream), sender.clone());
    }
    drop(sender);
    Ok(RunningJob { child, receiver, status: None, quiet_polls: 0, exit: None, last_space: false, master: None, alt: Default::default(), pending: Default::default() })
}

pub fn start_line(line: &str) -> Result<RunningJob, String> {
    let binary = shell_binary();
    let mut command = Command::new(&binary);
    command.arg("--no-config-file").arg("-c").arg(line);
    spawn_pty_job(command).map_err(|error| format!("could not start {}: {}", binary.display(), error))
}

#[cfg(test)]
mod tests {
    use super::{RunningJob, format_output, spawn_job};
    use std::process::Command;
    use std::time::Duration;

    fn finish(mut job: RunningJob) -> (Vec<String>, Option<i32>) {
        let mut rows = Vec::new();
        for _ in 0..400 {
            rows.extend(job.poll());
            if let Some(code) = job.exit {
                return (rows, code);
            }
            std::thread::sleep(Duration::from_millis(20));
        }
        panic!("job did not finish");
    }

    #[test]
    fn rows_arrive_and_exit_is_reported() {
        let mut command = Command::new("sh");
        command.arg("-c").arg("echo one; echo two 1>&2; exit 3");
        let (rows, code) = finish(spawn_job(command).unwrap());
        assert!(rows.contains(&String::from("one")));
        assert!(rows.contains(&String::from("two")));
        assert_eq!(code, Some(3));
    }

    #[test]
    fn stop_ends_a_running_job() {
        let mut command = Command::new("sh");
        command.arg("-c").arg("sleep 5");
        let mut job = spawn_job(command).unwrap();
        job.stop();
        let (_, code) = finish(job);
        assert_eq!(code, None);
    }

    #[test]
    fn escape_codes_and_tabs_are_cleaned() {
        let escape = char::from(27u8);
        let colored = format!("{}[31mred{}[0m\tend", escape, escape);
        let rows = format_output(colored.as_bytes(), b"", Some(0));
        assert_eq!(rows, vec![String::from("red    end")]);
    }

    #[test]
    fn nonzero_exit_is_appended_after_stderr() {
        let rows = format_output(b"out\n", b"bad\n", Some(2));
        assert_eq!(rows, vec!["out", "bad", "exit 2"]);
    }

    #[test]
    fn empty_output_gives_one_empty_row() {
        let rows = format_output(b"", b"", Some(0));
        assert_eq!(rows, vec![String::new()]);
    }

    #[test]
    fn long_output_is_cut() {
        let text = "x\n".repeat(300);
        let rows = format_output(text.as_bytes(), b"", Some(0));
        assert_eq!(rows.len(), 201);
        assert_eq!(rows[200], "... output cut");
    }

    #[test]
    fn signal_exit_is_named() {
        let rows = format_output(b"", b"", None);
        assert_eq!(rows, vec!["stopped by signal"]);
    }
}

static FULLSCREEN_LINE: std::sync::Mutex<Option<String>> = std::sync::Mutex::new(None);


pub fn request_fullscreen(line: &str) {
    if let Ok(mut slot) = FULLSCREEN_LINE.lock() {
        *slot = Some(line.to_string());
    }
}

static JUMP_REQUEST: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false); pub fn request_jump() { JUMP_REQUEST.store(true, std::sync::atomic::Ordering::Relaxed); } pub fn take_jump() -> bool { JUMP_REQUEST.swap(false, std::sync::atomic::Ordering::Relaxed) } pub fn pick_directory() -> Option<String> { let out = Command::new("tv").arg("zoxide").stdin(std::process::Stdio::inherit()).stderr(std::process::Stdio::inherit()).stdout(std::process::Stdio::piped()).output().ok()?; let path = String::from_utf8_lossy(&out.stdout).trim().to_string(); if !out.status.success() || path.is_empty() { return None; } std::env::set_current_dir(&path).ok()?; Some(path) } fn jump_bin() -> String { format!("{}/.local/share/aiu-pm/prefix/aiu-jump/current/bin/aiu-shell-jump", std::env::var("HOME").unwrap_or_default()) } pub fn add_current_dir() -> String { let cwd = match std::env::current_dir() { Ok(c) => c, Err(e) => return format!("add failed: {e}") }; match Command::new(jump_bin()).arg("add").arg(&cwd).status() { Ok(s) if s.success() => format!("added {}", cwd.display()), _ => String::from("zoxide add failed") } } pub fn try_cd(line: &str) -> Option<String> { let mut parts = line.split_whitespace(); if parts.next()? != "cd" { return None; } let rest: Vec<&str> = parts.collect(); let target = rest.join(" "); let home = std::env::var("HOME").unwrap_or_default(); let expanded = if target.is_empty() || target == "~" { home.clone() } else if let Some(r) = target.strip_prefix("~/") { format!("{home}/{r}") } else { target.clone() }; if std::path::Path::new(&expanded).is_dir() { return Some(match std::env::set_current_dir(&expanded) { Ok(_) => format!("cd {expanded}"), Err(e) => format!("cd failed: {e}") }); } let out = Command::new(jump_bin()).arg("query").args(&rest).output().ok()?; let path = String::from_utf8_lossy(&out.stdout).trim().to_string(); if out.status.success() && !path.is_empty() && std::env::set_current_dir(&path).is_ok() { Some(format!("z {path}")) } else { Some(format!("cd: no match for {target}")) } } pub fn take_fullscreen() -> Option<String> {
    FULLSCREEN_LINE.lock().ok().and_then(|mut slot| slot.take())
}

pub fn run_fullscreen(line: &str) -> i32 {
    let binary = shell_binary();
    match Command::new(&binary).arg("-c").arg(line).status() {
        Ok(status) => status.code().unwrap_or(-1),
        Err(_) => -1,
    }
}

pub fn enter_multiplexer() -> bool {
    if std::env::var_os("AIU_IN_MULTIPLEXER").is_some() {
        return false;
    }
    let me = match std::env::current_exe() {
        Ok(path) => path,
        Err(_) => return false,
    };
    Command::new("aiutm")
        .env("AIU_IN_MULTIPLEXER", "1")
        .env("AIU_PANE_PROGRAM", &me)
        .status()
        .is_ok()
}
pub fn dev_flag_path() -> String { format!("{}/.local/state/aiu-ecosystem/dev-mode", std::env::var("HOME").unwrap_or_default()) }
pub fn dev_mode_active() -> bool { std::path::Path::new(&dev_flag_path()).exists() }
fn run_detached(args: &str) -> bool {
    let home = std::env::var("HOME").unwrap_or_default();
    let _ = std::fs::create_dir_all(format!("{home}/.local/state/aiu-ecosystem"));
    let line = format!("setsid {home}/.local/share/aiu-pm/prefix/ecosystem/current/bin/ecosystem {args} >> {home}/.local/state/aiu-ecosystem/devmode.log 2>&1 < /dev/null &");
    Command::new("sh").arg("-c").arg(line).status().map(|s| s.success()).unwrap_or(false)
}
pub fn dev_mode_toggle() -> String {
    let was = dev_mode_active();
    if run_detached("devmode toggle") {
        if was { String::from("dev mode off: building everything changed, see devmode.log") } else { String::from("dev mode on") }
    } else { String::from("dev mode: could not start ecosystem") }
}
pub fn dev_build_all() -> String {
    if run_detached("update") { String::from("building everything changed through the pm, see devmode.log") } else { String::from("build: could not start ecosystem") }
}

fn has_alt(bytes: &[u8]) -> bool {
    let marks: [&[u8]; 3] =
        [b"\x1b[?1049h", b"\x1b[?1047h", b"\x1b[?47h"];
    marks.iter().any(|m| bytes.windows(m.len()).any(|w| w == *m))
}

fn set_size(fd: i32, cols: u16, rows: u16) {
    let ws = libc::winsize {
        ws_row: rows,
        ws_col: cols,
        ws_xpixel: 0,
        ws_ypixel: 0,
    };
    unsafe {
        libc::ioctl(fd, libc::TIOCSWINSZ as _, &ws);
    }
}

fn open_pty() -> std::io::Result<(std::fs::File, std::fs::File)> {
    use std::os::fd::FromRawFd;
    unsafe {
        let m = libc::posix_openpt(libc::O_RDWR | libc::O_NOCTTY);
        if m < 0 {
            return Err(std::io::Error::last_os_error());
        }
        let master = std::fs::File::from_raw_fd(m);
        if libc::grantpt(m) != 0 || libc::unlockpt(m) != 0 {
            return Err(std::io::Error::last_os_error());
        }
        let mut name = [0 as libc::c_char; 128];
        if libc::ptsname_r(m, name.as_mut_ptr(), 128) != 0 {
            return Err(std::io::Error::last_os_error());
        }
        let s = libc::open(name.as_ptr(), libc::O_RDWR | libc::O_NOCTTY);
        if s < 0 {
            return Err(std::io::Error::last_os_error());
        }
        Ok((master, std::fs::File::from_raw_fd(s)))
    }
}


fn pump_pty(
    mut reader: std::fs::File,
    sender: Sender<String>,
    alt: std::sync::Arc<std::sync::atomic::AtomicBool>,
    pending: std::sync::Arc<std::sync::Mutex<Vec<u8>>>,
) {
    std::thread::spawn(move || {
        use std::os::fd::AsRawFd;
        let fd = reader.as_raw_fd();
        let mut buf = [0u8; 4096];
        let mut acc: Vec<u8> = Vec::new();
        let mut last = std::time::Instant::now();
        let park = |acc: &Vec<u8>| {
            if let Ok(mut p) = pending.lock() {
                p.extend_from_slice(acc);
            }
            alt.store(true, std::sync::atomic::Ordering::SeqCst);
        };
        let raw_mode = || {
            let mut t: libc::termios = unsafe { std::mem::zeroed() };
            unsafe { libc::tcgetattr(fd, &mut t) == 0 && t.c_lflag & libc::ICANON == 0 }
        };
        loop {
            let mut p = libc::pollfd { fd, events: libc::POLLIN, revents: 0 };
            let ready = unsafe { libc::poll(&mut p, 1, 100) };
            if ready > 0 {
                let n = match reader.read(&mut buf) {
                    Ok(0) | Err(_) => break,
                    Ok(n) => n,
                };
                acc.extend_from_slice(&buf[..n]);
                last = std::time::Instant::now();
                if has_alt(&acc) || raw_mode() {
                    park(&acc);
                    return;
                }
                while let Some(i) = acc.iter().position(|b| *b == 10) {
                    let line: Vec<u8> = acc.drain(..=i).collect();
                    let text = String::from_utf8_lossy(&line)
                        .replace("\t", "    ")
                        .replace("\r", "");
                    let row = strip_escapes(text.trim_end_matches("\n"));
                    if sender.send(row).is_err() {
                        return;
                    }
                }
            } else {
                let stalled = !acc.is_empty()
                    && last.elapsed() > std::time::Duration::from_millis(500);
                if stalled || raw_mode() {
                    park(&acc);
                    return;
                }
            }
        }
        if !acc.is_empty() {
            let text = String::from_utf8_lossy(&acc).replace("\r", "");
            let _ = sender.send(strip_escapes(&text));
        }
    });
}

pub fn spawn_pty_job(mut command: Command) -> Result<RunningJob, String> {
    use std::os::fd::AsRawFd;
    use std::os::unix::process::CommandExt;
    let (master, slave) = open_pty().map_err(|e| e.to_string())?;
    let (c, r) = crossterm::terminal::size().unwrap_or((80, 24));
    set_size(master.as_raw_fd(), c, r);
    let dup = |f: &std::fs::File| f.try_clone().map_err(|e| e.to_string());
    command.stdin(Stdio::from(dup(&slave)?));
    command.stdout(Stdio::from(dup(&slave)?));
    command.stderr(Stdio::from(slave));
    unsafe {
        command.pre_exec(|| {
            libc::setsid();
            libc::ioctl(0, libc::TIOCSCTTY as _, 0);
            Ok(())
        });
    }
    let child = command.spawn().map_err(|e| e.to_string())?;
    drop(command);
    let reader = master.try_clone().map_err(|e| e.to_string())?;
    let (sender, receiver) = channel();
    let alt = std::sync::Arc::new(std::sync::atomic::AtomicBool::new(false));
    let pending = std::sync::Arc::new(std::sync::Mutex::new(Vec::new()));
    pump_pty(reader, sender, alt.clone(), pending.clone());
    Ok(RunningJob {
        child,
        receiver,
        status: None,
        quiet_polls: 0,
        exit: None,
        master: Some(master),
        last_space: false,
        alt,
        pending,
    })
}

impl RunningJob {
    pub fn wants_terminal(&self) -> bool {
        self.alt.load(std::sync::atomic::Ordering::SeqCst)
    }
}

pub fn run_passthrough(job: &mut RunningJob) -> i32 {
    use std::io::Write;
    use std::os::fd::AsRawFd;
    let Some(master) = job.master.as_ref().and_then(|m| m.try_clone().ok())
    else {
        return -1;
    };
    let _ = crossterm::terminal::enable_raw_mode();
    let mut out = std::io::stdout();
    let first = job.pending.lock().map(|p| p.clone()).unwrap_or_default();
    let _ = out.write_all(&first);
    let _ = out.flush();
    let mut size = crossterm::terminal::size().unwrap_or((80, 24));
    set_size(master.as_raw_fd(), size.0, size.1);
    if let Ok(mut reader) = master.try_clone() {
        std::thread::spawn(move || {
            let mut buf = [0u8; 4096];
            let mut out = std::io::stdout();
            while let Ok(n) = reader.read(&mut buf) {
                if n == 0 || out.write_all(&buf[..n]).is_err() {
                    break;
                }
                let _ = out.flush();
            }
        });
    }
    let mut writer = master;
    let code = loop {
        let mut fds = libc::pollfd { fd: 0, events: libc::POLLIN, revents: 0 };
        let ready = unsafe { libc::poll(&mut fds, 1, 40) };
        if ready > 0 && fds.revents & libc::POLLIN != 0 {
            let mut buf = [0u8; 1024];
            let n = unsafe {
                libc::read(0, buf.as_mut_ptr() as *mut libc::c_void, buf.len())
            };
            if n > 0 {
                let _ = writer.write_all(&buf[..n as usize]);
            }
        }
        if let Ok(now) = crossterm::terminal::size() {
            if now != size {
                size = now;
                set_size(writer.as_raw_fd(), now.0, now.1);
            }
        }
        if let Ok(Some(status)) = job.child.try_wait() {
            break status.code().unwrap_or(-1);
        }
    };
    std::thread::sleep(std::time::Duration::from_millis(80));
    let _ = crossterm::terminal::disable_raw_mode();
    job.status = Some(Some(code));
    job.exit = Some(Some(code));
    code
}


impl RunningJob {
    pub fn write_input(&mut self, bytes: &[u8]) {
        use std::io::Write;
        if let Some(master) = self.master.as_mut() {
            let _ = master.write_all(bytes);
        }
    }
}
