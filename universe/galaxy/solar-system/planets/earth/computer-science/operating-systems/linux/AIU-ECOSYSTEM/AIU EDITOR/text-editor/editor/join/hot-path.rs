
#[path = "../buffer/buffer.rs"]
mod buffer;
#[path = "../input/read.rs"]
mod input;
#[path = "../journal/journal.rs"]
mod journal;
#[path = "git-facts.rs"]
mod git_facts;
#[path = "wire-json.rs"]
mod wire_json;
#[path = "rust-exports.rs"]
mod rust_exports;

use std::env;
use std::fs;
use std::io::{BufRead, BufReader, Write};

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() >= 4 && args[1] == "serve" {
        serve(&args[2], &args[3]);
        return;
    }
    if args.len() < 3 {
        eprintln!("the hot path needs the request file and the answer file");
        std::process::exit(2);
    }
    let request_path = args[1].clone();
    let answer_path = args[2].clone();

    let request_text = match fs::read_to_string(&request_path) {
        Ok(text) => text,
        Err(why) => {
            eprintln!("the request file cannot be read: {}", why);
            std::process::exit(2);
        }
    };
    let line = request_text.lines().next().unwrap_or("");
    let request = match wire_json::read_request(line) {
        Some(request) => request,
        None => {
            write_answer(
                &answer_path,
                false,
                &[
                    ("kind".to_string(), "err-bad-request".to_string()),
                    ("what".to_string(), "the request line is not a request".to_string()),
                    ("what_to_do".to_string(), "ask for one op with string args".to_string()),
                ],
            );
            return;
        }
    };

    let (ok, data) = answer_for(&request);
    write_answer(&answer_path, ok, &data);
}

fn serve(request_path: &str, answer_path: &str) {
    let input = match fs::File::open(request_path) {
        Ok(file) => file,
        Err(why) => {
            eprintln!("the request pipe cannot be opened: {}", why);
            std::process::exit(2);
        }
    };
    let mut output = match fs::OpenOptions::new().write(true).open(answer_path) {
        Ok(file) => file,
        Err(why) => {
            eprintln!("the answer pipe cannot be opened: {}", why);
            std::process::exit(2);
        }
    };
    let reader = BufReader::new(input);
    for line in reader.lines() {
        let line = match line {
            Ok(line) => line,
            Err(_) => break,
        };
        if line.trim().is_empty() {
            continue;
        }
        let (ok, data) = match wire_json::read_request(&line) {
            Some(request) => answer_for(&request),
            None => (
                false,
                vec![
                    ("kind".to_string(), "err-bad-request".to_string()),
                    ("what".to_string(), "the request line is not a request".to_string()),
                    ("what_to_do".to_string(), "ask for one op with string args".to_string()),
                ],
            ),
        };
        let text = wire_json::write_response(ok, &data);
        if writeln!(output, "{}", text).is_err() {
            break;
        }
        if output.flush().is_err() {
            break;
        }
    }
}

