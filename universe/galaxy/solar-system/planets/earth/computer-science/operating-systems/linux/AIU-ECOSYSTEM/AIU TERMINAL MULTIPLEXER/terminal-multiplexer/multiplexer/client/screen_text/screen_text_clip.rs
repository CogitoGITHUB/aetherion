use super::*;

pub(crate) fn line_holds(line: &str, what: &str) -> bool {
    match serde_json::from_str::<Value>(line) {
        Ok(value) => value.get("what").and_then(|part| part.as_str()) == Some(what),
        Err(_) => false,
    }
}

pub fn agent_name(program: &str) -> String {
    program
        .rsplit('/')
        .next()
        .filter(|name| !name.is_empty())
        .unwrap_or(program)
        .to_string()
}

pub(crate) fn clip(text: &str, width: usize) -> String {
    let mut out = String::new();
    let mut count = 0;
    let mut characters = text.chars().peekable();
    while let Some(character) = characters.next() {
        if character == '\x1b' {
            out.push(character);
            for next in characters.by_ref() {
                out.push(next);
                if next.is_ascii_alphabetic() {
                    break;
                }
            }
            continue;
        }
        if count >= width {
            break;
        }
        out.push(character);
        count += 1;
    }
    out
}

pub(crate) fn first_line(text: &str) -> String {
    text.lines().next().unwrap_or("").to_string()
}

pub(crate) fn put(out: &mut String, row: u16, left: u16, text: &str) {
    out.push_str(&format!("\x1b[{};{}H", row, left));
    out.push_str(text);
    out.push_str("\x1b[K");
}

