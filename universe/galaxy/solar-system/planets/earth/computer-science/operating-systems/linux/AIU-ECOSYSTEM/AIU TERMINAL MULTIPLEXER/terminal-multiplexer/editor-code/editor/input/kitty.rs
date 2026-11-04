
pub const FLAG_DISAMBIGUATE: u8 = 1;

pub const FLAG_EVENT_TYPES: u8 = 2;

pub const FLAG_ALTERNATE_KEYS: u8 = 4;

pub const FLAG_ALL_KEYS: u8 = 8;

pub const MOD_SHIFT: u8 = 1;

pub const MOD_ALT: u8 = 2;

pub const MOD_CTRL: u8 = 4;

pub const MOD_SUPER: u8 = 8;

pub fn opt_in(flags: u8) -> String {
    format!("\x1b[={};1u", flags)
}

pub fn bits_of(number: u8) -> u8 {
    if number == 0 {
        0
    } else {
        number - 1
    }
}

pub fn prefix_of(bits: u8) -> String {
    let mut prefix = String::new();
    if bits & MOD_CTRL != 0 {
        prefix.push_str("C-");
    }
    if bits & MOD_ALT != 0 {
        prefix.push_str("M-");
    }
    if bits & MOD_SHIFT != 0 {
        prefix.push_str("S-");
    }
    prefix
}
