
// neoclear — clear the terminal with converging streams of braille glyphs
// Copyright (C) 2026 Fabian Transchel
// SPDX-License-Identifier: GPL-3.0-or-later

//! Configuration: defaults, a small TOML-subset config file, and CLI flags.
//! Precedence: built-in defaults < config file < command-line flags.

use std::fmt::Write as _;
use std::path::PathBuf;

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Dir {
    Top,
    Bottom,
    Left,
    Right,
}

impl Dir {
    pub const ALL: [Dir; 4] = [Dir::Top, Dir::Bottom, Dir::Left, Dir::Right];
    pub fn name(self) -> &'static str {
        match self {
            Dir::Top => "top",
            Dir::Bottom => "bottom",
            Dir::Left => "left",
            Dir::Right => "right",
        }
    }
    pub fn vertical(self) -> bool {
        matches!(self, Dir::Top | Dir::Bottom)
    }
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum ColorMode {
    Auto,
    TrueColor,
    Ansi256,
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub struct Rgb(pub u8, pub u8, pub u8);

impl Rgb {
    fn hex(self) -> String {
        format!("#{:02x}{:02x}{:02x}", self.0, self.1, self.2)
    }
}

#[derive(Clone, Debug)]
pub struct Config {
    /// Which edges streams start from: [top, bottom, left, right].
    pub directions: [bool; 4],
    /// Pick a random (non-empty) combination of edges on every run instead.
    pub random_directions: bool,
    /// Time (ms) until every stream has reached the meeting line.
    pub duration_ms: u64,
    /// Length (ms) of the fade-out once all streams have arrived.
    pub fade_ms: u64,
    /// Number of discrete brightness steps in the fade.
    pub fade_steps: u32,
    pub fps: u32,
    /// Body colour of the streams.
    pub color: Rgb,
    /// Colour of the leading glyph of each stream; None = a whitened tint of `color`.
    pub head_color: Option<Rgb>,
    /// Trail length in cells over which brightness drops to `rest`.
    pub trail: f32,
    /// Brightness (0..1) of glyphs behind the trail.
    pub rest: f32,
    /// Ratio between the fastest and the slowest stream (1 = all equal).
    pub speed_spread: f32,
    /// Absolute speed of the slowest streams in rows/s; 0 = derive from duration_ms.
    pub speed: f32,
    /// How much of its spare time (0..1) a fast stream may wait before starting.
    pub stagger: f32,
    /// Per-frame probability that a settled glyph changes.
    pub glitch: f32,
    /// Inclusive code-point range glyphs are drawn from.
    pub chars: (u32, u32),
    pub color_mode: ColorMode,
    /// Also wipe the scrollback buffer (ESC[3J), like `clear`.
    pub clear_scrollback: bool,
}

impl Default for Config {
    fn default() -> Self {
        Config {
            directions: [true, false, false, false],
            random_directions: false,
            duration_ms: 900,
            fade_ms: 350,
            fade_steps: 10,
            fps: 60,
            color: Rgb(0x1c, 0xff, 0x5a),
            head_color: None,
            trail: 10.0,
            rest: 0.45,
            speed_spread: 3.0,
            speed: 0.0,
            stagger: 0.9,
            glitch: 0.02,
            chars: (0x2800, 0x28FF),
            color_mode: ColorMode::Auto,
            clear_scrollback: true,
        }
    }
}

/// Ok(None) means "random": choose a combination at run time.
pub fn parse_directions(s: &str) -> Result<Option<[bool; 4]>, String> {
    let mut d = [false; 4];
    let mut random = false;
    let tokens = s
        .split(|c: char| c == ',' || c == '+' || c == '|' || c == '/' || c.is_whitespace())
        .filter(|t| !t.is_empty());
    for tok in tokens {
        let t = tok.to_ascii_lowercase();
        match t.as_str() {
            "top" | "up" | "above" | "t" => d[0] = true,
            "bottom" | "down" | "below" | "b" => d[1] = true,
            "left" | "l" => d[2] = true,
            "right" | "r" => d[3] = true,
            "vertical" | "v" => {
                d[0] = true;
                d[1] = true
            }
            "horizontal" | "sides" | "h" => {
                d[2] = true;
                d[3] = true
            }
            "all" | "a" | "everywhere" => d = [true; 4],
            "random" | "rand" | "rnd" | "any" | "?" => random = true,
            // compact letter form, e.g. "tblr" or "tl"
            _ if t.chars().all(|c| "tblr".contains(c)) => {
                for c in t.chars() {
                    d["tblr".find(c).unwrap()] = true;
                }
            }
            _ => return Err(format!("unknown direction '{tok}' (use top, bottom, left, right, vertical, horizontal, all, random)")),
        }
    }
    if random {
        if d.iter().any(|&b| b) {
            return Err("'random' can't be combined with other directions".into());
        }
        Ok(None)
    } else if d.iter().any(|&b| b) {
        Ok(Some(d))
    } else {
        Err("no direction given".into())
    }
}

pub fn directions_string(d: &[bool; 4]) -> String {
    let v: Vec<&str> = Dir::ALL.iter().zip(d).filter(|(_, &on)| on).map(|(x, _)| x.name()).collect();
    v.join("+")
}

/// Colour names accepted besides hex (tuned to look good as streams).
const NAMED: [(&str, Rgb); 11] = [
    ("green", Rgb(0x1c, 0xff, 0x5a)),
    ("red", Rgb(0xff, 0x2d, 0x2d)),
    ("blue", Rgb(0x3d, 0x7d, 0xff)),
    ("cyan", Rgb(0x00, 0xe5, 0xff)),
    ("magenta", Rgb(0xff, 0x3d, 0xf2)),
    ("yellow", Rgb(0xff, 0xe5, 0x3d)),
    ("amber", Rgb(0xff, 0xb0, 0x00)),
    ("orange", Rgb(0xff, 0x8c, 0x1a)),
    ("purple", Rgb(0xa6, 0x4d, 0xff)),
    ("pink", Rgb(0xff, 0x6e, 0xb4)),
    ("white", Rgb(0xe8, 0xe8, 0xe8)),
];

fn parse_color(s: &str) -> Result<Rgb, String> {
    let lower = s.trim().to_ascii_lowercase();
    if let Some((_, c)) = NAMED.iter().find(|(n, _)| *n == lower) {
        return Ok(*c);
    }
    let h = s.trim().trim_start_matches('#');
    let bad = || {
        let names: Vec<&str> = NAMED.iter().map(|(n, _)| *n).collect();
        format!("bad colour '{s}' (expected #rrggbb, #rgb or one of: {})", names.join(", "))
    };
    let nib = |c: char| c.to_digit(16).map(|v| v as u8).ok_or_else(bad);
    let ch: Vec<char> = h.chars().collect();
    match ch.len() {
        6 => Ok(Rgb(
            nib(ch[0])? * 16 + nib(ch[1])?,
            nib(ch[2])? * 16 + nib(ch[3])?,
            nib(ch[4])? * 16 + nib(ch[5])?,
        )),
        3 => Ok(Rgb(nib(ch[0])? * 17, nib(ch[1])? * 17, nib(ch[2])? * 17)),
        _ => Err(bad()),
    }
}

/// "2800-28FF", "U+2800-U+28FF", "0x2800..0x28ff" (hex), or "d10240-10495" (decimal).
fn parse_chars(s: &str) -> Result<(u32, u32), String> {
    let s = s.trim();
    let (decimal, body) = match s.strip_prefix(['d', 'D']) {
        Some(rest) => (true, rest),
        None => (false, s),
    };
    let (a, b) = body
        .split_once("..")
        .or_else(|| body.split_once('-'))
        .ok_or_else(|| format!("bad char range '{s}' (expected e.g. 2800-28FF)"))?;
    let num = |x: &str| {
        let x = x.trim();
        let x = x.strip_prefix("U+").or(x.strip_prefix("u+")).or(x.strip_prefix("0x")).unwrap_or(x);
        let r = if decimal { x.parse::<u32>() } else { u32::from_str_radix(x, 16) };
        r.map_err(|_| format!("bad code point '{x}' in '{s}'"))
    };
    let (lo, hi) = (num(a)?, num(b)?);
    if lo > hi || hi > 0x10FFFF || !(lo..=hi).any(|c| char::from_u32(c).is_some()) {
        return Err(format!("unusable char range '{s}'"));
    }
    Ok((lo, hi))
}

fn parse_num<T: std::str::FromStr>(key: &str, v: &str) -> Result<T, String> {
    v.trim().parse().map_err(|_| format!("bad value '{v}' for {key}"))
}

fn parse_unit(key: &str, v: &str) -> Result<f32, String> {
    let x: f32 = parse_num(key, v)?;
    if (0.0..=1.0).contains(&x) {
        Ok(x)
    } else {
        Err(format!("{key} must be between 0 and 1"))
    }
}

fn parse_bool(key: &str, v: &str) -> Result<bool, String> {
    match v.trim().to_ascii_lowercase().as_str() {
        "true" | "yes" | "on" | "1" => Ok(true),
        "false" | "no" | "off" | "0" => Ok(false),
        _ => Err(format!("bad boolean '{v}' for {key}")),
    }
}

impl Config {
    /// The head colour actually used: explicit, or `color` mixed 80% towards white.
    pub fn head(&self) -> Rgb {
        self.head_color.unwrap_or_else(|| {
            let w = |c: u8| (c as f32 + (255.0 - c as f32) * 0.8).round() as u8;
            Rgb(w(self.color.0), w(self.color.1), w(self.color.2))
        })
    }

    /// Set one option by its config-file key.
    pub fn set(&mut self, key: &str, v: &str) -> Result<(), String> {
        let key = key.trim().replace('-', "_").to_ascii_lowercase();
        match key.as_str() {
            "directions" | "direction" | "from" => match parse_directions(v)? {
                Some(d) => {
                    self.directions = d;
                    self.random_directions = false;
                }
                None => self.random_directions = true,
            },
            "duration" | "duration_ms" => self.duration_ms = parse_num(&key, v)?,
            "fade" | "fade_ms" => self.fade_ms = parse_num(&key, v)?,
            "fade_steps" => self.fade_steps = parse_num::<u32>(&key, v)?.max(1),
            "fps" => self.fps = parse_num::<u32>(&key, v)?.clamp(1, 1000),
            "color" | "colour" => self.color = parse_color(v)?,
            "head_color" | "head_colour" => {
                self.head_color = match v.trim().to_ascii_lowercase().as_str() {
                    "auto" | "" => None,
                    _ => Some(parse_color(v)?),
                }
            }
            "trail" => self.trail = parse_num::<f32>(&key, v)?.max(1.0),
            "rest" => self.rest = parse_unit(&key, v)?,
            "speed_spread" | "spread" => {
                let x: f32 = parse_num(&key, v)?;
                if !(1.0..=20.0).contains(&x) {
                    return Err(format!("{key} must be between 1 and 20"));
                }
                self.speed_spread = x;
            }
            "speed" => {
                let x: f32 = parse_num(&key, v)?;
                if x < 0.0 {
                    return Err(format!("{key} must be >= 0 (0 = use duration_ms)"));
                }
                self.speed = x;
            }
            // pre-0.2 name: 0..1 variation, mapped onto a spread ratio
            "jitter" => self.speed_spread = 1.0 / (1.0 - parse_unit(&key, v)?.min(0.95)),
            "stagger" => self.stagger = parse_unit(&key, v)?,
            "glitch" => self.glitch = parse_unit(&key, v)?,
            "chars" | "charset" => self.chars = parse_chars(v)?,
            "color_mode" | "colormode" => {
                self.color_mode = match v.trim().to_ascii_lowercase().as_str() {
                    "auto" => ColorMode::Auto,
                    "truecolor" | "24bit" | "rgb" => ColorMode::TrueColor,
                    "256" | "ansi256" => ColorMode::Ansi256,
                    _ => return Err(format!("bad color_mode '{v}' (auto, truecolor, 256)")),
                }
            }
            "clear_scrollback" => self.clear_scrollback = parse_bool(&key, v)?,
            _ => return Err(format!("unknown option '{key}'")),
        }
        Ok(())
    }

    pub fn load_file(&mut self, path: &std::path::Path, src: &str) -> Vec<String> {
        let mut warnings = Vec::new();
        for (i, raw) in src.lines().enumerate() {
            let line = raw.trim();
            if line.is_empty() || line.starts_with('#') || line.starts_with('[') && !line.contains('=') {
                continue;
            }
            let Some((k, v)) = line.split_once('=') else {
                warnings.push(format!("{}:{}: expected 'key = value'", path.display(), i + 1));
                continue;
            };
            let v = clean_value(v);
            if let Err(e) = self.set(k, &v) {
                warnings.push(format!("{}:{}: {e}", path.display(), i + 1));
            }
        }
        warnings
    }

    pub fn to_toml(&self) -> String {
        let mode = match self.color_mode {
            ColorMode::Auto => "auto",
            ColorMode::TrueColor => "truecolor",
            ColorMode::Ansi256 => "256",
        };
        let mut s = String::new();
        let _ = write!(
            s,
            r#"# neoclear configuration
# Command-line flags override anything set here.

# Edges the streams start from. Any combination of top, bottom, left, right
# joined with '+' or ',' — or a shortcut: vertical (top+bottom),
# horizontal (left+right), all. Streams meet at the centre.
# "random" picks one of the 15 possible combinations on every run.
directions = "{dirs}"

# Milliseconds until every stream has reached the centre. Alternatively set
# `speed` (rows per second of the slowest streams); then the run takes longer
# on bigger terminals, like cmatrix. speed = 0 means: use duration_ms.
duration_ms = {dur}
speed = {speed}
# Milliseconds of fade-out after the streams have met, and how many
# brightness steps it uses (fewer steps = less output on huge terminals).
fade_ms = {fade}
fade_steps = {steps}
fps = {fps}

# Stream colour as #rrggbb, #rgb, or a name: green, red, blue, cyan, magenta,
# yellow, amber, orange, purple, pink, white. The leading glyph of each stream
# is drawn in a whitened tint of it unless head_color is set ("auto" = tint).
color = "{color}"
head_color = "{head}"
# Trail length in cells, and brightness (0..1) of glyphs behind it.
trail = {trail}
rest = {rest}

# Ratio between the fastest and the slowest stream (1 = all move together,
# 3 = fastest is 3x the slowest). Fast streams also get longer trails.
speed_spread = {spread}
# How much of its spare time (0..1) a fast stream may wait before it starts;
# lower values make streams start together, higher values scatter them.
stagger = {stagger}
# Per-frame chance (0..1) that a settled glyph flickers.
glitch = {glitch}

# Code-point range to draw from (hex). Braille is 2800-28FF.
chars = "{lo:04X}-{hi:04X}"

# auto, truecolor or 256
color_mode = "{mode}"
# Also erase the scrollback buffer, like `clear` does.
clear_scrollback = {sb}
"#,
            dirs = if self.random_directions { "random".into() } else { directions_string(&self.directions) },
            dur = self.duration_ms,
            fade = self.fade_ms,
            steps = self.fade_steps,
            fps = self.fps,
            color = self.color.hex(),
            head = self.head_color.map(|c| c.hex()).unwrap_or_else(|| "auto".into()),
            trail = self.trail,
            rest = self.rest,
            spread = self.speed_spread,
            speed = self.speed,
            stagger = self.stagger,
            glitch = self.glitch,
            lo = self.chars.0,
            hi = self.chars.1,
            mode = mode,
            sb = self.clear_scrollback,
        );
        s
    }
}

/// Strip a trailing comment, quotes and array brackets: `["top", "left"] # x` -> `top, left`.
fn clean_value(v: &str) -> String {
    let mut out = String::new();
    let mut quote: Option<char> = None;
    for c in v.chars() {
        match (quote, c) {
            (Some(q), c) if c == q => quote = None,
            (Some(_), c) => out.push(c),
            (None, '"' | '\'') => quote = Some(c),
            // '#' starts a comment only once a value has begun (so `color = #0f0` works)
            (None, '#') if !out.trim().is_empty() => break,
            (None, '[' | ']') => {}
            (None, c) => out.push(c),
        }
    }
    out.trim().to_string()
}

pub fn default_path() -> Option<PathBuf> {
    let env = |k: &str| std::env::var_os(k).filter(|v| !v.is_empty()).map(PathBuf::from);
    let base = env("XDG_CONFIG_HOME").or_else(|| env("HOME").map(|p| p.join(".config")));
    base.map(|b| b.join("neoclear").join("config.toml"))
}

pub enum Action {
    Run { cfg: Config, size: Option<(usize, usize)> },
    PrintConfig(Config),
    WriteConfig(Config, PathBuf),
    ShowPath(Option<PathBuf>),
    Help,
    Version,
}

pub const HELP: &str = "\
neoclear — clear the terminal with converging streams of braille glyphs

USAGE:
    neoclear [OPTIONS]

Streams of braille characters (U+2800–U+28FF) pour in from the chosen edges
until they meet in the middle, glow, fade to black, and leave a clean screen.

OPTIONS:
    -d, --directions <LIST>  Edges to pour from: top, bottom, left, right in any
                             combination (\"top+left\", \"tb\", \"left,right\"),
                             or vertical | horizontal | all, or random
                             (a new combination every run)     [default: top]
    -t, --duration <MS>      Time until all streams reach the centre  [900]
    -f, --fade <MS>          Fade-out time after they meet           [350]
        --fade-steps <N>     Brightness steps used by the fade       [10]
        --fps <N>            Frames per second                       [60]
    -c, --color <COLOR>      Stream colour: #rrggbb, #rgb, or green, red,
                             blue, cyan, magenta, yellow, amber,
                             orange, purple, pink, white       [#1cff5a]
        --head-color <HEX>   Leading glyph colour, or auto          [auto]
        --trail <CELLS>      Length of the bright trail              [10]
        --rest <0..1>        Brightness behind the trail             [0.45]
    -s, --speed-spread <X>   Fastest/slowest stream speed ratio,
                             1 = all equal                          [3]
        --speed <ROWS/S>     Absolute speed of the slowest streams;
                             0 = fit into --duration                [0]
        --stagger <0..1>     How long fast streams may wait to start [0.9]
        --glitch <0..1>      Per-frame flicker chance of a glyph     [0.02]
        --chars <RANGE>      Code points to use, hex                 [2800-28FF]
        --colormode <MODE>   auto | truecolor | 256                  [auto]
        --keep-scrollback    Don't erase the scrollback buffer
        --clear-scrollback   Erase the scrollback buffer too (default)
        --size <COLSxROWS>   Override the detected size (also forces the
                             animation when stdout isn't a terminal)

CONFIG:
        --config <PATH>      Use this config file instead of the default
        --no-config          Ignore the config file
        --print-config       Print the effective configuration as TOML
        --write-config       Write the effective configuration to the config
                             file (combine with flags to save them as defaults)
        --config-path        Print where the config file is looked for
    -h, --help               Show this help
    -V, --version            Show version

Default config file: $XDG_CONFIG_HOME/neoclear/config.toml
                     (~/.config/neoclear/config.toml)

Ctrl-C at any point skips straight to the final clear.
Tip: alias clear=neoclear
";

pub fn from_args() -> Result<(Action, Vec<String>), String> {
    let args: Vec<String> = std::env::args().skip(1).collect();

    // Pass 1: where does the config come from?
    let mut path = default_path();
    let mut explicit_path = false;
    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--no-config" => path = None,
            "--config" => {
                let p = args.get(i + 1).ok_or("--config needs a path")?;
                path = Some(PathBuf::from(p));
                explicit_path = true;
                i += 1;
            }
            a if a.starts_with("--config=") => {
                path = Some(PathBuf::from(&a["--config=".len()..]));
                explicit_path = true;
            }
            _ => {}
        }
        i += 1;
    }

    let mut cfg = Config::default();
    let mut warnings = Vec::new();
    let write_target = path.clone().or_else(default_path);
    if let Some(p) = &path {
        match std::fs::read_to_string(p) {
            Ok(src) => warnings = cfg.load_file(p, &src),
            Err(e) if explicit_path => return Err(format!("cannot read {}: {e}", p.display())),
            Err(_) => {}
        }
    }

    // Pass 2: flags.
    let mut size = None;
    let mut mode = 0; // 0 run, 1 print, 2 write, 3 path
    let mut i = 0;
    while i < args.len() {
        let (flag, inline) = match args[i].split_once('=') {
            Some((f, v)) if f.starts_with("--") => (f.to_string(), Some(v.to_string())),
            _ => (args[i].clone(), None),
        };
        let mut value = |name: &str| -> Result<String, String> {
            if let Some(v) = &inline {
                return Ok(v.clone());
            }
            i += 1;
            args.get(i).cloned().ok_or_else(|| format!("{name} needs a value"))
        };
        let key = match flag.as_str() {
            "-h" | "--help" => return Ok((Action::Help, warnings)),
            "-V" | "--version" => return Ok((Action::Version, warnings)),
            "--no-config" => None,
            "--config" => {
                value("--config")?;
                None
            }
            "--print-config" => {
                mode = 1;
                None
            }
            "--write-config" => {
                mode = 2;
                None
            }
            "--config-path" => {
                mode = 3;
                None
            }
            "--keep-scrollback" => {
                cfg.clear_scrollback = false;
                None
            }
            "--clear-scrollback" => {
                cfg.clear_scrollback = true;
                None
            }
            "--size" => {
                let v = value("--size")?;
                let (w, h) = v
                    .split_once(['x', 'X'])
                    .and_then(|(w, h)| Some((w.trim().parse().ok()?, h.trim().parse().ok()?)))
                    .ok_or_else(|| format!("bad --size '{v}' (expected e.g. 120x40)"))?;
                size = Some((w, h));
                None
            }
            "-d" | "--directions" | "--direction" | "--from" => Some("directions"),
            "-t" | "--duration" => Some("duration_ms"),
            "-f" | "--fade" => Some("fade_ms"),
            "--fade-steps" => Some("fade_steps"),
            "--fps" => Some("fps"),
            "-c" | "--color" | "--colour" => Some("color"),
            "--head-color" | "--head-colour" => Some("head_color"),
            "--trail" => Some("trail"),
            "--rest" => Some("rest"),
            "-s" | "--speed-spread" | "--spread" => Some("speed_spread"),
            "--speed" => Some("speed"),
            "--jitter" => Some("jitter"),
            "--stagger" => Some("stagger"),
            "--glitch" => Some("glitch"),
            "--chars" => Some("chars"),
            "--colormode" | "--color-mode" => Some("color_mode"),
            other => return Err(format!("unknown option '{other}'")),
        };
        if let Some(k) = key {
            let v = value(&flag)?;
            cfg.set(k, &v).map_err(|e| format!("{flag}: {e}"))?;
        }
        i += 1;
    }

    let action = match mode {
        1 => Action::PrintConfig(cfg),
        2 => Action::WriteConfig(cfg, write_target.ok_or("cannot determine config path (HOME not set)")?),
        3 => Action::ShowPath(path),
        _ => Action::Run { cfg, size },
    };
    Ok((action, warnings))
}
