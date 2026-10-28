// neoclear — clear the terminal with converging streams of braille glyphs
// Copyright (C) 2026 Fabian Transchel
// SPDX-License-Identifier: GPL-3.0-or-later

//! The screen is partitioned between the enabled edges: every cell belongs to
//! the edge it is (proportionally) closest to, so one edge sweeps the whole
//! screen, two opposite edges meet on the centre line, and all four meet in an
//! X. Each column (or row) gets one stream with its own speed and start delay;
//! all streams are timed to arrive within `duration_ms`. Once every stream has
//! arrived the whole field fades to black and the terminal is cleared.

#[cfg(not(target_os = "linux"))]
compile_error!("neoclear supports Linux only");

mod config;
mod term;

use config::{Action, ColorMode, Config, Dir, Rgb};
use std::fmt::Write as _;
use std::io::Write;
use std::time::{Duration, Instant};

const NONE: u32 = u32::MAX;

fn main() {
    let (action, warnings) = match config::from_args() {
        Ok(x) => x,
        Err(e) => {
            eprintln!("neoclear: {e}\nTry 'neoclear --help'.");
            std::process::exit(2);
        }
    };
    for w in &warnings {
        eprintln!("neoclear: warning: {w}");
    }
    match action {
        Action::Help => print!("{}", config::HELP),
        Action::Version => println!("neoclear {}", env!("CARGO_PKG_VERSION")),
        Action::PrintConfig(cfg) => print!("{}", cfg.to_toml()),
        Action::ShowPath(p) => match p {
            Some(p) => println!("{}", p.display()),
            None => println!("(no config file)"),
        },
        Action::WriteConfig(cfg, path) => {
            if let Some(dir) = path.parent() {
                let _ = std::fs::create_dir_all(dir);
            }
            match std::fs::write(&path, cfg.to_toml()) {
                Ok(()) => println!("wrote {}", path.display()),
                Err(e) => {
                    eprintln!("neoclear: cannot write {}: {e}", path.display());
                    std::process::exit(1);
                }
            }
        }
        Action::Run { cfg, size } => run(&cfg, size),
    }
}

fn final_clear(cfg: &Config) -> String {
    let mut s = String::from("\x1b[0m\x1b[H\x1b[2J");
    if cfg.clear_scrollback {
        s.push_str("\x1b[3J");
    }
    s
}

fn run(cfg: &Config, forced: Option<(usize, usize)>) {
    let mut out = std::io::stdout().lock();
    let size = forced.or_else(|| if term::stdout_is_tty() { term::size() } else { None });
    let Some((w, h)) = size.filter(|&(w, h)| w > 0 && h > 0) else {
        // Not a terminal (or unknown size): behave like plain `clear`.
        let _ = out.write_all(final_clear(cfg).as_bytes());
        let _ = out.flush();
        return;
    };

    let guard = term::Guard::new();
    let truecolor = match cfg.color_mode {
        ColorMode::TrueColor => true,
        ColorMode::Ansi256 => false,
        ColorMode::Auto => detect_truecolor(),
    };
    let mut anim = Anim::new(cfg, w, h, truecolor);

    // Hide the cursor, disable auto-wrap, reset attributes. Each frame saves
    // the cursor position (DECSC) and ends by restoring it (DECRC) inside its
    // synchronized update, so the terminal only ever renders the cursor where
    // it started; drawing jumps around invisibly in between. (Saving per frame
    // also works on terminals that treat DECSC/DECRC as a one-shot stack.) This keeps cursor shaders/trails (Ghostty etc.) still until the
    // single move to the top-left in the final clear.
    let _ = out.write_all(b"\x1b[?25l\x1b[?7l\x1b[0m");
    let start = Instant::now();
    let dt = Duration::from_secs_f64(1.0 / cfg.fps as f64);
    let mut buf = String::with_capacity(w * h * 24);
    let mut frame: u32 = 0;
    loop {
        if term::interrupted() || (forced.is_none() && term::size() != Some((w, h))) {
            break; // Ctrl-C or resize: skip straight to the clear
        }
        let t = start.elapsed().as_secs_f32();
        buf.clear();
        buf.push_str("\x1b[?2026h\x1b7"); // begin synchronized update, save cursor
        let empty = buf.len();
        let finished = anim.render(t, &mut buf);
        if buf.len() > empty {
            buf.push_str("\x1b8\x1b[?2026l"); // cursor back to where it started, then present
            if out.write_all(buf.as_bytes()).and_then(|_| out.flush()).is_err() {
                break;
            }
        }
        if finished {
            break;
        }
        frame += 1;
        let next = start + dt * frame;
        let now = Instant::now();
        if next > now {
            std::thread::sleep(next - now);
        }
    }
    // the one and only visible cursor move: clear, home, show cursor
    let _ = out.write_all(format!("\x1b[?2026h{}\x1b[?7h\x1b[?25h\x1b[?2026l", final_clear(cfg)).as_bytes());
    let _ = out.flush();
    drop(guard);
}

