use super::*;
use std::io::{BufRead, BufReader, Write};
use std::process::{Child, ChildStdin, ChildStdout, Command, Stdio};
use std::sync::Mutex;

const RACKET_BAR_SERVER_FILE: &str = concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/../editor-code/editor/tui/bar/bar-lines-server.rkt"
);

struct RacketBarServer {
    child: Child,
    input: ChildStdin,
    output: BufReader<ChildStdout>,
}

impl Drop for RacketBarServer {
    fn drop(&mut self) {
        let _ = self.child.kill();
    }
}

static RACKET_BAR_SERVER: Mutex<Option<RacketBarServer>> = Mutex::new(None);

fn racket_bar_server_start() -> Result<RacketBarServer, String> {
    let home = std::env::var("HOME").unwrap_or_default();
    let mut child = Command::new("racket")
        .arg(RACKET_BAR_SERVER_FILE)
        .env("LC_ALL", "C.UTF-8")
        .env("PLTCOMPILEDROOTS", format!("{}/aiu-compiled", home))
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|why| format!("racket cannot start: {}", why))?;
    let input = child.stdin.take().ok_or_else(|| "racket has no stdin".to_string())?;
    let output = child.stdout.take().ok_or_else(|| "racket has no stdout".to_string())?;
    Ok(RacketBarServer { child, input, output: BufReader::new(output) })
}

fn racket_bar_server_ask(
    server: &mut RacketBarServer,
    layer: &str,
    short: &str,
    width: usize,
) -> Result<Vec<String>, String> {
    writeln!(server.input, "{}\t{}\t{}", layer, short, width)
        .map_err(|why| format!("racket write failed: {}", why))?;
    server
        .input
        .flush()
        .map_err(|why| format!("racket flush failed: {}", why))?;
    let mut rows: Vec<String> = Vec::new();
    loop {
        let mut line = String::new();
        let read = server
            .output
            .read_line(&mut line)
            .map_err(|why| format!("racket read failed: {}", why))?;
        if read == 0 {
            return Err("racket closed its output".to_string());
        }
        let row = line.trim_end_matches(char::is_control).to_string();
        if row.is_empty() {
            return Ok(rows);
        }
        rows.push(row);
    }
}

pub(crate) fn bar_lines_from_racket(layer: &str, short: &str, width: usize) -> Vec<String> {
    let mut held = RACKET_BAR_SERVER
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    if held.is_none() {
        match racket_bar_server_start() {
            Ok(server) => *held = Some(server),
            Err(why) => return vec![body_line(&why, width)],
        }
    }
    let clean = short.replace("\t", " ").replace("\n", " ");
    let result = match held.as_mut() {
        Some(server) => racket_bar_server_ask(server, layer, &clean, width),
        None => Err("racket bar server is not running".to_string()),
    };
    match result {
        Ok(rows) => rows,
        Err(why) => {
            *held = None;
            vec![body_line(&why, width)]
        }
    }
}
