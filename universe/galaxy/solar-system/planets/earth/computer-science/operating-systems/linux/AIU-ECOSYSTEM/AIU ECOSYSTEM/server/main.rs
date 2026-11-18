mod ws;
use std::collections::BTreeMap;
use std::env;
use std::fs;
use std::io::{BufRead, BufReader, Write};
use std::net::{TcpListener, TcpStream};
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::PathBuf;
use std::process;
use std::fs::OpenOptions;
use std::process::{Command, Stdio};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

fn socket_path() -> PathBuf {
    match env::var("AIU_SERVER_SOCKET") {
        Ok(p) if !p.is_empty() => PathBuf::from(p),
        _ => {
            let home = env::var("HOME").unwrap_or_else(|_| String::from("."));
            PathBuf::from(home)
                .join(".local")
                .join("state")
                .join("aiu-ecosystem")
                .join("server.sock")
        }
    }
}

fn ask(line: &str) -> Result<String, String> {
    let path = socket_path();
    let mut stream = UnixStream::connect(&path)
        .map_err(|e| format!("no server at {}: {}", path.display(), e))?;
    let _ = stream.set_read_timeout(Some(Duration::from_secs(5)));
    stream.write_all(line.as_bytes()).map_err(|e| e.to_string())?;
    stream.write_all(b"\n").map_err(|e| e.to_string())?;
    let mut answer = String::new();
    BufReader::new(&stream)
        .read_line(&mut answer)
        .map_err(|e| e.to_string())?;
    Ok(answer.trim_end().to_string())
}

fn now_seconds() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

struct DevState {
    running: bool,
    names: String,
    last: String,
}

fn ecosystem_bin() -> PathBuf {
    match env::var("AIU_ECOSYSTEM_BIN") {
        Ok(p) if !p.is_empty() => PathBuf::from(p),
        _ => {
            let data = match env::var("XDG_DATA_HOME") {
                Ok(p) if !p.is_empty() => PathBuf::from(p),
                _ => {
                    let home = env::var("HOME").unwrap_or_else(|_| String::from("."));
                    PathBuf::from(home).join(".local").join("share")
                }
            };
            data.join("aiu-pm").join("prefix").join("ecosystem").join("current").join("bin").join("ecosystem")
        }
    }
}

fn dev_log_path() -> PathBuf {
    match socket_path().parent() {
        Some(p) => p.join("dev.log"),
        None => PathBuf::from("dev.log"),
    }
}

fn start_dev(names: Vec<String>, dev: &Arc<Mutex<DevState>>) -> String {
    let label = if names.is_empty() { String::from("ecosystem") } else { names.join(" ") };
    {
        let mut state = dev.lock().unwrap();
        if state.running {
            return format!("busy {}", state.names);
        }
        state.running = true;
        state.names = label.clone();
    }
    let started_label = label.clone();
    let shared = Arc::clone(dev);
    thread::spawn(move || {
        let mut command = Command::new(ecosystem_bin());
        command.arg("dev-local").args(&names).stdin(Stdio::null());
        match OpenOptions::new().create(true).append(true).open(dev_log_path()) {
            Ok(log) => {
                match log.try_clone() {
                    Ok(second) => {
                        command.stdout(Stdio::from(log)).stderr(Stdio::from(second));
                    }
                    Err(_) => {
                        command.stdout(Stdio::null()).stderr(Stdio::null());
                    }
                }
            }
            Err(_) => {
                command.stdout(Stdio::null()).stderr(Stdio::null());
            }
        }
        let result = match command.status() {
            Ok(status) => format!("rc {} {}", status.code().unwrap_or(-1), label),
            Err(e) => format!("spawn failed {} {}", e, label),
        };
        let mut state = shared.lock().unwrap();
        state.running = false;
        state.last = result;
    });
    format!("started {}", started_label)
}

