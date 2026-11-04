// One job: the Android clipboard — the pick out to it, and its text in.
//
// Measured on this phone on 2026-10-23, and written down in the README under
// "The Android clipboard on this phone":
//
//   - OSC 52 works, and it only writes. Termux's own emulator hands the
//     base64 payload to ClipboardManager.setPrimaryClip, so the text lands in
//     the ANDROID clipboard and not only in the terminal's buffer. One OSC
//     string of at most 8192 characters, and a longer one is dropped without a
//     word; the emulator does not answer the read query.
//   - The read direction has one route, the Termux:API add-on. Without that
//     app the termux-clipboard-get script waits for ever (measured: exit 124
//     under a 15 s bound, then under a 5 s bound), so this file NEVER runs the
//     script before the phone's package list says the app is there. The gate
//     is the package list, and no timer is needed, because the gate answers by
//     itself.
//
// Nothing here guesses what the phone can do: every answer is a value, and a
// refusal names the thing that is missing.

use std::process::Command;

/// OSC_LIMIT is the longest OSC string the emulator takes, as measured: one
/// string of 8192 characters. A longer one is dropped silently, so a copy
/// that would not fit is refused here, by name.
pub const OSC_LIMIT: usize = 8192;

/// OSC_PREFIX opens the OSC 52 sequence: clipboard, the selection 'c', then
/// the base64 payload.
const OSC_PREFIX: &str = "\x1b]52;c;";

/// OSC_END ends an OSC string. The bell is the ending every emulator takes.
const OSC_END: &str = "\x07";

/// ADDON is the Termux:API add-on app: the app every termux-* clipboard
/// script answers through, and the app this phone does not have.
pub const ADDON: &str = "com.termux.api";

/// PASTE_MAX is how much clipboard text one paste carries. A larger text is
/// refused by name rather than cut: a paste that silently loses its end is a
/// paste the owner would act on wrongly.
pub const PASTE_MAX: usize = 65536;

/// base64 encodes bytes the standard way, padding included: the alphabet the
/// emulator takes.
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

/// out answers the bytes that put the text on the Android clipboard, or the
/// reason it was not put there.
///
/// The bytes go to the owner's own terminal, never to a pane: the pane's
/// program would print them, and the clipboard would never see them. A text
/// over the limit is refused with both numbers said, because the emulator's
/// own answer to an over-long string is silence.
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

/// addon answers whether the Termux:API add-on is installed. The package list
/// answers by itself, so this is the gate the read direction passes through:
/// the script is never run on a phone that would leave it waiting.
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

/// paste answers the Android clipboard's text, or the reason it could not be
/// read. The add-on is checked first: without it the script waits for ever,
/// so it is never run.
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

/// fits answers whether the clipboard text can go to a pane in one paste, or
/// the reason it cannot.
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
mod tests {
    use super::*;

    /// the_rfc_vectors are the examples of RFC 4648: an encoder that agrees
    /// with them is an encoder that agrees with every emulator.
    #[test]
    fn base64_agrees_with_the_standard_examples() {
        assert_eq!(base64(b""), "");
        assert_eq!(base64(b"f"), "Zg==");
        assert_eq!(base64(b"fo"), "Zm8=");
        assert_eq!(base64(b"foo"), "Zm9v");
        assert_eq!(base64(b"foob"), "Zm9vYg==");
        assert_eq!(base64(b"fooba"), "Zm9vYmE=");
        assert_eq!(base64(b"foobar"), "Zm9vYmFy");
    }

    #[test]
    fn base64_takes_the_bytes_of_a_multibyte_line() {
        // The phone writes UTF-8, and the payload is bytes, not characters:
        // three bytes make four characters with no padding.
        assert_eq!(base64("é".as_bytes()), "w6k=");
        assert_eq!(base64("δ".as_bytes()), "zrQ=");
    }

    #[test]
    fn out_is_one_osc_52_string_that_ends_in_the_bell() {
        let bytes = out("the region").unwrap();
        let said = String::from_utf8(bytes).unwrap();
        assert!(said.starts_with("\x1b]52;c;"), "the prefix: {:?}", said);
        assert!(said.ends_with('\x07'), "the ending: {:?}", said);
        assert!(said.contains(&base64(b"the region")), "the payload: {:?}", said);
        assert!(!said.contains('\n'), "one string, no newline: {:?}", said);
    }

    #[test]
    fn a_text_over_the_limit_is_refused_with_both_numbers() {
        let text = "x".repeat(OSC_LIMIT);
        let why = out(&text).unwrap_err();
        assert!(why.contains("8192"), "the limit is said: {:?}", why);
        assert!(why.contains("bytes"), "the size is said: {:?}", why);
    }

    #[test]
    fn a_text_that_just_fits_is_taken() {
        // 6132 bytes of text make 8176 base64 characters, 8184 with the
        // prefix and the bell: the last size the string takes.
        let text = "x".repeat(6132);
        let said = String::from_utf8(out(&text).unwrap()).unwrap();
        assert_eq!(said.len(), OSC_LIMIT - 8);
    }

    #[test]
    fn an_escape_in_the_text_is_refused_and_named() {
        let why = out("one \x1b two").unwrap_err();
        assert!(why.contains("escape"), "the reason is named: {:?}", why);
    }

    #[test]
    fn an_empty_text_is_refused_and_named() {
        let why = out("").unwrap_err();
        assert!(why.contains("no text"), "the reason is named: {:?}", why);
    }

    #[test]
    fn a_paste_over_the_limit_is_refused_with_both_numbers() {
        let text = "x".repeat(PASTE_MAX + 1);
        let why = fits(&text).unwrap_err();
        assert!(why.contains("65536"), "the limit is said: {:?}", why);
        assert!(fits(&"x".repeat(PASTE_MAX)).is_ok(), "the limit itself is taken");
    }
}
