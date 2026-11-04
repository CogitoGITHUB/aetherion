
const SECRET_WORDS: [&str; 11] = [
    "api_key",
    "api-key",
    "apikey",
    "password",
    "passwd",
    "secret",
    "token",
    "authorization",
    "sk-",
    "bearer ",
    "-----begin",
];

const REDACTION: &str = "[redacted]";

pub fn carries_a_secret(text: &str) -> bool {
    text.split('\n')
        .any(|line| names_a_credential(line) && !line.trim_end().ends_with(REDACTION))
}

pub fn redact_text(text: &str) -> String {
    text.split('\n')
        .map(|line| {
            if names_a_credential(line) {
                hide_value(line)
            } else {
                line.to_string()
            }
        })
        .collect::<Vec<String>>()
        .join("\n")
}

fn names_a_credential(line: &str) -> bool {
    let lower = line.to_lowercase();
    SECRET_WORDS.iter().any(|word| lower.contains(word))
}

fn separator_at(line: &str) -> Option<usize> {
    let colon = line.find(':');
    let equals = line.find('=');
    match (colon, equals) {
        (None, None) => None,
        (Some(at), None) => Some(at),
        (None, Some(at)) => Some(at),
        (Some(one), Some(other)) => Some(if one < other { one } else { other }),
    }
}

fn hide_value(line: &str) -> String {
    match separator_at(line) {
        Some(at) => format!("{}[redacted]", &line[..at]),
        None => "[redacted]".to_string(),
    }
}

#[cfg(test)]
#[path = "redact_test/redact_test_behavior.rs"]
mod tests;