fn read_db(db: &Arc<Mutex<Option<notation::database_store::Store>>>, f: impl FnOnce(&notation::database_store::Store) -> String) -> String {
    let guard = db.lock().unwrap_or_else(|e| e.into_inner());
    match guard.as_ref() {
        Some(store) => f(store),
        None => String::from("error no index, run load FOLDER first"),
    }
}
static ROOT: Mutex<Option<String>> = Mutex::new(None);
fn state_dir() -> PathBuf {
    let home = env::var("HOME").unwrap_or_else(|_| String::from("."));
    PathBuf::from(home)
        .join(".local")
        .join("state")
        .join("aiu-ecosystem")
}
fn state_text(name: &str) -> Option<String> {
    let t = fs::read_to_string(state_dir().join(name)).ok()?;
    let t = t.trim().to_string();
    if t.is_empty() { None } else { Some(t) }
}
fn website_dir() -> PathBuf {
    if let Ok(p) = env::var("AIU_WEBSITE_DIR") {
        if !p.is_empty() {
            return PathBuf::from(p);
        }
    }
    if let Some(p) = state_text("website-dir") {
        if PathBuf::from(&p).join("index.html").is_file() {
            return PathBuf::from(p);
        }
    }
    if let Some(r) = state_text("root") {
        let d = PathBuf::from(r)
            .join("AIU ECOSYSTEM")
            .join("website");
        if d.join("index.html").is_file() {
            return d;
        }
    }
    PathBuf::from("website")
}
fn git_out(dir: &std::path::Path, args: &[&str]) -> Option<String> {
    let out = Command::new("git").arg("-C").arg(dir).args(args).output().ok()?;
    if !out.status.success() {
        return None;
    }
    Some(String::from_utf8_lossy(&out.stdout).trim().to_string())
}
fn git_report(file: &str) -> String {
    let mut p = PathBuf::from(file);
    if p.is_relative() {
        let root = ROOT.lock().unwrap_or_else(|e| e.into_inner()).clone();
        if let Some(r) = root {
            p = PathBuf::from(r).join(p);
        }
    }
    let dir = if p.is_dir() {
        p.clone()
    } else {
        p.parent().map(|x| x.to_path_buf()).unwrap_or_else(|| PathBuf::from("."))
    };
    let repo = match git_out(&dir, &["rev-parse", "--show-toplevel"]) {
        Some(r) => r,
        None => return format!("error no git repo or git missing for {}", file),
    };
    let yn = |b: bool| if b { "yes" } else { "no" };
    let name = git_out(&dir, &["config", "user.name"]).is_some();
    let email = git_out(&dir, &["config", "user.email"]).is_some();
    let target = p.to_string_lossy().to_string();
    let state = match git_out(&dir, &["status", "--porcelain", "--", target.as_str()]) {
        Some(s) if s.is_empty() => "clean",
        Some(_) => "dirty",
        None => "unknown",
    };
    format!("git {} name {} email {} {}", repo, yn(name), yn(email), state)
}
fn handle(words: &[&str], programs: &mut BTreeMap<String, String>, started: u64, dev: &Arc<Mutex<DevState>>, db: &Arc<Mutex<Option<notation::database_store::Store>>>) -> (String, bool) {
    match words {
        ["ping"] => (String::from("pong"), false),
        ["status"] => (
            format!("up pid {} since {} programs {}", process::id(), started, programs.len()),
            false,
        ),
        ["register", name, mode] => {
            programs.insert(name.to_string(), mode.to_string());
            (String::from("ok"), false)
        }
        ["unregister", name] => {
            programs.remove(*name);
            (String::from("ok"), false)
        }
        ["list"] => {
            let rows: Vec<String> = programs.iter().map(|(k, v)| format!("{} {}", k, v)).collect();
            (format!("programs {}", rows.join(";")), false)
        }
        ["dev", names @ ..] => (start_dev(names.iter().map(|n| n.to_string()).collect(), dev), false),
        ["dev-status"] => {
            let state = dev.lock().unwrap();
            let mode = if state.running { "running" } else { "idle" };
            (format!("dev {} {} last {}", mode, state.names, state.last), false)
        }
        ["links", rest @ ..] if !rest.is_empty() => {
            let file = rest.join(" ");
            (read_db(db, |s| {
                let rows: Vec<String> = s.of_kind("link").iter()
                    .filter(|r| r.source == file)
                    .map(|r| format!("{} {} {} {}", r.field("name").unwrap_or(""), r.field("target").unwrap_or(""), r.field("relation").unwrap_or(""), r.field("mode").unwrap_or("")))
                    .collect();
                format!("links {} {}", rows.len(), rows.join(";"))
            }), false)
        }
        ["backlinks", rest @ ..] if !rest.is_empty() => {
            let target = rest.join(" ");
            (read_db(db, |s| {
                let rows: Vec<String> = notation::database_index_links::backlinks_of(s, &target)
                    .iter().map(|(k, r)| format!("{} {}", k, r)).collect();
                format!("backlinks {} {}", rows.len(), rows.join(";"))
            }), false)
        }
        ["broken"] => (read_db(db, |s| {
            let rows: Vec<String> = notation::database_index_links::broken_links(s)
                .iter().map(|(p, t)| format!("{} {}", p, if t.is_empty() { "<nothing>" } else { t.as_str() })).collect();
            format!("broken {} {}", rows.len(), rows.join(";"))
        }), false),
        ["names"] => (read_db(db, |s| {
            let rows: Vec<String> = s.of_kind("name").iter()
                .map(|r| format!("{} {}", r.field("name").unwrap_or(""), r.source))
                .collect();
            format!("names {} {}", rows.len(), rows.join(";"))
        }), false),
        ["git", rest @ ..] if !rest.is_empty() => (git_report(&rest.join(" ")), false),
        ["reload"] => {
            let root = ROOT.lock().unwrap_or_else(|e| e.into_inner()).clone();
            match root {
                Some(r) => handle(&["load", r.as_str()], programs, started, dev, db),
                None => (String::from("error no folder loaded, run load FOLDER first"), false),
            }
        }
        ["load", rest @ ..] if !rest.is_empty() => {
            let root = std::path::PathBuf::from(rest.join(" "));
            match notation::database_index_folder::index_folder(&root) {
                Err(e) => (format!("error {}", e.replace("\n", " ")), false),
                Ok(_) => {
                    let file = root.join(".notation").join("index.db");
                    match notation::database_file_format::load(&file) {
                        Err(e) => (format!("error {}", e.replace("\n", " ")), false),
                        Ok(store) => {
                            let answer = format!(
                                "loaded {} files {} blocks {} records",
                                store.of_kind("file").len(),
                                store.of_kind("block").len(),
                                store.len()
                            );
                            *ROOT.lock().unwrap_or_else(|e| e.into_inner()) = Some(root.to_string_lossy().to_string());
                            let full = fs::canonicalize(&root).unwrap_or(root.clone());
                            let _ = fs::write(state_dir().join("notation-root"), full.to_string_lossy().to_string());
                            *db.lock().unwrap_or_else(|e| e.into_inner()) = Some(store);
                            ws::broadcast("changed");
                            (answer, false)
                        }
                    }
                }
            }
        }
        ["stop"] => (String::from("stopping"), true),
        _ => (String::from("error unknown request"), false),
    }
}

