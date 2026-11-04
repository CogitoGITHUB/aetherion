use super::*;

/// line_holds answers whether a record on the wire says a thing.
pub(crate) fn line_holds(line: &str, what: &str) -> bool {
    match serde_json::from_str::<Value>(line) {
        Ok(value) => value.get("what").and_then(|part| part.as_str()) == Some(what),
        Err(_) => false,
    }
}

/// agent_name answers the name of the agent program: the last piece of its
/// path. The target of a bundle is named, never inferred.
pub fn agent_name(program: &str) -> String {
    program
        .rsplit('/')
        .next()
        .filter(|name| !name.is_empty())
        .unwrap_or(program)
        .to_string()
}

/// clip answers the text with no more than width characters, and no more
/// than one line.
pub(crate) fn clip(text: &str, width: usize) -> String {
    // The escape sequences take no room on the screen, so they are not
    // counted, and they are never cut in half.
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

/// first_line answers the first line of a text, for a message that names
/// what was copied.
pub(crate) fn first_line(text: &str) -> String {
    text.lines().next().unwrap_or("").to_string()
}

/// put answers the escape sequence that puts one line of text at one place
/// on the terminal.
pub(crate) fn put(out: &mut String, row: u16, left: u16, text: &str) {
    out.push_str(&format!("\x1b[{};{}H", row, left));
    out.push_str(text);
    out.push_str("\x1b[K");
}