fn answer_for(request: &wire_json::Request) -> (bool, Vec<(String, String)>) {
    let file = wire_json::arg(request, "file");
    let journal_path = wire_json::arg(request, "journal");
    let op = request.op.as_str();

    match op {
        rust_exports::OP_GIT_HISTORY => {
            let path = std::path::Path::new(&file);
            (true, git_facts::history(path))
        }        rust_exports::OP_GIT_DIFF => {
            let path = std::path::Path::new(&file);
            let asked = wire_json::arg(request, "comparison");
            (true, git_facts::diff(path, &asked))
        }
        rust_exports::OP_NOTATION => {
            let text = current_text(&file, &journal_path);
            let document = notation::rust_exports::parse_document(&file, &text);
            (
                true,
                vec![("document".to_string(), document)],
            )
        }
        rust_exports::OP_NOTATION_RENDER => {
            let text = current_text(&file, &journal_path);
            let rendered = notation::plain::render_plain(&text);
            (true, vec![("text".to_string(), rendered)])
        }
        rust_exports::OP_NOTATION_VIEW => {
            let text = current_text(&file, &journal_path);
            let width = wire_json::arg(request, "width")
                .trim()
                .parse::<usize>()
                .unwrap_or(56);
            let read = wire_json::arg(request, "mode").trim().to_string();
            match notation_view(&text, width, &file, &read) {
                Ok(rendered) => (true, vec![("text".to_string(), rendered)]),
                Err(why) => (
                    false,
                    vec![
                        ("kind".to_string(), "err-view-unavailable".to_string()),
                        ("what".to_string(), why),
                        (
                            "what_to_do".to_string(),
                            "build the notation package's own binary, or set AIU_NOTATION_BIN"
                                .to_string(),
                        ),
                    ],
                ),
            }
        }
        rust_exports::OP_GIT => {
            let path = std::path::Path::new(&file);
            (true, git_facts::facts(path))
        }
        rust_exports::OP_OPEN => {
            let text = current_text(&file, &journal_path);
            let text = if journal::records(&journal_path).is_empty() { let synced = sync_contracts(&text, &file); if synced != text { let _ = fs::write(&file, &synced); } synced } else { text };
            let state = buffer::new_buffer(&text);
            let pending = journal::records(&journal_path).len();
            let mut facts = vec![
                ("file".to_string(), file.clone()),
                ("lines".to_string(), buffer::line_count(&state).to_string()),
                ("bytes".to_string(), buffer::byte_len(&state).to_string()),
                ("pending".to_string(), pending.to_string()),
            ];
            (true, facts)
        }
        rust_exports::OP_INSERT => {
            let more = wire_json::arg(request, "text");
            let text = current_text(&file, &journal_path);
            if locked(&text, text.len(), 0, &more) {
                return refused();
            }
            let mut state = buffer::new_buffer(&text);
            let bytes = buffer::append(&mut state, &more);
            let record = format!("insert {}", journal::escape(&more));
            let pending = journal::append_record(&journal_path, &record);
            (
                true,
                vec![
                    ("bytes".to_string(), bytes.to_string()),
                    ("lines".to_string(), buffer::line_count(&state).to_string()),
                    ("pending".to_string(), pending.to_string()),
                ],
            )
        }
        rust_exports::OP_SAVE => {
            let text = current_text(&file, &journal_path);
            let text = sync_contracts(&text, &file);
            let before = fs::read_to_string(&file).unwrap_or_default();
            if let Err(why) = fs::write(&file, &text) {
                return (
                    false,
                    vec![
                        ("kind".to_string(), "err-no-save".to_string()),
                        ("what".to_string(), format!("the file cannot be written: {}", why)),
                        ("what_to_do".to_string(), "check the path and its permissions".to_string()),
                    ],
                );
            }
            notify_server(&file, &text);
            journal::archive(&journal_path, &before);
            journal::clear(&journal_path);
            let state = buffer::new_buffer(&text);
            (
                true,
                vec![
                    ("file".to_string(), file),
                    ("bytes".to_string(), buffer::byte_len(&state).to_string()),
                    ("lines".to_string(), buffer::line_count(&state).to_string()),
                    ("pending".to_string(), "0".to_string()),
                ],
            )
        }
        rust_exports::OP_SHOW => {
            let text = current_text(&file, &journal_path);
            let state = buffer::new_buffer(&text);
            (
                true,
                vec![
                    ("text".to_string(), buffer::text_of(&state).to_string()),
                    ("lines".to_string(), buffer::line_count(&state).to_string()),
                    ("bytes".to_string(), buffer::byte_len(&state).to_string()),
                ],
            )
        }
        rust_exports::OP_JOURNAL => {
            let records = journal::records(&journal_path);
            (
                true,
                vec![
                    ("count".to_string(), records.len().to_string()),
                    ("records".to_string(), records.join("\n")),
                ],
            )
        }
        rust_exports::OP_REPLAY => {
            let text = current_text(&file, &journal_path);
            let state = buffer::new_buffer(&text);
            let records = journal::records(&journal_path);
            (
                true,
                vec![
                    ("text".to_string(), buffer::text_of(&state).to_string()),
                    ("lines".to_string(), buffer::line_count(&state).to_string()),
                    ("bytes".to_string(), buffer::byte_len(&state).to_string()),
                    ("pending".to_string(), records.len().to_string()),
                    ("records".to_string(), records.join("\n")),
                ],
            )
        }
        rust_exports::OP_KEYS => {
            let bytes = input::from_hex(&wire_json::arg(request, "bytes"));
            let mut reader = input::new_reader();
            input::push(&mut reader, &bytes);
            let mut names: Vec<String> = Vec::new();
            let mut lengths: Vec<String> = Vec::new();
            loop {
                match input::next_key(&mut reader) {
                    Some(key) => {
                        names.push(key.name);
                        lengths.push(key.length.to_string());
                    }
                    None => break,
                }
            }
            (
                true,
                vec![
                    ("count".to_string(), names.len().to_string()),
                    ("names".to_string(), names.join(" ")),
                    ("lengths".to_string(), lengths.join(",")),
                    ("pending".to_string(), input::pending(&reader).to_string()),
                ],
            )
        }
        rust_exports::OP_INSERT_AT => {
            let at = wire_json::arg(request, "at")
                .trim()
                .parse::<usize>()
                .unwrap_or(0);
            let more = wire_json::arg(request, "text");
            let text = current_text(&file, &journal_path);
            if locked(&text, at, 0, &more) {
                return refused();
            }
            let mut state = buffer::new_buffer(&text);
            let bytes = buffer::insert_at(&mut state, at, &more);
            let record = format!("insert-at {} {}", at, journal::escape(&more));
            let pending = journal::append_record(&journal_path, &record);
            (
                true,
                vec![
                    ("bytes".to_string(), bytes.to_string()),
                    ("lines".to_string(), buffer::line_count(&state).to_string()),
                    ("at".to_string(), at.to_string()),
                    ("pending".to_string(), pending.to_string()),
                ],
            )
        }
        rust_exports::OP_DELETE_AT => {
            let at = wire_json::arg(request, "at")
                .trim()
                .parse::<usize>()
                .unwrap_or(0);
            let count = wire_json::arg(request, "count")
                .trim()
                .parse::<usize>()
                .unwrap_or(0);
            let text = current_text(&file, &journal_path);
            if count > 0 && locked(&text, at, count, "") {
                return refused();
            }
            let mut state = buffer::new_buffer(&text);
            let bytes = buffer::delete_at(&mut state, at, count);
            let record = format!("delete-at {} {}", at, count);
            let pending = journal::append_record(&journal_path, &record);
            (
                true,
                vec![
                    ("bytes".to_string(), bytes.to_string()),
                    ("lines".to_string(), buffer::line_count(&state).to_string()),
                    ("pending".to_string(), pending.to_string()),
                ],
            )
        }
        rust_exports::OP_MOVE => {
            let at = wire_json::arg(request, "at")
                .trim()
                .parse::<usize>()
                .unwrap_or(0);
            let direction = wire_json::arg(request, "direction");
            let text = current_text(&file, &journal_path);
            let state = buffer::new_buffer(&text);
            (
                true,
                vec![
                    ("at".to_string(), buffer::move_point(&state, at, &direction).to_string()),
                    ("line".to_string(), buffer::line_of(&state, at).to_string()),
                ],
            )
        }
        rust_exports::OP_SELECT => {
            let from = wire_json::arg(request, "from")
                .trim()
                .parse::<usize>()
                .unwrap_or(0);
            let to = wire_json::arg(request, "to")
                .trim()
                .parse::<usize>()
                .unwrap_or(0);
            let text = current_text(&file, &journal_path);
            let state = buffer::new_buffer(&text);
            let chosen = buffer::text_range(&state, from, to);
            (
                true,
                vec![
                    ("text".to_string(), chosen),
                    ("bytes".to_string(), buffer::byte_len(&state).to_string()),
                ],
            )
        }
        rust_exports::OP_KEY_BYTES => {
            let name = wire_json::arg(request, "name");
            match input::encode_name(&name) {
                Some(bytes) => (
                    true,
                    vec![
                        ("name".to_string(), name),
                        ("bytes".to_string(), input::to_hex(&bytes)),
                    ],
                ),
                None => (
                    false,
                    vec![
                        ("kind".to_string(), "err-unknown-key".to_string()),
                        ("what".to_string(), format!("there is no key named {}", name)),
                        ("what_to_do".to_string(), "ask for a key the decoder knows".to_string()),
                    ],
                ),
            }
        }
        _ => (
            false,
            vec![
                ("kind".to_string(), "err-unknown-op".to_string()),
                ("what".to_string(), format!("there is no operation named {}", op)),
                ("what_to_do".to_string(), "ask for one of: open, insert, save, show, journal, replay".to_string()),
            ],
        ),
    }
}