type Db = Arc<Mutex<Option<notation::database_store::Store>>>;
type Programs = Arc<Mutex<BTreeMap<String, String>>>;
fn kind(rel: &str) -> String {
    let ext = rel.rsplit(".").next().unwrap_or("");
    let t = match ext {
        "html" => "text/html; charset=utf-8",
        "js" => "text/javascript; charset=utf-8",
        "css" => "text/css; charset=utf-8",
        "json" => "application/json",
        "wasm" => "application/wasm",
        "txt" => "text/plain; charset=utf-8",
        _ => "application/octet-stream",
    };
    t.to_string()
}
fn theme_hex(v: &str) -> Option<String> {
    if v == "none" {
        return Some(String::from("none"));
    }
    if v.len() == 7 && v.starts_with("#")
        && v[1..].bytes().all(|b| b.is_ascii_hexdigit())
    {
        return Some(v.to_lowercase());
    }
    let h = match v {
        "black" => "#000000",
        "red" => "#dc2828",
        "green" => "#28c828",
        "yellow" => "#dcc828",
        "blue" => "#3c64e6",
        "magenta" => "#c83cc8",
        "cyan" => "#28c8c8",
        "white" => "#ffffff",
        "gray" | "grey" => "#6e6e6e",
        _ => return None,
    };
    Some(String::from(h))
}
fn theme_text() -> String {
    let dir = match env::var("AIU_THEME_DIR") {
        Ok(d) if PathBuf::from(&d).is_dir() => Some(PathBuf::from(d)),
        _ => {
            let home = env::var("HOME").unwrap_or_default();
            fs::read_to_string(
                PathBuf::from(home).join(".config/aiu/theme-dir"))
                .ok()
                .map(|d| PathBuf::from(d.trim()))
                .filter(|p| p.is_dir())
        }
    };
    let body = dir.and_then(|d| {
        let n = fs::read_to_string(d.join("active")).ok()?;
        let n = n.trim().to_string();
        if n.is_empty()
            || !n.bytes().all(|b| b.is_ascii_alphanumeric() || b == 45 || b == 95)
        {
            return None;
        }
        fs::read_to_string(d.join(format!("{}.theme", n))).ok()
    });
    let mut roles: Vec<(String, String)> = vec![
        ("text", "#ffffff"), ("dim", "#6e6e6e"),
        ("error", "#dc2828"), ("bg", "none"),
        ("corner", "round"),
    ]
    .into_iter()
    .map(|(a, b)| (a.to_string(), b.to_string()))
    .collect();
    if let Some(body) = body {
        for l in body.lines() {
            if let Some((k, v)) = l.split_once("=") {
                if let Some(c) = theme_hex(v.trim()).or_else(|| {
                    let t = v.trim();
                    if k.trim() == "corner"
                        && (t == "round" || t == "square")
                    { Some(t.to_string()) } else { None }
                }) {
                    for r in roles.iter_mut() {
                        if r.0 == k.trim() {
                            r.1 = c.clone();
                        }
                    }
                }
            }
        }
    }
    roles.iter().map(|r| format!("{}={}\n", r.0, r.1)).collect::<String>()
}
fn http_file(path: &str) -> (u16, String, Vec<u8>) {
    let clean = path.split("?").next().unwrap_or("");
    let plain = |code: u16, text: &str| (code, String::from("text/plain; charset=utf-8"), text.as_bytes().to_vec());
    if let Some(q) = path.strip_prefix("/file?k=") {
        let b = q.as_bytes();
        let mut key: Vec<u8> = Vec::new();
        let mut i = 0;
        while i < b.len() {
            if b[i] == 37u8 && i + 2 < b.len() {
                let h = std::str::from_utf8(&b[i + 1..i + 3]).ok()
                    .and_then(|h| u8::from_str_radix(h, 16).ok());
                if let Some(v) = h {
                    key.push(v);
                    i += 3;
                    continue;
                }
            }
            key.push(b[i]);
            i += 1;
        }
        let key = String::from_utf8_lossy(&key).to_string();
        if key.is_empty() || key.contains("..") || key.contains("\0")
            || key.starts_with("/")
        {
            return plain(403, "error forbidden path");
        }
        let root = ROOT.lock().unwrap_or_else(|e| e.into_inner()).clone();
        return match root {
            None => plain(404, "error no folder loaded"),
            Some(r) => match fs::read(PathBuf::from(r).join(&key)) {
                Ok(bytes) => (200, String::from("text/plain; charset=utf-8"), bytes),
                Err(e) => plain(404, &format!("error {}", e)),
            },
        };
    }
    if clean == "/theme" {
        return (200, String::from("text/plain; charset=utf-8"),
            theme_text().into_bytes());
    }
    if clean == "/index.db" {
        let root = ROOT.lock().unwrap_or_else(|e| e.into_inner()).clone();
        return match root {
            None => plain(404, "error no index, run load FOLDER first"),
            Some(r) => match fs::read(PathBuf::from(r).join(".notation").join("index.db")) {
                Ok(bytes) => (200, kind("index.db"), bytes),
                Err(e) => plain(404, &format!("error {}", e)),
            },
        };
    }
    let mut rel = clean.trim_start_matches("/").to_string();
    if rel.is_empty() {
        rel = String::from("index.html");
    }
    if rel.contains("..") || rel.contains("\0") {
        return plain(403, "error forbidden path");
    }
    let dir = website_dir();
    match fs::read(dir.join(&rel)) {
        Ok(bytes) => (200, kind(&rel), bytes),
        Err(_) => plain(404, "error not found"),
    }
}
fn http_conn(stream: TcpStream, programs: &Programs, dev: &Arc<Mutex<DevState>>, db: &Db, started: u64) {
    let _ = stream.set_read_timeout(Some(Duration::from_secs(5)));
    let mut reader = BufReader::new(&stream);
    let mut first = String::new();
    if reader.read_line(&mut first).is_err() {
        return;
    }
    let mut wskey = String::new();
    let mut upgrade = false;
    let mut len = 0usize;
    loop {
        let mut h = String::new();
        if reader.read_line(&mut h).is_err() {
            return;
        }
        let t = h.trim_end().to_lowercase();
        if t.starts_with("sec-websocket-key:") {
            wskey = h.trim_end()[18..].trim().to_string();
        }
        if t.starts_with("upgrade:") && t.contains("websocket") {
            upgrade = true;
        }
        if t.is_empty() {
            break;
        }
        if let Some(v) = t.strip_prefix("content-length:") {
            len = v.trim().parse().unwrap_or(0);
        }
    }
    let plain = |code: u16, text: &str| (code, String::from("text/plain; charset=utf-8"), text.as_bytes().to_vec());
    if upgrade && !wskey.is_empty() && first.starts_with("GET ") {
        ws::serve(&stream, &wskey, reader, programs, dev, db, started);
        return;
    }
    let parts: Vec<&str> = first.split_whitespace().collect();
    let (code, ctype, data) = if len > 1_000_000 {
        plain(413, "error body too large")
    } else {
        let mut body = vec![0u8; len];
        if len > 0 && std::io::Read::read_exact(&mut reader, &mut body).is_err() {
            return;
        }
        match parts.as_slice() {
            ["POST", "/cmd", ..] => {
                let text = String::from_utf8_lossy(&body).to_string();
                let words: Vec<&str> = text.split_whitespace().collect();
                if words == ["stop"] {
                    plain(403, "error stop only from the socket")
                } else {
                    let mut map = programs.lock().unwrap_or_else(|e| e.into_inner());
                    let (answer, _) = handle_raw(&text, &mut map, started, dev, db);
                    plain(200, &answer)
                }
            }
            ["GET", path, ..] => http_file(path),
            _ => plain(405, "error method not allowed"),
        }
    };
    let reason = match code {
        200 => "OK",
        403 => "Forbidden",
        404 => "Not Found",
        405 => "Method Not Allowed",
        413 => "Payload Too Large",
        _ => "Error",
    };
    let head = format!("HTTP/1.1 {} {}\r\nContent-Type: {}\r\nContent-Length: {}\r\nConnection: close\r\n\r\n", code, reason, ctype, data.len());
    let mut out = &stream;
    let _ = out.write_all(head.as_bytes());
    let _ = out.write_all(&data);
}
fn http_door(programs: Programs, dev: Arc<Mutex<DevState>>, db: Db, started: u64) {
    let port: u16 = match env::var("AIU_SERVER_PORT") {
        Ok(p) => p.parse().unwrap_or(8080),
        Err(_) => 8080,
    };
    let listener = match TcpListener::bind(("127.0.0.1", port)) {
        Ok(l) => l,
        Err(e) => {
            println!("http door off at port {}: {}", port, e);
            return;
        }
    };
    println!("http door at 127.0.0.1:{}", port);
    for conn in listener.incoming() {
        let stream = match conn {
            Ok(s) => s,
            Err(_) => continue,
        };
        let p = Arc::clone(&programs);
        let d = Arc::clone(&dev);
        let b = Arc::clone(&db);
        thread::spawn(move || http_conn(stream, &p, &d, &b, started));
    }
}
fn serve() -> i32 {
    let path = socket_path();
    if ask("ping").is_ok() {
        println!("server already running at {}", path.display());
        return 1;
    }
    if let Some(parent) = path.parent() {
        if let Err(e) = fs::create_dir_all(parent) {
            println!("cannot create {}: {}", parent.display(), e);
            return 1;
        }
    }
    let _ = fs::remove_file(&path);
    let listener = match UnixListener::bind(&path) {
        Ok(l) => l,
        Err(e) => {
            println!("cannot bind {}: {}", path.display(), e);
            return 1;
        }
    };
    let started = now_seconds();
    let programs: Arc<Mutex<BTreeMap<String, String>>> = Arc::new(Mutex::new(BTreeMap::new()));
    let dev = Arc::new(Mutex::new(DevState { running: false, names: String::new(), last: String::from("none") }));
    let db: Arc<Mutex<Option<notation::database_store::Store>>> = Arc::new(Mutex::new(None));
    println!("server up at {} pid {}", path.display(), process::id());
    if let Ok(w) = env::var("AIU_WEBSITE_DIR") {
        if !w.is_empty() {
            let _ = fs::write(state_dir().join("website-dir"), w);
        }
    }
    if let Some(r) = state_text("notation-root") {
        let p = Arc::clone(&programs);
        let d = Arc::clone(&dev);
        let b = Arc::clone(&db);
        thread::spawn(move || {
            let _keep = p;
            let mut map: BTreeMap<String, String> = BTreeMap::new();
            let line = format!("load {}", r);
            let a = handle_raw(&line, &mut map, started, &d, &b).0;
            println!("startup load: {}", a);
        });
    }
    {
        let p = Arc::clone(&programs);
        let d = Arc::clone(&dev);
        let b = Arc::clone(&db);
        thread::spawn(move || http_door(p, d, b, started));
    }
    for conn in listener.incoming() {
        let stream = match conn {
            Ok(s) => s,
            Err(_) => continue,
        };
        let programs = Arc::clone(&programs);
        let dev = Arc::clone(&dev);
        let db = Arc::clone(&db);
        let sock = path.clone();
        thread::spawn(move || {
            let mut stream = stream;
            let _ = stream.set_read_timeout(Some(Duration::from_secs(5)));
            let mut line = String::new();
            if BufReader::new(&stream).read_line(&mut line).is_err() {
                return;
            }
            let (answer, stop) = {
                let mut map = programs.lock().unwrap_or_else(|e| e.into_inner());
                handle_raw(&line, &mut map, started, &dev, &db)
            };
            let _ = stream.write_all(answer.as_bytes());
            let _ = stream.write_all(b"\n");
            if stop {
                let _ = fs::remove_file(&sock);
                println!("server stopped");
                process::exit(0);
            }
        });
    }
    let _ = fs::remove_file(&path);
    println!("server stopped");
    0
}

