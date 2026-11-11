use std::collections::BTreeMap;
use std::env;
use std::fs;
use std::io::{BufRead, BufReader, Write};
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

fn handle(words: &[&str], programs: &mut BTreeMap<String, String>, started: u64, dev: &Arc<Mutex<DevState>>) -> (String, bool) {
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
        ["stop"] => (String::from("stopping"), true),
        _ => (String::from("error unknown request"), false),
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
    let mut programs: BTreeMap<String, String> = BTreeMap::new();
    let dev = Arc::new(Mutex::new(DevState { running: false, names: String::new(), last: String::from("none") }));
    println!("server up at {} pid {}", path.display(), process::id());
    for conn in listener.incoming() {
        let mut stream = match conn {
            Ok(s) => s,
            Err(_) => continue,
        };
        let _ = stream.set_read_timeout(Some(Duration::from_secs(5)));
        let mut line = String::new();
        if BufReader::new(&stream).read_line(&mut line).is_err() {
            continue;
        }
        let words: Vec<&str> = line.split_whitespace().collect();
        let (answer, stop) = handle(&words, &mut programs, started, &dev);
        let _ = stream.write_all(answer.as_bytes());
        let _ = stream.write_all(b"\n");
        if stop {
            break;
        }
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


