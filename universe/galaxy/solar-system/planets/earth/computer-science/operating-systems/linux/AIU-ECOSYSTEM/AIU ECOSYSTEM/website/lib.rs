use std::collections::HashMap;
use std::sync::Mutex;

use notation::database_store::Store;

static DB: Mutex<Option<Store>> = Mutex::new(None);
static LAST: Mutex<String> = Mutex::new(String::new());

const BOX_W: f64 = 240.0;
const BOX_H: f64 = 64.0;
const GAP: f64 = 24.0;
const STEP_X: f64 = 264.0;
const STEP_Y: f64 = 88.0;
const MARGIN: f64 = 200.0;
const MAX_CHARS: usize = 26;

#[link(wasm_import_module = "env")]
extern "C" {
    fn send(ptr: *const u8, len: usize);
    fn rect(x: f64, y: f64, w: f64, h: f64);
    fn line(x1: f64, y1: f64, x2: f64, y2: f64);
    fn text(ptr: *const u8, len: usize, x: f64, y: f64);
}

struct Boxed {
    key: String,
    title: String,
    x: f64,
    y: f64,
}

#[no_mangle]
pub extern "C" fn alloc(len: usize) -> *mut u8 {
    let mut v = Vec::<u8>::with_capacity(len);
    let p = v.as_mut_ptr();
    std::mem::forget(v);
    p
}

#[no_mangle]
pub unsafe extern "C" fn free_buf(ptr: *mut u8, len: usize) {
    drop(Vec::from_raw_parts(ptr, 0, len));
}

#[no_mangle]
pub unsafe extern "C" fn load_index(ptr: *const u8, len: usize) -> i32 {
    let bytes = std::slice::from_raw_parts(ptr, len);
    let body = match std::str::from_utf8(bytes) {
        Ok(t) => t,
        Err(_) => return -1,
    };
    match notation::database_file_format::decode(body) {
        Ok(store) => {
            let n = store.of_kind("block").len() as i32;
            *DB.lock().unwrap_or_else(|e| e.into_inner()) = Some(store);
            n
        }
        Err(_) => -2,
    }
}

#[no_mangle]
pub extern "C" fn block_count() -> i32 {
    match DB.lock().unwrap_or_else(|e| e.into_inner()).as_ref() {
        Some(s) => s.of_kind("block").len() as i32,
        None => -1,
    }
}

#[no_mangle]
pub unsafe extern "C" fn command(ptr: *const u8, len: usize) {
    send(ptr, len);
}

#[no_mangle]
pub unsafe extern "C" fn on_message(ptr: *const u8, len: usize) {
    let bytes = std::slice::from_raw_parts(ptr, len);
    let body = String::from_utf8_lossy(bytes).to_string();
    *LAST.lock().unwrap_or_else(|e| e.into_inner()) = body;
}

#[no_mangle]
pub extern "C" fn answer_ptr() -> *const u8 {
    LAST.lock().unwrap_or_else(|e| e.into_inner()).as_ptr()
}

#[no_mangle]
pub extern "C" fn answer_len() -> usize {
    LAST.lock().unwrap_or_else(|e| e.into_inner()).len()
}

fn parse_place(s: &str) -> Option<(f64, f64)> {
    let mut it = s.split_whitespace();
    let x = it.next()?.parse::<f64>().ok()?;
    let y = it.next()?.parse::<f64>().ok()?;
    Some((x, y))
}

fn layout(store: &Store, width: f64) -> Vec<Boxed> {
    let files = store.of_kind("file");
    let mut out: Vec<Boxed> = Vec::new();
    let mut loose: Vec<(String, String)> = Vec::new();
    let mut last_row: f64 = -1.0;
    for r in &files {
        let title = r.field("title").unwrap_or("").to_string();
        match r.field("place").and_then(parse_place) {
            Some((px, py)) => {
                if py > last_row {
                    last_row = py;
                }
                out.push(Boxed {
                    key: r.key.clone(),
                    title,
                    x: GAP + px * STEP_X,
                    y: GAP + py * STEP_Y,
                });
            }
            None => loose.push((r.key.clone(), title)),
        }
    }
    let cols = (((width - GAP) / STEP_X) as usize).max(1);
    let first = last_row.floor() + 1.0;
    for (i, (key, title)) in loose.into_iter().enumerate() {
        let col = (i % cols) as f64;
        let row = first + (i / cols) as f64;
        out.push(Boxed {
            key,
            title,
            x: GAP + col * STEP_X,
            y: GAP + row * STEP_Y,
        });
    }
    out
}