fn main() {
    let args: Vec<String> = env::args().skip(1).collect();
    let code = match args.first().map(|s| s.as_str()) {
        None => {
            println!("ecosystem-server serve | ping | status | stop | register NAME MODE | unregister NAME | list | dev [NAME...] | dev-status");
            0
        }
        Some("serve") => serve(),
        Some(_) => match ask(&args.join(" ")) {
            Ok(answer) => {
                println!("{}", answer);
                0
            }
            Err(e) => {
                println!("{}", e);
                1
            }
        },
    };
    process::exit(code);
}



fn abs_path(p: &str) -> PathBuf {
    let q = PathBuf::from(p);
    if q.is_relative() {
        let root = ROOT.lock().unwrap_or_else(|e| e.into_inner()).clone();
        if let Some(r) = root {
            return PathBuf::from(r).join(q);
        }
    }
    q
}

fn commit_for(p: &std::path::Path, paths: &[&std::path::Path], msg: &str) -> String {
    let mut d = match p.parent() {
        Some(x) => x,
        None => return String::from("not committed, no parent folder"),
    };
    while !d.is_dir() {
        d = match d.parent() {
            Some(x) => x,
            None => return String::from("not committed, no parent folder"),
        };
    }
    let repo = match git_out(d, &["rev-parse", "--show-toplevel"]) {
        Some(r) => r,
        None => return String::from("not committed, no git repo or git missing"),
    };
    let r = std::path::Path::new(&repo);
    let names: Vec<String> = paths.iter().map(|x| x.to_string_lossy().to_string()).collect();
    let mut add: Vec<&str> = vec!["add", "-A", "--"];
    let mut st: Vec<&str> = vec!["status", "--porcelain", "--"];
    let mut cm: Vec<&str> = vec!["commit", "-q", "-m", msg, "--"];
    for n in &names {
        add.push(n.as_str());
        st.push(n.as_str());
        cm.push(n.as_str());
    }
    if git_out(r, &add).is_none() {
        return String::from("not committed, git add failed");
    }
    match git_out(r, &st) {
        Some(s) if s.is_empty() => return String::from("no change to commit"),
        None => return String::from("not committed, git status failed"),
        _ => {}
    }
    if git_out(r, &cm).is_some() {
        String::from("committed")
    } else {
        String::from("not committed, git commit failed, check user.name and user.email")
    }
}