fn detect_truecolor() -> bool {
    let var = |k: &str| std::env::var(k).unwrap_or_default().to_ascii_lowercase();
    let ct = var("COLORTERM");
    if ct.contains("truecolor") || ct.contains("24bit") {
        return true;
    }
    let t = var("TERM");
    if ["direct", "kitty", "alacritty", "wezterm", "foot", "ghostty", "contour"].iter().any(|k| t.contains(k)) {
        return true;
    }
    let tp = var("TERM_PROGRAM");
    ["wezterm", "vscode", "hyper", "ghostty", "tabby"].iter().any(|k| tp.contains(k))
}

// ------------------------------------------------------------------ RNG ----

struct Rng(u64);

impl Rng {
    fn new() -> Rng {
        let t = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_nanos() as u64)
            .unwrap_or(0x9E37_79B9_7F4A_7C15);
        let local = 0u8;
        let seed = t ^ ((std::process::id() as u64) << 32) ^ (&local as *const u8 as u64).rotate_left(17);
        let mut r = Rng(seed | 1);
        for _ in 0..4 {
            r.next();
        }
        r
    }
    fn next(&mut self) -> u64 {
        // xorshift64*
        let mut x = self.0;
        x ^= x >> 12;
        x ^= x << 25;
        x ^= x >> 27;
        self.0 = x;
        x.wrapping_mul(0x2545_F491_4F6C_DD1D)
    }
    fn f32(&mut self) -> f32 {
        (self.next() >> 40) as f32 / (1u64 << 24) as f32
    }
    fn range(&mut self, lo: u32, hi: u32) -> u32 {
        lo + (self.next() % (hi as u64 - lo as u64 + 1)) as u32
    }
}

// ------------------------------------------------------------ animation ----

struct Lane {
    delay: f32, // seconds before the stream enters
    speed: f32, // cells per second
    len: u32,   // cells this stream must cover to reach the meeting line
    trail: f32, // bright-trail length in cells (longer for faster streams)
}

struct Anim {
    w: usize,
    truecolor: bool,
    lanes: Vec<Lane>,
    heads: Vec<f32>,
    cell_lane: Vec<u32>, // lane owning each cell (row-major)
    cell_pos: Vec<u16>,  // distance of the cell from its lane's edge
    glyph: Vec<char>,
    shade: Vec<f32>, // per-cell brightness variation, for uneven colours
    drawn_key: Vec<u32>,
    drawn_ch: Vec<char>,
    rng: Rng,
    chars: (u32, u32),
    color: [f32; 3],
    head: [f32; 3],
    rest: f32,
    glitch: f32,
    fade_s: f32,
    fade_steps: u32,
    t_done: Option<f32>,
}

