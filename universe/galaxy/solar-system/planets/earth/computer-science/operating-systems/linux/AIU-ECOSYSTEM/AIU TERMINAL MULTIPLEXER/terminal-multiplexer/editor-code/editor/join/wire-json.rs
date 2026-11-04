
#[derive(Clone)]
enum Value {
    Text(String),
    Object(Vec<(String, Value)>),
}

pub struct Request {
    pub op: String,
    pub args: Vec<(String, String)>,
}

pub fn arg(request: &Request, name: &str) -> String {
    for (key, value) in &request.args {
        if key == name {
            return value.clone();
        }
    }
    String::new()
}

pub fn read_request(line: &str) -> Option<Request> {
    let members = parse_object(line)?;
    let op = text_of(&members, "op")?;
    let arguments = object_of(&members, "args")?;
    let mut args: Vec<(String, String)> = Vec::new();
    for (key, value) in &arguments {
        match value {
            Value::Text(text) => args.push((key.clone(), text.clone())),
            _ => return None,
        }
    }
    Some(Request { op, args })
}

pub fn write_response(ok: bool, data: &[(String, String)]) -> String {
    let mut out = String::from("{\"ok\":");
    out.push_str(if ok { "true" } else { "false" });
    out.push_str(",\"data\":{");
    let mut first = true;
    for (key, value) in data {
        if !first {
            out.push(',');
        }
        first = false;
        out.push('"');
        out.push_str(&escape(key));
        out.push_str("\":\"");
        out.push_str(&escape(value));
        out.push('"');
    }
    out.push_str("}}");
    out
}

fn text_of(members: &[(String, Value)], name: &str) -> Option<String> {
    for (key, value) in members {
        if key == name {
            if let Value::Text(text) = value {
                return Some(text.clone());
            }
            return None;
        }
    }
    None
}

fn object_of(members: &[(String, Value)], name: &str) -> Option<Vec<(String, Value)>> {
    for (key, value) in members {
        if key == name {
            if let Value::Object(inner) = value {
                return Some(inner.clone());
            }
            return None;
        }
    }
    None
}

fn parse_object(line: &str) -> Option<Vec<(String, Value)>> {
    let mut at = 0usize;
    match parse_value(line, &mut at)? {
        Value::Object(members) => Some(members),
        _ => None,
    }
}

fn parse_value(text: &str, at: &mut usize) -> Option<Value> {
    skip_spaces(text, at);
    let byte = *text.as_bytes().get(*at)?;
    if byte == b'"' {
        return Some(Value::Text(parse_string(text, at)?));
    }
    if byte == b'{' {
        *at += 1;
        let mut members: Vec<(String, Value)> = Vec::new();
        loop {
            skip_spaces(text, at);
            let byte = *text.as_bytes().get(*at)?;
            if byte == b'}' {
                *at += 1;
                return Some(Value::Object(members));
            }
            if byte == b',' {
                *at += 1;
                continue;
            }
            let key = parse_string(text, at)?;
            skip_spaces(text, at);
            if *text.as_bytes().get(*at)? != b':' {
                return None;
            }
            *at += 1;
            let value = parse_value(text, at)?;
            members.push((key, value));
        }
    }
    None
}

fn parse_string(text: &str, at: &mut usize) -> Option<String> {
    let bytes = text.as_bytes();
    if bytes.get(*at) != Some(&b'"') {
        return None;
    }
    *at += 1;
    let mut out = String::new();
    while *at < bytes.len() {
        let byte = bytes[*at];
        if byte == b'"' {
            *at += 1;
            return Some(out);
        }
        if byte == b'\\' {
            *at += 1;
            let escaped = *bytes.get(*at)?;
            *at += 1;
            match escaped {
                b'n' => out.push('\n'),
                b't' => out.push('\t'),
                b'r' => out.push('\r'),
                b'"' => out.push('"'),
                b'\\' => out.push('\\'),
                b'/' => out.push('/'),
                other => {
                    out.push('\\');
                    out.push(other as char);
                }
            }
            continue;
        }
        let rest = &text[*at..];
        let character = rest.chars().next()?;
        out.push(character);
        *at += character.len_utf8();
    }
    None
}

/// skip_spaces moves the cursor past the spaces.
fn skip_spaces(text: &str, at: &mut usize) {
    while let Some(byte) = text.as_bytes().get(*at) {
        if *byte == b' ' || *byte == b'\n' || *byte == b'\t' || *byte == b'\r' {
            *at += 1;
        } else {
            return;
        }
    }
}

fn escape(text: &str) -> String {
    let mut out = String::new();
    for c in text.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\t' => out.push_str("\\t"),
            '\r' => out.push_str("\\r"),
            _ => out.push(c),
        }
    }
    out
}
