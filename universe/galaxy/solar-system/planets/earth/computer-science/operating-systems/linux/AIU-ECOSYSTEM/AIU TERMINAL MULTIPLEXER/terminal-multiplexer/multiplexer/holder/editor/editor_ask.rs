
use std::io::{BufRead, BufReader, Read, Write};
use std::process::{Command, Stdio};
use std::time::Instant;

use serde_json::{json, Value};

pub struct Answer {
    pub ok: bool,
    pub data: Value,
}

pub fn ask(command: &[String], capability: &str) -> Answer {
    if command.is_empty() {
        return Answer {
            ok: false,
            data: json!({
                "why": "there is no command for the editor's server: give one with --editor-mcp-arg"
            }),
        };
    }
    let started = Instant::now();
    let mut child = match Command::new(&command[0])
        .args(&command[1..])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
    {
        Ok(child) => child,
        Err(why) => {
            return Answer {
                ok: false,
                data: json!({
                    "why": format!("the editor's server did not start: {}", why),
                    "command": command,
                }),
            }
        }
    };
    {
        let mut stdin = match child.stdin.take() {
            Some(stdin) => stdin,
            None => {
                return Answer {
                    ok: false,
                    data: json!({ "why": "the editor's server has no input to read" }),
                }
            }
        };
        let handshake = json!({
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": {
                "protocolVersion": "2024-11-05",
                "capabilities": {},
                "clientInfo": { "name": "multiplexer", "version": "1" }
            }
        });
        let call = json!({
            "jsonrpc": "2.0",
            "id": 2,
            "method": "tools/call",
            "params": { "name": capability, "arguments": { "args": [] } }
        });
        if let Err(why) = writeln!(stdin, "{}", handshake)
            .and_then(|_| writeln!(stdin, "{}", call))
            .and_then(|_| stdin.flush())
        {
            return Answer {
                ok: false,
                data: json!({ "why": format!("the editor's server was not asked: {}", why) }),
            };
        }
    }
    let mut lines: Vec<String> = Vec::new();
    if let Some(stdout) = child.stdout.take() {
        let mut reader = BufReader::new(stdout);
        let mut line = String::new();
        while lines.len() < 2 {
            line.clear();
            match reader.read_line(&mut line) {
                Ok(0) => break,
                Ok(_) => {
                    let text = line.trim().to_string();
                    if !text.is_empty() {
                        lines.push(text);
                    }
                }
                Err(why) => {
                    return Answer {
                        ok: false,
                        data: json!({
                            "why": format!("the editor's answer was not read: {}", why)
                        }),
                    }
                }
            }
        }
    }
    let _ = child.kill();
    let _ = child.wait();
    let elapsed = started.elapsed().as_millis();
    let answer = match lines.get(1) {
        Some(line) => line.clone(),
        None => {
            let mut why = format!(
                "the editor's server said nothing: it was asked and it did not answer ({} ms)",
                elapsed
            );
            if let Some(stderr) = child.stderr.take() {
                let mut text = String::new();
                let _ = BufReader::new(stderr).read_to_string(&mut text);
                if !text.trim().is_empty() {
                    why = format!("{}: {}", why, text.trim());
                }
            }
            return Answer {
                ok: false,
                data: json!({ "why": why, "command": command }),
            };
        }
    };
    let parsed: Value = match serde_json::from_str(&answer) {
        Ok(value) => value,
        Err(why) => {
            return Answer {
                ok: false,
                data: json!({
                    "why": format!("the editor's answer is not one record: {}", why),
                    "answer": answer,
                }),
            }
        }
    };
    let words = parsed
        .get("result")
        .and_then(|result| result.get("content"))
        .and_then(|content| content.as_array())
        .and_then(|content| content.first())
        .and_then(|first| first.get("text"))
        .and_then(|text| text.as_str())
        .unwrap_or("");
    let envelope: Value = match serde_json::from_str(words) {
        Ok(value) => value,
        Err(_) => json!({}),
    };
    let text = envelope
        .get("data")
        .and_then(|data| data.get("text"))
        .and_then(|text| text.as_str())
        .unwrap_or(words)
        .to_string();
    let refused = match envelope.get("refusal") {
        None | Some(Value::Null) => false,
        Some(Value::Array(list)) => !list.is_empty(),
        Some(Value::Object(map)) => !map.is_empty(),
        Some(Value::String(text)) => !text.is_empty(),
        Some(_) => true,
    };
    Answer {
        ok: !refused && !text.is_empty(),
        data: json!({
            "capability": capability,
            "text": text,
            "took-ms": elapsed,
        }),
    }
}