fn name_map(store: &Store) -> HashMap<String, String> {
    let mut m: HashMap<String, String> = HashMap::new();
    let files = store.of_kind("file");
    for r in &files {
        m.entry(r.key.clone()).or_insert_with(|| r.key.clone());
    }
    for r in &files {
        if let Some(last) = r.key.rsplit("/").next() {
            m.entry(last.to_string()).or_insert_with(|| r.key.clone());
        }
    }
    for r in store.of_kind("name") {
        if let Some(n) = r.field("name") {
            m.entry(n.to_string()).or_insert_with(|| r.source.clone());
        }
    }
    for r in store.of_kind("block") {
        if let Some(n) = r.field("declared-name") {
            if !n.is_empty() {
                m.entry(n.to_string()).or_insert_with(|| r.source.clone());
            }
        }
    }
    m
}

fn fit(title: &str, key: &str) -> String {
    let base = if title.is_empty() {
        key.rsplit("/").next().unwrap_or(key)
    } else {
        title
    };
    if base.chars().count() <= MAX_CHARS {
        base.to_string()
    } else {
        let mut s: String = base.chars().take(MAX_CHARS - 1).collect();
        s.push_str("…");
        s
    }
}

fn anchors(a: &Boxed, b: &Boxed) -> (f64, f64, f64, f64) {
    let dx = b.x - a.x;
    let dy = b.y - a.y;
    if dx.abs() >= dy.abs() {
        if dx >= 0.0 {
            (a.x + BOX_W, a.y + BOX_H / 2.0, b.x, b.y + BOX_H / 2.0)
        } else {
            (a.x, a.y + BOX_H / 2.0, b.x + BOX_W, b.y + BOX_H / 2.0)
        }
    } else if dy >= 0.0 {
        (a.x + BOX_W / 2.0, a.y + BOX_H, b.x + BOX_W / 2.0, b.y)
    } else {
        (a.x + BOX_W / 2.0, a.y, b.x + BOX_W / 2.0, b.y + BOX_H)
    }
}

#[no_mangle]
pub extern "C" fn draw(width: f64, height: f64, sx: f64, sy: f64) -> i32 {
    let guard = DB.lock().unwrap_or_else(|e| e.into_inner());
    let store = match guard.as_ref() {
        Some(s) => s,
        None => return -1,
    };
    let boxes = layout(store, width);
    let index: HashMap<&str, usize> = boxes
        .iter()
        .enumerate()
        .map(|(i, b)| (b.key.as_str(), i))
        .collect();
    let names = name_map(store);
    let seen = |x: f64, y: f64, w: f64, h: f64| -> bool {
        x + w >= sx - MARGIN && x <= sx + width + MARGIN && y + h >= sy - MARGIN && y <= sy + height + MARGIN
    };
    let mut drawn: i32 = 0;
    unsafe {
        for r in store.of_kind("link") {
            let from = match index.get(r.source.as_str()) {
                Some(i) => *i,
                None => continue,
            };
            let target = r.field("target").unwrap_or("").trim();
            let to = match names.get(target).and_then(|k| index.get(k.as_str())) {
                Some(i) => *i,
                None => continue,
            };
            if from == to {
                continue;
            }
            let (ax, ay, bx, by) = anchors(&boxes[from], &boxes[to]);
            let left = ax.min(bx);
            let top = ay.min(by);
            if seen(left, top, (ax - bx).abs(), (ay - by).abs()) {
                line(ax - sx, ay - sy, bx - sx, by - sy);
            }
        }
        for b in &boxes {
            if seen(b.x, b.y, BOX_W, BOX_H) {
                rect(b.x - sx, b.y - sy, BOX_W, BOX_H);
                let t = fit(&b.title, &b.key);
                text(t.as_ptr(), t.len(), b.x - sx + 8.0, b.y - sy + 8.0);
                drawn += 1;
            }
        }
    }
    drawn
}
