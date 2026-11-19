//! One job: the five commands — parse, render, render-rich, roundtrip, todos — one file path each.
//! provisional 2026-07-17
//! alongside the binary target in Cargo.toml.
//!
//! This binary exists for the one by-hand run allowed.
//! Nothing here is automatic, nothing writes outside /tmp unless it is told to,
//! and every failure is named rather than turned into a quiet zero.

use std::time::Instant;
#[path = "rendering/view.rs"]
mod view;
#[path = "rendering/boxview.rs"]
mod boxview;
#[path = "rendering/theme.rs"]
mod theme;
#[path = "rendering/edition.rs"]
mod edition;
#[path = "rendering/contract-files.rs"]
mod contract_files;

use notation::buffer::Buffer;
use notation::parser::{parse, Node};
use notation::plain::render_plain;
use notation::rich::render_rich;
use notation::rust_exports::parse_document;

/// The columns the rich render draws into when the caller names none. The
/// binary cannot ask the terminal, so it picks a phone's width and says so.
const RICH_DEFAULT_WIDTH: usize = 40;

// usage prints how the binary is called, so a wrong call says what the
// right one is.
/// Say how to call the binary: the five commands and the one file path they take.
fn usage() {
    eprintln!("usage: notation <parse|render|render-rich|roundtrip|todos> <file>  or  notation index <folder>");
    eprintln!("       notation <load|reload|links|backlinks|broken|names> [args]  or  notation new FILE (text on stdin)");
}
// main reads the command and the file, and hands the work to the one
// command that knows it.

/// Read the file, run the one command named, and exit with the code it earns.
fn page_anchor(path: &str) -> std::path::PathBuf {
    match std::env::var("AIU_PAGE_DIR") {
        Ok(d) if !d.is_empty() => std::path::PathBuf::from(d).join("page.aiu"),
        _ => std::path::PathBuf::from(path),
    }
}


fn ask_server(cmd: &str) -> Result<String, String> {
    use std::io::{Read, Write};
    use std::net::{SocketAddr, TcpStream};
    use std::time::Duration;
    let port = std::env::var("AIU_SERVER_PORT").unwrap_or_else(|_| String::from("8080"));
    let addr: SocketAddr = format!("127.0.0.1:{}", port).parse().map_err(|_| String::from("bad port"))?;
    let mut s = TcpStream::connect_timeout(&addr, Duration::from_millis(500)).map_err(|e| e.to_string())?;
    let _ = s.set_read_timeout(Some(Duration::from_secs(60)));
    let req = format!(
        "POST /cmd HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
        cmd.len(),
        cmd
    );
    s.write_all(req.as_bytes()).map_err(|e| e.to_string())?;
    let mut out = String::new();
    s.read_to_string(&mut out).map_err(|e| e.to_string())?;
    match out.split_once("\r\n\r\n") {
        Some((_, body)) => Ok(body.to_string()),
        None => Err(String::from("no answer")),
    }
}

