#![allow(dead_code)]

use libc::{c_int, termios, winsize};

pub fn make_raw(fd: c_int) -> Result<(), String> {
    let mut settings = termios_here(fd)?;
    unsafe {
        libc::cfmakeraw(&mut settings);
    }
    set_termios(fd, &settings)
}

pub fn is_raw(fd: c_int) -> bool {
    match termios_here(fd) {
        Ok(settings) => {
            let flags = settings.c_lflag;
            (flags & (libc::ICANON | libc::ECHO)) == 0
        }
        Err(_) => false,
    }
}

pub fn window_size(fd: c_int) -> Option<(u16, u16)> {
    let mut size = winsize {
        ws_row: 0,
        ws_col: 0,
        ws_xpixel: 0,
        ws_ypixel: 0,
    };
    let answer = unsafe { libc::ioctl(fd, libc::TIOCGWINSZ, &mut size) };
    if answer == 0 {
        Some((size.ws_col, size.ws_row))
    } else {
        None
    }
}

pub fn set_window_size(fd: c_int, cols: u16, rows: u16) -> Result<(), String> {
    let size = winsize {
        ws_row: rows,
        ws_col: cols,
        ws_xpixel: 0,
        ws_ypixel: 0,
    };
    let answer = unsafe { libc::ioctl(fd, libc::TIOCSWINSZ, &size) };
    if answer == 0 {
        Ok(())
    } else {
        Err(format!("the terminal refused a size of {}x{}", cols, rows))
    }
}

pub fn save_termios(fd: c_int) -> Result<termios, String> {
    termios_here(fd)
}

pub fn restore_termios(fd: c_int, settings: &termios) -> Result<(), String> {
    set_termios(fd, settings)
}

pub fn escape_len(bytes: &[u8], at: usize) -> usize {
    let first = match bytes.get(at) {
        Some(byte) => *byte,
        None => return 0,
    };
    if first != 0x1b {
        return 0;
    }
    let second = match bytes.get(at + 1) {
        Some(byte) => *byte,
        None => return 1,
    };
    match second {
        b'[' => {
            let mut i = at + 2;
            while i < bytes.len() {
                let byte = bytes[i];
                if (0x40..=0x7e).contains(&byte) {
                    return i - at + 1;
                }
                i += 1;
            }
            bytes.len() - at
        }
        b']' => {
            let mut i = at + 2;
            while i < bytes.len() {
                if bytes[i] == 0x07 {
                    return i - at + 1;
                }
                if bytes[i] == 0x1b && bytes.get(i + 1) == Some(&b'\\') {
                    return i - at + 2;
                }
                i += 1;
            }
            bytes.len() - at
        }
        _ => 2,
    }
}

pub fn plain(bytes: &[u8]) -> String {
    let mut kept: Vec<u8> = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        let span = escape_len(bytes, i);
        if span > 0 {
            i += span;
        } else {
            kept.push(bytes[i]);
            i += 1;
        }
    }
    String::from_utf8_lossy(&kept).to_string()
}

fn termios_here(fd: c_int) -> Result<termios, String> {
    let mut settings = std::mem::MaybeUninit::<termios>::zeroed();
    let answer = unsafe { libc::tcgetattr(fd, settings.as_mut_ptr()) };
    if answer == 0 {
        Ok(unsafe { settings.assume_init() })
    } else {
        Err(format!("tcgetattr refused on fd {}", fd))
    }
}

fn set_termios(fd: c_int, settings: &termios) -> Result<(), String> {
    let answer = unsafe { libc::tcsetattr(fd, libc::TCSAFLUSH, settings) };
    if answer == 0 {
        Ok(())
    } else {
        Err(format!("tcsetattr refused on fd {}", fd))
    }
}
