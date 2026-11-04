use crate::*;

pub(crate) fn ok(id: Value, result: Value) -> Value {
    json!({ "jsonrpc": "2.0", "id": id, "result": result })
}

pub(crate) fn error(id: Value, code: i64, message: String) -> Value {
    json!({
        "jsonrpc": "2.0",
        "id": id,
        "error": { "code": code, "message": message }
    })
}

pub(crate) fn result(id: Value, text: String, is_error: bool) -> Value {
    json!({
        "jsonrpc": "2.0",
        "id": id,
        "result": {
            "content": [ { "type": "text", "text": text } ],
            "isError": is_error
        }
    })
}

pub(crate) fn write_answer(answer: &Value) -> Result<(), String> {
    let mut text = answer.to_string();
    text.push('\n');
    let stdout = std::io::stdout();
    let mut out = stdout.lock();
    out.write_all(text.as_bytes())
        .map_err(|why| format!("the answer cannot be written: {}", why))?;
    out.flush()
        .map_err(|why| format!("the answer cannot be flushed: {}", why))
}