fn write_file(path: &str, text: &str) -> Result<(), String> {
    let p = std::path::Path::new(path);
    let abs = match std::fs::canonicalize(p) {
        Ok(a) => a,
        Err(_) => {
            let dir = match p.parent() {
                Some(d) if !d.as_os_str().is_empty() => d.to_path_buf(),
                _ => std::path::PathBuf::from("."),
            };
            let d = std::fs::canonicalize(dir).map_err(|e| e.to_string())?;
            match p.file_name() {
                Some(n) => d.join(n),
                None => return Err(String::from("bad path")),
            }
        }
    };
    let cmd = format!("write {}\n{}", abs.to_string_lossy(), text);
    match ask_server(&cmd) {
        Ok(a) if !a.contains("no folder loaded") => Ok(()),
        _ => {
            std::fs::write(path, text).map_err(|e| e.to_string())?;
            eprintln!("notation: no server used, file written directly");
            Ok(())
        }
    }
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let server_cmds = ["load", "reload", "links", "backlinks", "broken", "names"];
    if args.len() >= 2 && server_cmds.contains(&args[1].as_str()) {
        let mut parts: Vec<String> = args[1..].to_vec();
        if args[1] == "load" && parts.len() > 1 {
            if let Ok(p) = std::fs::canonicalize(&parts[1]) {
                parts[1] = p.to_string_lossy().to_string();
            }
        }
        match ask_server(&parts.join(" ")) {
            Ok(a) => {
                println!("{}", a.trim_end());
                return;
            }
            Err(e) => {
                eprintln!("notation: no server ({}), start it with: ecosystem serve", e);
                std::process::exit(1);
            }
        }
    }
    if args.len() < 3 {
        usage();
        std::process::exit(2);
    }
    if args.len() >= 3 && args[1] == "new" {
        if std::path::Path::new(&args[2]).exists() {
            eprintln!("notation: {} exists", args[2]);
            std::process::exit(2);
        }
        let mut body = String::new();
        {
            use std::io::Read;
            let _ = std::io::stdin().read_to_string(&mut body);
        }
        if body.trim().is_empty() {
            eprintln!("notation: no page text on stdin");
            std::process::exit(2);
        }
        match write_file(&args[2], &body) {
            Ok(()) => {
                println!("created {}", args[2]);
                return;
            }
            Err(e) => {
                eprintln!("notation: {}", e);
                std::process::exit(1);
            }
        }
    }
    if args[1] == "index" {
        match notation::database_index_folder::index_folder(std::path::Path::new(&args[2])) {
            Ok(summary) => {
                println!("{}", summary);
                return;
            }
            Err(e) => {
                eprintln!("notation: {}", e);
                std::process::exit(1);
            }
        }
    }
    let command = args[1].clone();
    let path = args[2].clone();
    contract_files::set_page(&path);
    if let Some(folder) = notation::block_registry::load_near(&page_anchor(&path)) {
        eprintln!("notation: block types from {}", folder);
    }

    let text = match std::fs::read_to_string(&path) {
        Ok(t) => t,
        Err(e) => {
            eprintln!("notation: cannot read {}: {}", path, e);
            std::process::exit(2);
        }
    };

    match command.as_str() {
        // Print the payload document on stdout, and the parse time on stderr,
        // so the document can be redirected to a file and still be parseable.
        // Print the page formatted for a terminal: numbers, frames, colour.
        "view" => {
            let (mut width, mut plain, mut i) = (56usize, false, 3usize);
            let mut contracts = false;
            let mut flat = false;
            while i < args.len() {
                if args[i] == "--plain" { plain = true; } else if args[i] == "--contracts" { contracts = true; } else if args[i] == "--flat" { flat = true; } else if args[i] == "--read" { boxview::set_read(true); } else if args[i] == "--keep-pins" { boxview::set_keep(true); }
                else if args[i] == "--width" && i + 1 < args.len() { width = args[i + 1].parse().unwrap_or(56); i += 1; }
                i += 1;
            }
            if flat { print!("{}", view::render_view(&text, width, plain, contracts)); } else { print!("{}", boxview::render_boxes(&text, width, plain, contracts)); }
        }
        "contracts" => {
            let text = match boxview::fill_page(&text) {
                Ok((new, _)) => {
                    if new != text {
                        if let Err(e) = write_file(&path, &new) {
                            eprintln!("notation: cannot write {}: {}", path, e);
                            std::process::exit(2);
                        }
                    }
                    new
                }
                Err(e) => {
                    eprintln!("notation: {}", e);
                    std::process::exit(2);
                }
            };
            let mut stack: Vec<(String, String)> = Vec::new();
            let mut found: Vec<(String, String, String)> = Vec::new();
            let mut answered: Vec<String> = Vec::new();
            let lines: Vec<&str> = text.lines().collect();
            let mut k = 0;
            while k < lines.len() {
                let l = lines[k].trim();
                if l == "contract start" {
                    let mut id = String::new();
                    let mut q = String::new();
                    k += 1;
                    while k < lines.len() && lines[k].trim() != "contract end" {
                        let t = lines[k].trim();
                        if let Some(v) = t.strip_prefix("id:") { id = v.trim().to_string(); }
                        if let Some(v) = t.strip_prefix("question:") { q = v.trim().to_string(); }
                        k += 1;
                    }
                    let at = match stack.last() {
                        Some(s) => format!("{} {}", s.0, s.1),
                        None => String::new(),
                    };
                    found.push((id, at, q));
                } else if l == "answer start" {
                    let mut id = String::new();
                    let mut body = false;
                    k += 1;
                    while k < lines.len() && lines[k].trim() != "answer end" {
                        let t = lines[k].trim();
                        if let Some(v) = t.strip_prefix("for:") {
                            id = v.trim().to_string();
                        } else if !t.starts_with("asked:") && !t.is_empty() {
                            body = true;
                        }
                        k += 1;
                    }
                    let at = match stack.last() {
                        Some(s) => format!("{} {}", s.0, s.1),
                        None => String::new(),
                    };
                    if body { answered.push(format!("{}|{}", id, at)); }
                } else if let Some(n) = l.strip_suffix(" start") {
                    if !n.contains(" ") { stack.push((n.to_string(), String::new())); }
                } else if let Some(n) = l.strip_suffix(" end") {
                    if !n.contains(" ") { stack.pop(); }
                } else if let Some(v) = l.strip_prefix("name:") {
                    if let Some(s) = stack.last_mut() {
                        if s.1.is_empty() { s.1 = v.trim().to_string(); }
                    }
                }
                k += 1;
            }
            let all = args.iter().skip(3).any(|a| a == "--all");
            let open: Vec<&(String, String, String)> =
                found.iter().filter(|f| all || !answered.contains(&format!("{}|{}", f.0, f.1))).collect();
            println!("{}: {}", if all { "all" } else { "open" }, open.len());
            for f in open {
                let done = answered.contains(&format!("{}|{}", f.0, f.1));
                println!("\n{}  {}{}\n{}", f.0, f.1, if done { "  [answered]" } else { "" }, f.2);
            }
        }
        // Add an empty answer slot under every question that has none; never touches an answer.
        "fill" => {
            match boxview::fill_page(&text) {
                Ok((new, report)) => {
                    if new != text {
                        if let Err(e) = write_file(&path, &new) {
                            eprintln!("notation: cannot write {}: {}", path, e);
                            std::process::exit(2);
                        }
                    }
                    for l in report { println!("{}", l); }
                }
                Err(e) => {
                    eprintln!("notation: {}", e);
                    std::process::exit(2);
                }
            }
        }
        "edition" => {
            let mut width = 0usize;
            let mut lines = 0usize;
            let mut margin = 0usize;
            let mut paper = String::new();
            let mut i = 3usize;
            while i + 1 < args.len() {
                if args[i] == "--width" { width = args[i + 1].parse().unwrap_or(0); }
                if args[i] == "--lines" { lines = args[i + 1].parse().unwrap_or(0); }
                if args[i] == "--margin" { margin = args[i + 1].parse().unwrap_or(0); }
                if args[i] == "--paper" { paper = args[i + 1].to_lowercase(); }
                i += 1;
            }
            let (pw, pl) = match paper.as_str() {
                "" => (56, 40),
                "a6" => (40, 30),
                "a5" => (50, 40),
                "a4" => (66, 52),
                "letter" => (68, 50),
                _ => {
                    eprintln!("unknown paper: {} (a6 a5 a4 letter)", paper);
                    std::process::exit(1);
                }
            };
            if width == 0 { width = pw; }
            if lines == 0 { lines = pl; }
            print!("{}", edition::render(&text, &path, width, lines, margin));
        }
        "parse" => {
            let started = Instant::now();
            let document = parse_document(&path, &text);
            let elapsed = started.elapsed();
            print!("{}", document);
            eprintln!("parse-ms: {}", elapsed.as_millis());
        }
        // Print the plain render: the marks are gone, the content is not.
        "render" => {
            print!("{}", render_plain(&text));
        }
        // Print the rich render: the same content, drawn with unicode.
        "render-rich" => {
            print!("{}", render_rich(&text, RICH_DEFAULT_WIDTH));
        }
        // Say whether the tree prints back to the identical bytes.
        "roundtrip" => {
            let buffer = Buffer::from_text(&text);
            let tree = parse(&buffer);
            let printed = tree.print_back(&buffer);
            if tree.round_trips(&buffer) {
                println!("roundtrip: identical ({} bytes)", printed.len());
            } else {
                println!("roundtrip: not identical ({} bytes out)", printed.len());
                std::process::exit(1);
            }
        }
        // List every todo in the page. A todo may sit on any block and inside
        // any comment, so the whole page is read line by line.
        "todos" => {
            let buffer = Buffer::from_text(&text);
            let tree = parse(&buffer);
            let mut opaque: Vec<(usize, usize)> = Vec::new();
            collect_opaque_bodies(&tree.nodes, &buffer, &mut opaque);
            for line in todo_lines(&text, &opaque) {
                println!("{}", line);
            }
        }
        other => {
            eprintln!("notation: no command named {}", other);
            usage();
            std::process::exit(2);
        }
    }
}