fn refused() -> (bool, Vec<(String, String)>) {
    (
        false,
        vec![
            ("kind".to_string(), "err-read-only".to_string()),
            (
                "what".to_string(),
                "a contract block is read only".to_string(),
            ),
            (
                "what_to_do".to_string(),
                "edit outside the contract block".to_string(),
            ),
        ],
    )
}

fn contract_spans(text: &str) -> Vec<(usize, usize)> {
    let mut spans = Vec::new();
    let mut open: Option<usize> = None;
    let mut off = 0usize;
    for line in text.split("\n") {
        let t = line.trim();
        if t == "contract start" && open.is_none() {
            open = Some(off);
        }
        if t == "contract end" {
            if let Some(s) = open.take() {
                spans.push((s, off + line.len()));
            }
        }
        off += line.len() + 1;
    }
    spans
}

fn locked(text: &str, at: usize, count: usize, more: &str) -> bool {
    contract_spans(text).iter().any(|&(s, e)| {
        if count == 0 {
            (at > s && at <= e) || (at == s && !more.ends_with("\n"))
        } else {
            at < e + 1 && at + count > s
        }
    })
}

fn current_text(file: &str, journal_path: &str) -> String {
    let saved = match fs::read_to_string(file) {
        Ok(text) => text,
        Err(_) => String::new(),
    };
    let records = journal::records(journal_path);
    journal::replay(&saved, &records)
}

