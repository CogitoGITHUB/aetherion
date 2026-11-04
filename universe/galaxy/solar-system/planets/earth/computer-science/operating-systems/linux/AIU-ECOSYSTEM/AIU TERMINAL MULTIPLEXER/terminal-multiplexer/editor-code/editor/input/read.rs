
#[path = "keys.rs"]
mod keys;

use std::io::Read;

pub struct Reader {
    buffer: Vec<u8>,
    at: usize,
}

pub fn new_reader() -> Reader {
    Reader {
        buffer: Vec::new(),
        at: 0,
    }
}

pub fn push(reader: &mut Reader, bytes: &[u8]) {
    reader.buffer.extend_from_slice(bytes);
}

pub fn next_key(reader: &mut Reader) -> Option<keys::Key> {
    let waiting: Vec<u8> = reader.buffer[reader.at..].to_vec();
    let key = keys::decode(&waiting)?;
    reader.at += key.length;
    if reader.at >= reader.buffer.len() {
        reader.buffer.clear();
        reader.at = 0;
    }
    Some(key)
}

pub fn pending(reader: &Reader) -> usize {
    reader.buffer.len() - reader.at
}

pub fn read_more(reader: &mut Reader, source: &mut dyn Read) -> usize {
    let mut chunk = [0u8; 64];
    match source.read(&mut chunk) {
        Ok(count) => {
            push(reader, &chunk[..count]);
            count
        }
        Err(_) => 0,
    }
}

pub fn from_hex(text: &str) -> Vec<u8> {
    let digits: Vec<char> = text.chars().filter(|c| c.is_ascii_hexdigit()).collect();
    let mut bytes = Vec::new();
    let mut at = 0usize;
    while at + 1 < digits.len() {
        let pair = format!("{}{}", digits[at], digits[at + 1]);
        bytes.push(u8::from_str_radix(&pair, 16).unwrap_or(0));
        at += 2;
    }
    bytes
}

pub fn to_hex(bytes: &[u8]) -> String {
    let mut out = String::new();
    for byte in bytes {
        out.push_str(&format!("{:02x}", byte));
    }
    out
}

pub fn encode_name(name: &str) -> Option<Vec<u8>> {
    keys::encode(name)
}

pub use self::keys::Key;
pub use self::keys::decode;
pub use self::Reader as KeyReader;