fn save_first(p: &std::path::Path, why: &str) -> Result<(), String> {
    let s = commit_for(p, &[p], &format!("save {} before {}", p.display(), why));
    if s == "committed" || s == "no change to commit" {
        Ok(())
    } else {
        Err(format!("error {}, nothing changed", s))
    }
}

fn file_write(path: &str, content: Option<&str>) -> String {
    let content = match content {
        Some(c) if !c.is_empty() => c,
        _ => return String::from("error write needs content after a newline, use HTTP or WebSocket"),
    };
    let p = abs_path(path);
    if let Some(d) = p.parent() {
        if let Err(e) = fs::create_dir_all(d) {
            return format!("error {}", e);
        }
    }
    if let Err(e) = fs::write(&p, content) {
        return format!("error {}", e);
    }
    format!("written {} {}", path, commit_for(&p, &[&p], &format!("write {}", path)))
}

fn file_delete(path: &str) -> String {
    let p = abs_path(path);
    if !p.is_file() {
        return format!("error not a file {}", path);
    }
    if let Err(e) = save_first(&p, "delete") {
        return e;
    }
    if let Err(e) = fs::remove_file(&p) {
        return format!("error {}", e);
    }
    format!("deleted {} {}", path, commit_for(&p, &[&p], &format!("delete {}", path)))
}

