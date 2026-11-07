use std::io::Write;
use std::process::{Command, Stdio};

const ALPHABET: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

pub fn base64_encode(bytes: &[u8]) -> String {
    let mut out = String::new();
    for chunk in bytes.chunks(3) {
        let first = chunk[0] as u32;
        let second = if chunk.len() > 1 { chunk[1] as u32 } else { 0 };
        let third = if chunk.len() > 2 { chunk[2] as u32 } else { 0 };
        let joined = (first << 16) | (second << 8) | third;
        out.push(ALPHABET[((joined >> 18) & 63) as usize] as char);
        out.push(ALPHABET[((joined >> 12) & 63) as usize] as char);
        if chunk.len() > 1 {
            out.push(ALPHABET[((joined >> 6) & 63) as usize] as char);
        } else {
            out.push_str("=");
        }
        if chunk.len() > 2 {
            out.push(ALPHABET[(joined & 63) as usize] as char);
        } else {
            out.push_str("=");
        }
    }
    out
}

pub fn osc52_sequence(text: &str) -> String {
    format!(
        "{}]52;c;{}{}",
        char::from(27u8),
        base64_encode(text.as_bytes()),
        char::from(7u8)
    )
}

fn send_to_termux_clipboard(text: &str) {
    let Ok(mut child) = Command::new("termux-clipboard-set")
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
    else {
        return;
    };
    if let Some(mut input) = child.stdin.take() {
        let _ = input.write_all(text.as_bytes());
    }
}

pub fn copy_to_clipboard(text: &str) {
    let mut out = std::io::stdout();
    let _ = out.write_all(osc52_sequence(text).as_bytes());
    let _ = out.flush();
    send_to_termux_clipboard(text);
}

#[cfg(test)]
mod tests {
    use super::{base64_encode, osc52_sequence};

    #[test]
    fn base64_matches_known_values() {
        assert_eq!(base64_encode(b""), "");
        assert_eq!(base64_encode(b"a"), "YQ==");
        assert_eq!(base64_encode(b"ab"), "YWI=");
        assert_eq!(base64_encode(b"abc"), "YWJj");
        assert_eq!(base64_encode(b"hello"), "aGVsbG8=");
    }

    #[test]
    fn osc52_wraps_the_base64_text() {
        let sequence = osc52_sequence("hello");
        assert!(sequence.starts_with(char::from(27u8)));
        assert!(sequence.contains("]52;c;aGVsbG8="));
        assert!(sequence.ends_with(char::from(7u8)));
    }
}
