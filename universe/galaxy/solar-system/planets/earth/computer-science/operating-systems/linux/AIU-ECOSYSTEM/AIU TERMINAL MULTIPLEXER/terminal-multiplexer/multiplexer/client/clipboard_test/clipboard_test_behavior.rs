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