impl Anim {
    fn new(cfg: &Config, w: usize, h: usize, truecolor: bool) -> Anim {
        let mut rng = Rng::new();
        let dirs = if cfg.random_directions {
            // any of the 15 non-empty subsets of {top, bottom, left, right}, uniformly
            let m = rng.range(1, 15);
            [m & 1 != 0, m & 2 != 0, m & 4 != 0, m & 8 != 0]
        } else {
            cfg.directions
        };
        let enabled: Vec<Dir> = Dir::ALL.iter().zip(dirs).filter(|(_, on)| *on).map(|(d, _)| *d).collect();

        // Normalised distance of a cell from an edge: 0 at the edge, 1 at the
        // opposite edge. Scaling by the screen dimension makes horizontal and
        // vertical streams arrive together and puts meeting lines on the
        // centre/diagonals.
        let dist = |d: Dir, x: usize, y: usize| -> f32 {
            match d {
                Dir::Top => (y as f32 + 0.5) / h as f32,
                Dir::Bottom => (h as f32 - 0.5 - y as f32) / h as f32,
                Dir::Left => (x as f32 + 0.5) / w as f32,
                Dir::Right => (w as f32 - 0.5 - x as f32) / w as f32,
            }
        };
        let owner = |x: usize, y: usize| -> Dir {
            let mut best = enabled[0];
            for &d in &enabled[1..] {
                if dist(d, x, y) < dist(best, x, y) {
                    best = d;
                }
            }
            best
        };

        let mut cell_lane = vec![NONE; w * h];
        let mut cell_pos = vec![0u16; w * h];
        let mut lanes = Vec::new();
        let mut lane_dir = Vec::new();
        for &d in &enabled {
            let (count, depth) = if d.vertical() { (w, h) } else { (h, w) };
            for lane in 0..count {
                let id = lanes.len() as u32;
                let mut len = 0u32;
                for p in 0..depth {
                    let (x, y) = match d {
                        Dir::Top => (lane, p),
                        Dir::Bottom => (lane, h - 1 - p),
                        Dir::Left => (p, lane),
                        Dir::Right => (w - 1 - p, lane),
                    };
                    // ownership along a lane is always a prefix starting at the edge
                    if owner(x, y) != d {
                        break;
                    }
                    cell_lane[y * w + x] = id;
                    cell_pos[y * w + x] = p as u16;
                    len += 1;
                }
                lanes.push(Lane { delay: 0.0, speed: 1.0, len, trail: cfg.trail });
                lane_dir.push(d);
            }
        }

        // Timing. `dur` is when the last stream must have arrived: either the
        // configured duration, or derived from an absolute `speed` (rows/s for
        // the slowest vertical streams; columns move twice as fast because
        // terminal cells are about twice as tall as wide).
        let mut max_len = [1u32; 4];
        for (l, d) in lanes.iter().zip(&lane_dir) {
            let k = *d as usize;
            max_len[k] = max_len[k].max(l.len);
        }
        let dur = if cfg.speed > 0.0 {
            enabled
                .iter()
                .map(|&d| (max_len[d as usize] as f32 + 1.0) / if d.vertical() { cfg.speed } else { 2.0 * cfg.speed })
                .fold(0.0f32, f32::max)
        } else {
            cfg.duration_ms as f32 / 1000.0
        }
        .max(0.01);

        // Each stream gets a speed factor f in [1, speed_spread] (log-uniform):
        // the slowest streams need the whole `dur` to cross the longest lane of
        // their direction, the fastest only dur/spread. Faster streams start
        // later (random share of their slack), so everything still arrives by
        // `dur` while very different speeds are on screen at the same time.
        let spread = cfg.speed_spread.max(1.0);
        for (l, d) in lanes.iter_mut().zip(&lane_dir) {
            let f = spread.powf(rng.f32());
            let travel = dur / f;
            l.delay = rng.f32() * cfg.stagger * (dur - travel);
            // +1 so the head passes the last cell of the longest lane at `travel`
            l.speed = (max_len[*d as usize] as f32 + 1.0) / travel;
            l.trail = cfg.trail * f.sqrt();
        }

        let pick = |rng: &mut Rng| random_glyph(rng, cfg.chars);
        let glyph = (0..w * h).map(|_| pick(&mut rng)).collect();
        let shade = (0..w * h).map(|_| [0.72, 0.84, 0.92, 1.0][(rng.next() % 4) as usize]).collect();

        let f = |c: Rgb| [c.0 as f32, c.1 as f32, c.2 as f32];
        Anim {
            w,
            truecolor,
            heads: vec![0.0; lanes.len()],
            lanes,
            cell_lane,
            cell_pos,
            glyph,
            shade,
            drawn_key: vec![NONE; w * h],
            drawn_ch: vec!['\0'; w * h],
            rng,
            chars: cfg.chars,
            color: f(cfg.color),
            head: f(cfg.head()),
            rest: cfg.rest,
            glitch: cfg.glitch,
            fade_s: cfg.fade_ms as f32 / 1000.0,
            fade_steps: cfg.fade_steps.max(1),
            t_done: None,
        }
    }

