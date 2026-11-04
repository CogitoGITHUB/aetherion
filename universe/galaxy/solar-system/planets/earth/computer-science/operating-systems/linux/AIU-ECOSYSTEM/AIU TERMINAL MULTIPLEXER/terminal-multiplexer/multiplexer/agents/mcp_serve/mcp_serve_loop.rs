use crate::*;

pub(crate) fn sessions_dir(args: &[String]) -> Result<PathBuf, String> {
    let at = 0;
    while at < args.len() {
        match args[at].as_str() {
            "--sessions-dir" => {
                let value = args
                    .get(at + 1)
                    .cloned()
                    .ok_or("--sessions-dir needs a value")?;
                return Ok(PathBuf::from(value));
            }
            "--help" => {
                println!("mux-mcp --sessions-dir DIR");
                std::process::exit(envelope::EXIT_OK);
            }
            other => return Err(format!("{} is not an option this server knows", other)),
        }
    }
    Err("the server needs --sessions-dir".to_string())
}

pub(crate) fn serve(sessions_dir: &PathBuf) -> i32 {
    let stdin = std::io::stdin();
    let mut reader = stdin.lock();
    let mut refused = false;
    let mut line = String::new();
    loop {
        line.clear();
        let got = match reader.read_line(&mut line) {
            Ok(count) => count,
            Err(_) => return envelope::EXIT_CANNOT_RUN,
        };
        if got == 0 {
            break;
        }
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }
        let request: Value = match serde_json::from_str(trimmed) {
            Ok(value) => value,
            Err(why) => {
                let answer = json!({
                    "jsonrpc": "2.0",
                    "id": Value::Null,
                    "error": { "code": -32700, "message": format!("the request is not JSON: {}", why) }
                });
                if write_answer(&answer).is_err() {
                    return envelope::EXIT_CANNOT_RUN;
                }
                continue;
            }
        };
        let mut is_refusal = false;
        match handle(&request, sessions_dir) {
            Some(answer) => {
                if answer.get("result").is_some() {
                    if let Some(text) = answer
                        .get("result")
                        .and_then(|r| r.get("content"))
                        .and_then(|c| c.get(0))
                        .and_then(|c| c.get("text"))
                        .and_then(|t| t.as_str())
                    {
                        if text.contains("\"ok\":false") {
                            is_refusal = true;
                        }
                    }
                }
                if write_answer(&answer).is_err() {
                    return envelope::EXIT_CANNOT_RUN;
                }
            }
            None => {}
        }
        if is_refusal {
            refused = true;
        }
    }
    if refused {
        envelope::EXIT_REFUSAL
    } else {
        envelope::EXIT_OK
    }
}

pub(crate) fn handle(request: &Value, sessions_dir: &PathBuf) -> Option<Value> {
    let id = request.get("id").cloned();
    let method = request
        .get("method")
        .and_then(|value| value.as_str())
        .unwrap_or("")
        .to_string();

    if id.is_none() {
        return None;
    }
    let id = id.unwrap();

    match method.as_str() {
        "initialize" => Some(ok(id, json!({
            "protocolVersion": PROTOCOL_VERSION,
            "capabilities": { "tools": {} },
            "serverInfo": { "name": envelope::PROGRAM, "version": envelope::VERSION }
        }))),
        "ping" => Some(ok(id, json!({}))),
        "tools/list" => {
            let mut list: Vec<Value> = Vec::new();
            for cap in tools::capabilities() {
                list.push(json!({
                    "name": cap.name,
                    "description": cap.description,
                    "inputSchema": tools::schema(&cap)
                }));
            }
            Some(ok(id, json!({ "tools": Value::Array(list) })))
        }
        "tools/call" => {
            let params = request.get("params").cloned().unwrap_or(json!({}));
            let name = params
                .get("name")
                .and_then(|value| value.as_str())
                .unwrap_or("")
                .to_string();
            let arguments = params
                .get("arguments")
                .cloned()
                .unwrap_or(json!({}));
            Some(call(id, &name, &arguments, sessions_dir))
        }
        other => Some(error(id, -32601, format!("there is no method named {}", other))),
    }
}

