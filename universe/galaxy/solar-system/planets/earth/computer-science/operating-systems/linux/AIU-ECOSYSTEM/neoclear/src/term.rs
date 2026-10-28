// neoclear — clear the terminal with converging streams of braille glyphs
// Copyright (C) 2026 Fabian Transchel
// SPDX-License-Identifier: GPL-3.0-or-later

//! Minimal, dependency-free terminal plumbing for Linux: tty detection,
//! window size, echo suppression and signal handling via libc FFI.

use std::os::raw::{c_int, c_ulong, c_ushort};
use std::sync::atomic::{AtomicBool, Ordering};

static INTERRUPTED: AtomicBool = AtomicBool::new(false);

extern "C" {
    fn isatty(fd: c_int) -> c_int;
    fn ioctl(fd: c_int, request: c_ulong, ...) -> c_int;
    fn signal(signum: c_int, handler: usize) -> usize;
    fn tcgetattr(fd: c_int, termios: *mut Termios) -> c_int;
    fn tcsetattr(fd: c_int, action: c_int, termios: *const Termios) -> c_int;
}

#[repr(C)]
#[derive(Default)]
struct WinSize {
    rows: c_ushort,
    cols: c_ushort,
    xpixel: c_ushort,
    ypixel: c_ushort,
}

#[cfg(not(any(
    target_arch = "powerpc",
    target_arch = "powerpc64",
    target_arch = "mips",
    target_arch = "mips64",
    target_arch = "sparc",
    target_arch = "sparc64"
)))]
const TIOCGWINSZ: c_ulong = 0x5413;
#[cfg(any(
    target_arch = "powerpc",
    target_arch = "powerpc64",
    target_arch = "mips",
    target_arch = "mips64",
    target_arch = "sparc",
    target_arch = "sparc64"
))]
const TIOCGWINSZ: c_ulong = 0x4008_7468;

// `struct termios` varies slightly between Linux architectures (the size of
// c_cc), but c_lflag is always the fourth u32. We only touch c_lflag, so an
// oversized, aligned buffer is enough.
#[repr(C, align(8))]
#[derive(Clone, Copy)]
struct Termios([u8; 256]);

const LFLAG_OFFSET: usize = 12;
const ECHO: u32 = 0x8;
const TCSANOW: c_int = 0;
const SIGHUP: c_int = 1;
const SIGINT: c_int = 2;
const SIGTERM: c_int = 15;

/// True once SIGINT/SIGTERM/SIGHUP arrived.
pub fn interrupted() -> bool {
    INTERRUPTED.load(Ordering::Relaxed)
}

pub fn stdout_is_tty() -> bool {
    unsafe { isatty(1) == 1 }
}

/// Terminal size as (columns, rows).
pub fn size() -> Option<(usize, usize)> {
    for fd in [1, 2, 0] {
        let mut ws = WinSize::default();
        if unsafe { ioctl(fd, TIOCGWINSZ, &mut ws as *mut WinSize) } == 0 && ws.cols > 0 && ws.rows > 0 {
            return Some((ws.cols as usize, ws.rows as usize));
        }
    }
    let c = std::env::var("COLUMNS").ok()?.trim().parse().ok()?;
    let l = std::env::var("LINES").ok()?.trim().parse().ok()?;
    Some((c, l))
}

extern "C" fn on_signal(_: c_int) {
    INTERRUPTED.store(true, Ordering::Relaxed);
}

/// Installs signal handlers and turns off input echo (so keys pressed
/// during the animation don't scribble over it). Restores echo on drop.
pub struct Guard {
    saved: Option<Termios>,
}

impl Guard {
    pub fn new() -> Self {
        unsafe {
            for sig in [SIGHUP, SIGINT, SIGTERM] {
                signal(sig, on_signal as extern "C" fn(c_int) as usize);
            }
        }
        Guard { saved: disable_echo() }
    }
}

impl Drop for Guard {
    fn drop(&mut self) {
        if let Some(t) = &self.saved {
            unsafe {
                tcsetattr(0, TCSANOW, t);
            }
        }
    }
}

fn disable_echo() -> Option<Termios> {
    unsafe {
        if isatty(0) != 1 {
            return None;
        }
        let mut t = Termios([0; 256]);
        if tcgetattr(0, &mut t) != 0 {
            return None;
        }
        let saved = t;
        let field = &mut t.0[LFLAG_OFFSET..LFLAG_OFFSET + 4];
        let v = u32::from_ne_bytes(field.try_into().ok()?) & !ECHO;
        field.copy_from_slice(&v.to_ne_bytes());
        if tcsetattr(0, TCSANOW, &t) != 0 {
            return None;
        }
        Some(saved)
    }
}
