
use std::process::Command;

pub const OSC_LIMIT: usize = 8192;

const OSC_PREFIX: &str = "\x1b]52;c;";

const OSC_END: &str = "\x07";

pub const ADDON: &str = "com.termux.api";

pub const PASTE_MAX: usize = 65536;

pub fn base64(data: &[u8]) -> String {
    const ALPHABET: &[u8; 64] =
        b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut text = String::with_capacity(data.len().div_ceil(3) * 4);
    for piece in data.chunks(3) {
        let a = piece[0] as u32;
        let b = piece.get(1).copied().unwrap_or(0) as u32;
        let c = piece.get(2).copied().unwrap_or(0) as u32;
        let word = (a << 16) | (b << 8) | c;
        text.push(ALPHABET[((word >> 18) & 63) as usize] as char);
        text.push(ALPHABET[((word >> 12) & 63) as usize] as char);
        if piece.len() > 1 {
            text.push(ALPHABET[((word >> 6) & 63) as usize] as char);
        } else {
            text.push('=');
        }
        if piece.len() > 2 {
            text.push(ALPHABET[(word & 63) as usize] as char);
        } else {
            text.push('=');
        }
    }
    text
}

pub fn out(text: &str) -> Result<Vec<u8>, String> {
    let payload = base64(text.as_bytes());
    let total = OSC_PREFIX.len() + payload.len() + OSC_END.len();
    if total > OSC_LIMIT {
        let most = (OSC_LIMIT - OSC_PREFIX.len() - OSC_END.len()) / 4 * 3;
        return Err(format!(
            "the copy is not on the Android clipboard: one OSC 52 string carries {} \
             characters at most and this one is {}, so pick less text (at most {} bytes)",
            OSC_LIMIT, total, most
        ));
    }
    if text.is_empty() {
        return Err("the copy is not on the Android clipboard: there is no text to put there"
            .to_string());
    }
    if text.contains('\x07') || text.contains('\x1b') {
        return Err(
            "the copy is not on the Android clipboard: the text holds an escape or a bell, \
             and the emulator would read it as the end of the string"
                .to_string(),
        );
    }
    let mut bytes: Vec<u8> = Vec::with_capacity(total);
    bytes.extend_from_slice(OSC_PREFIX.as_bytes());
    bytes.extend_from_slice(payload.as_bytes());
    bytes.extend_from_slice(OSC_END.as_bytes());
    Ok(bytes)
}

pub fn addon() -> Result<bool, String> {
    let listed = Command::new("pm")
        .args(["list", "packages", ADDON])
        .output();
    let answer = match listed {
        Ok(found) => found,
        Err(why) => {
            return Err(format!(
                "the Android clipboard cannot be read: the phone's package list cannot be \
                 asked (pm: {}), so the Termux:API add-on cannot be checked",
                why
            ))
        }
    };
    let wanted = format!("package:{}", ADDON);
    let said = String::from_utf8_lossy(&answer.stdout);
    Ok(said.lines().any(|line| line.trim() == wanted))
}

pub fn paste() -> Result<String, String> {
    if !addon()? {
        return Err(format!(
            "{} is not installed, so the Android clipboard cannot be read: \
             termux-clipboard-get waits for ever without it",
            ADDON
        ));
    }
    let read = Command::new("termux-clipboard-get").output();
    let answer = match read {
        Ok(found) => found,
        Err(why) => {
            return Err(format!(
                "the Android clipboard cannot be read: termux-clipboard-get could not be run \
                 ({})",
                why
            ))
        }
    };
    if !answer.status.success() {
        return Err(format!(
            "the Android clipboard cannot be read: termux-clipboard-get ended with {}",
            answer.status
        ));
    }
    Ok(String::from_utf8_lossy(&answer.stdout).to_string())
}

pub fn fits(text: &str) -> Result<(), String> {
    if text.len() > PASTE_MAX {
        return Err(format!(
            "the paste is not sent: the Android clipboard holds {} bytes and one paste carries \
             {} at most, so copy less of it",
            text.len(),
            PASTE_MAX
        ));
    }
    Ok(())
}

#[cfg(test)]
#[path = "clipboard_test/clipboard_test_behavior.rs"]
mod tests;