// collect_opaque_bodies gathers the line ranges of the bodies of the opaque
// blocks in the tree. A code body is not read as notation, so a todo written
// there is not a todo of the page.
fn collect_opaque_bodies(nodes: &[Node], buffer: &Buffer, out: &mut Vec<(usize, usize)>) {
    for node in nodes {
        if let Node::Block(block) = node {
            if block.is_opaque() {
                let end_line = buffer.line_at(block.span.end);
                if end_line > block.line + 1 {
                    out.push((block.line + 1, end_line - 1));
                }
            }
            collect_opaque_bodies(&block.children, buffer, out);
        }
    }
}

// todo_lines reads the page line by line and answers every todo it holds. The
// page is read as a whole and not through the tree, because the tree knows a
// declaration only when the line is straight under the start line, and a todo
// must be found wherever it is written.
fn todo_lines(text: &str, opaque: &[(usize, usize)]) -> Vec<String> {
    let mut found = Vec::new();
    for (index, line) in text.split('\n').enumerate() {
        let number = index + 1;
        let hidden = opaque.iter().any(|(first, last)| number >= *first && number <= *last);
        if hidden {
            continue;
        }
        let trimmed = line.trim_start();
        if let Some(words) = trimmed.strip_prefix("todo:") {
            found.push(format!("todo line {}: {}", number, words.trim()));
        }
    }
    found
}