    /// Append the escape sequences for frame `t` to `out`. Returns true once
    /// the fade-out has completed.
    fn render(&mut self, t: f32, out: &mut String) -> bool {
        let mut all_arrived = true;
        for (h, l) in self.heads.iter_mut().zip(&self.lanes) {
            *h = (t - l.delay) * l.speed;
            if *h < l.len as f32 {
                all_arrived = false;
            }
        }
        if all_arrived && self.t_done.is_none() {
            self.t_done = Some(t);
        }
        let fade = match self.t_done {
            None => 1.0,
            // No fade: still draw the frame in which the last streams arrive
            // (at full brightness), then finish on the next one.
            Some(td) if self.fade_s <= 0.0 => {
                if t > td {
                    return true;
                }
                1.0
            }
            Some(td) => {
                let p = (t - td) / self.fade_s;
                if p >= 1.0 {
                    return true;
                }
                // stepped, slightly eased-in decrease of brightness
                let n = self.fade_steps as f32;
                let step = (p * n).floor() + 1.0;
                (1.0 - step / (n + 1.0)).powf(1.3)
            }
        };

        let mut cursor: Option<usize> = None; // index the terminal cursor sits on
        let mut last_key = NONE;
        for idx in 0..self.cell_lane.len() {
            let lane = self.cell_lane[idx];
            if lane == NONE {
                continue;
            }
            let head = self.heads[lane as usize];
            let trail = self.lanes[lane as usize].trail;
            let k = head - self.cell_pos[idx] as f32; // cells behind the head
            if k < 0.0 {
                continue; // not reached yet: the old screen content stays visible
            }
            let flicker = if k < 1.0 { 0.5 } else { self.glitch };
            if self.rng.f32() < flicker {
                self.glyph[idx] = random_glyph(&mut self.rng, self.chars);
            }

            let level = self.rest + (1.0 - self.rest) * (1.0 - k / trail).max(0.0);
            let white = (1.0 - k / 1.5).clamp(0.0, 1.0);
            let s = level * self.shade[idx];
            let mut rgb = [0u8; 3];
            for c in 0..3 {
                let v = (self.color[c] * s) * (1.0 - white) + self.head[c] * white;
                rgb[c] = (v * fade).round().clamp(0.0, 255.0) as u8;
            }
            let key = if self.truecolor {
                (rgb[0] as u32) << 16 | (rgb[1] as u32) << 8 | rgb[2] as u32
            } else {
                to_ansi256(rgb) as u32
            };
            let ch = self.glyph[idx];
            if key == self.drawn_key[idx] && ch == self.drawn_ch[idx] {
                continue;
            }
            if cursor != Some(idx) {
                let _ = write!(out, "\x1b[{};{}H", idx / self.w + 1, idx % self.w + 1);
            }
            if key != last_key {
                if self.truecolor {
                    let _ = write!(out, "\x1b[38;2;{};{};{}m", rgb[0], rgb[1], rgb[2]);
                } else {
                    let _ = write!(out, "\x1b[38;5;{key}m");
                }
                last_key = key;
            }
            out.push(ch);
            self.drawn_key[idx] = key;
            self.drawn_ch[idx] = ch;
            // after printing, the cursor advances unless we're in the last column
            cursor = if (idx + 1) % self.w != 0 { Some(idx + 1) } else { None };
        }
        false
    }
}

fn random_glyph(rng: &mut Rng, (lo, hi): (u32, u32)) -> char {
    for _ in 0..8 {
        if let Some(c) = char::from_u32(rng.range(lo, hi)) {
            return c;
        }
    }
    (lo..=hi).find_map(char::from_u32).unwrap_or('\u{28FF}')
}

/// Nearest xterm-256 colour (6x6x6 cube or grey ramp).
fn to_ansi256([r, g, b]: [u8; 3]) -> u8 {
    const LV: [i32; 6] = [0, 95, 135, 175, 215, 255];
    let q = |v: u8| -> usize {
        if v < 48 {
            0
        } else if v < 115 {
            1
        } else {
            ((v as usize - 35) / 40).min(5)
        }
    };
    let (qr, qg, qb) = (q(r), q(g), q(b));
    let d2 = |a: [i32; 3]| (a[0] - r as i32).pow(2) + (a[1] - g as i32).pow(2) + (a[2] - b as i32).pow(2);
    let cube = d2([LV[qr], LV[qg], LV[qb]]);
    let avg = (r as i32 + g as i32 + b as i32) / 3;
    let gi = ((avg - 3).max(0) / 10).min(23);
    let gv = 8 + 10 * gi;
    if d2([gv, gv, gv]) < cube {
        (232 + gi) as u8
    } else {
        (16 + 36 * qr + 6 * qg + qb) as u8
    }
}
