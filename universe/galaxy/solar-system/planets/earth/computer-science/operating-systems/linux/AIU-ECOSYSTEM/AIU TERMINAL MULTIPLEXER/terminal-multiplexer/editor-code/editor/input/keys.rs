
#[path = "kitty.rs"]
mod kitty;

pub struct Key {
    pub name: String,
    pub length: usize,
}

const NAMED_KEYS: [(&str, &str); 20] = [
    ("\x1b[A", "up"),
    ("\x1b[B", "down"),
    ("\x1b[C", "right"),
    ("\x1b[D", "left"),
    ("\x1b[H", "home"),
    ("\x1b[F", "end"),
    ("\x1b[1~", "home"),
    ("\x1b[2~", "insert"),
    ("\x1b[3~", "delete"),
    ("\x1b[4~", "end"),
    ("\x1b[5~", "pageup"),
    ("\x1b[6~", "pagedown"),
    ("\x1b[11~", "f1"),
    ("\x1b[12~", "f2"),
    ("\x1b[13~", "f3"),
    ("\x1b[14~", "f4"),
    ("\x1b[15~", "f5"),
    ("\x1b[17~", "f6"),
    ("\x1b[18~", "f7"),
    ("\x1b[19~", "f8"),
];

pub fn decode(bytes: &[u8]) -> Option<Key> {
    if bytes.is_empty() {
        return None;
    }
    for (sequence, name) in NAMED_KEYS.iter() {
        if bytes.starts_with(sequence.as_bytes()) {
            return Some(Key {
                name: name.to_string(),
                length: sequence.len(),
            });
        }
    }
    let first = bytes[0];
    if first == 0x1b {
        if bytes.len() == 1 {
            return Some(Key {
                name: "escape".to_string(),
                length: 1,
            });
        }
        return Some(Key {
            name: format!("M-{}", plain_name(bytes[1])),
            length: 2,
        });
    }
    if first == 0x09 {
        return Some(Key {
            name: "tab".to_string(),
            length: 1,
        });
    }
    if first == 0x0d || first == 0x0a {
        return Some(Key {
            name: "return".to_string(),
            length: 1,
        });
    }
    if first == 0x7f {
        return Some(Key {
            name: "backspace".to_string(),
            length: 1,
        });
    }
    if first == 0x20 {
        return Some(Key {
            name: "space".to_string(),
            length: 1,
        });
    }
    if first < 0x20 {
        return Some(Key {
            name: format!("C-{}", plain_name(first + 0x60)),
            length: 1,
        });
    }
    Some(Key {
        name: plain_name(first),
        length: 1,
    })
}

fn plain_name(byte: u8) -> String {
    match byte {
        b' ' => "space".to_string(),
        _ => (byte as char).to_string(),
    }
}

pub fn decode_csi(body: &str) -> Option<Key> {
    let mut parts = body.split(';');
    let code: u32 = parts.next()?.parse().ok()?;
    let modifiers: u8 = match parts.next() {
        Some(value) => value.parse().ok()?,
        None => 0,
    };
    let bits = kitty::bits_of(modifiers);
    let character = char::from_u32(code)?;
    Some(Key {
        name: format!("{}{}", kitty::prefix_of(bits), character),
        length: body.len() + 3,
    })
}

pub fn encode(name: &str) -> Option<Vec<u8>> {
    for (sequence, key) in NAMED_KEYS.iter() {
        if *key == name {
            return Some(sequence.as_bytes().to_vec());
        }
    }
    if name == "escape" {
        return Some(vec![0x1b]);
    }
    if name == "tab" {
        return Some(vec![0x09]);
    }
    if name == "return" {
        return Some(vec![0x0d]);
    }
    if name == "backspace" {
        return Some(vec![0x7f]);
    }
    if name == "space" {
        return Some(vec![0x20]);
    }
    if let Some(rest) = name.strip_prefix("C-") {
        let mut chars = rest.chars();
        if let (Some(letter), None) = (chars.next(), chars.next()) {
            if letter.is_ascii_lowercase() {
                return Some(vec![(letter as u8) - 0x60]);
            }
        }
    }
    if let Some(rest) = name.strip_prefix("M-") {
        let mut chars = rest.chars();
        if let (Some(letter), None) = (chars.next(), chars.next()) {
            if letter.is_ascii_lowercase() {
                return Some(vec![0x1b, letter as u8]);
            }
        }
    }
    let mut chars = name.chars();
    if let (Some(letter), None) = (chars.next(), chars.next()) {
        return Some(vec![letter as u8]);
    }
    None
}

pub use self::Key as DecodedKey;