fn write_answer(answer_path: &str, ok: bool, data: &[(String, String)]) {
    let text = wire_json::write_response(ok, data);
    if let Err(why) = fs::write(answer_path, format!("{}\n", text)) {
        eprintln!("the answer file cannot be written: {}", why);
        std::process::exit(2);
    }
}

fn sync_contracts(text: &str, file: &str) -> String {
    let named = std::env::var("AIU_NOTATION_BIN").unwrap_or_default();
    if !file.ends_with(".aiu") || named.is_empty() {
        return text.to_string();
    }
    let temp = std::env::temp_dir()
        .join(format!("aiu-editor-sync-{}.aiu", std::process::id()));
    if std::fs::write(&temp, text).is_err() {
        return text.to_string();
    }
    let dir = std::path::Path::new(file)
        .parent()
        .map(|p| p.to_path_buf())
        .unwrap_or_default();
    let ran = std::process::Command::new(&named)
        .env("AIU_PAGE_DIR", dir)
        .arg("fill")
        .arg(&temp)
        .output();
    let synced = match ran {
        Ok(out) if out.status.success() => std::fs::read_to_string(&temp),
        _ => Err(std::io::Error::from(std::io::ErrorKind::Other)),
    };
    let _ = std::fs::remove_file(&temp);
    synced.unwrap_or_else(|_| text.to_string())
}

fn notation_view(text: &str, width: usize, file: &str, read: &str) -> Result<String, String> {
    let named = std::env::var("AIU_NOTATION_BIN").unwrap_or_default();
    let bin = if named.is_empty() {
        std::path::PathBuf::from(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../notation/target/debug/notation"
        ))
    } else {
        std::path::PathBuf::from(named)
    };
    if !bin.exists() {
        return Err(format!("the notation view is not built: {} is not there", bin.display()));
    }
    let temp = std::env::temp_dir()
        .join(format!("aiu-editor-view-{}.aiu", std::process::id()));
    std::fs::write(&temp, text)
        .map_err(|e| format!("the page could not be written to draw it: {}", e))?;
    let drawn = std::process::Command::new(&bin)
        .env("AIU_PAGE_DIR", std::path::Path::new(file).parent().map(|p| p.to_path_buf()).unwrap_or_default())
        .arg("view").arg(&temp)
        .arg("--width").arg(width.to_string())
        .arg("--contracts").args(match read {
            "read" => vec!["--read"],
            "read-pins" => vec!["--read", "--keep-pins"],
            _ => vec![],
        })
        .output();
    let _ = std::fs::remove_file(&temp);
    let output = drawn.map_err(|e| format!("the notation view could not run: {}", e))?;
    if !output.status.success() {
        return Err(format!(
            "the notation view refused the page: {}",
            String::from_utf8_lossy(&output.stderr).trim()
        ));
    }
    Ok(String::from_utf8_lossy(&output.stdout).to_string())
}

fn notify_server(file: &str, text: &str) {
    use std::net::{SocketAddr, TcpStream};
    use std::time::Duration;
    let path = match fs::canonicalize(file) {
        Ok(p) => p.to_string_lossy().to_string(),
        Err(_) => return,
    };
    let port = env::var("AIU_SERVER_PORT").unwrap_or_else(|_| String::from("8080"));
    let addr: SocketAddr = match format!("127.0.0.1:{}", port).parse() {
        Ok(a) => a,
        Err(_) => return,
    };
    let body = format!("write {}\n{}", path, text);
    let req = format!(
        "POST /cmd HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
        body.len(),
        body
    );
    if let Ok(mut s) = TcpStream::connect_timeout(&addr, Duration::from_millis(300)) {
        let _ = s.set_write_timeout(Some(Duration::from_secs(2)));
        let _ = s.write_all(req.as_bytes());
        let _ = s.flush();
    }
}
