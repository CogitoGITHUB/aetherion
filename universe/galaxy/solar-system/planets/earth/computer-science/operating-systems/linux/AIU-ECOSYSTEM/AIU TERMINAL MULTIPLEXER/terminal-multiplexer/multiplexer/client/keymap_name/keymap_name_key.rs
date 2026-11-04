use super::*;

/// key_name answers the name of one byte, the way the explorer shows it.
pub fn key_name(byte: u8) -> String {
    match byte {
        0x1b => "Escape".to_string(),
        0x0d => "Enter".to_string(),
        0x7f => "Backspace".to_string(),
        0x20 => "Space".to_string(),
        byte if byte.is_ascii_graphic() => (byte as char).to_string(),
        byte => format!("Ctrl-{}", (byte + 0x60) as char),
    }
}