fn file_move(from: &str, to: Option<&str>) -> String {
    let to = match to.map(|t| t.trim()) {
        Some(t) if !t.is_empty() => t,
        _ => return String::from("error move needs the target on a second line, use HTTP or WebSocket"),
    };
    let a = abs_path(from);
    let b = abs_path(to);
    if !a.is_file() {
        return format!("error not a file {}", from);
    }
    if let Err(e) = save_first(&a, "move") {
        return e;
    }
    if b.is_file() {
        if let Err(e) = save_first(&b, "overwrite") {
            return e;
        }
    }
    if let Some(d) = b.parent() {
        if let Err(e) = fs::create_dir_all(d) {
            return format!("error {}", e);
        }
    }
    if let Err(e) = fs::rename(&a, &b) {
        return format!("error {}", e);
    }
    let msg = format!("move {} to {}", from, to);
    format!("moved {} to {} {}", from, to, commit_for(&a, &[&a, &b], &msg))
}

fn handle_raw(text: &str, programs: &mut BTreeMap<String, String>, started: u64, dev: &Arc<Mutex<DevState>>, db: &Db) -> (String, bool) {
    let (first, rest) = match text.split_once("\n") {
        Some((a, b)) => (a.trim_end_matches("\r"), Some(b)),
        None => (text, None),
    };
    let words: Vec<&str> = first.split_whitespace().collect();
    match words.as_slice() {
        ["write", p @ ..] if !p.is_empty() => (file_write(&p.join(" "), rest), false),
        ["delete", p @ ..] if !p.is_empty() => (file_delete(&p.join(" ")), false),
        ["move", p @ ..] if !p.is_empty() => (file_move(&p.join(" "), rest), false),
        _ => handle(&words, programs, started, dev, db),
    }
}
