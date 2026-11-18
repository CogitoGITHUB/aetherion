use std::collections::{HashMap, HashSet};
use std::sync::Mutex;

use notation::database_store::Store;

static DB: Mutex<Option<Store>> = Mutex::new(None);
static LAST: Mutex<String> = Mutex::new(String::new());

const BOX_W: f64 = 240.0;
const BOX_H: f64 = 76.0;
const GAP: f64 = 24.0;
const STEP_X: f64 = 264.0;
const STEP_Y: f64 = 100.0;
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

struct Frame {
    title: String,
    x: f64,
    y: f64,
    w: f64,
    h: f64,
}

struct Item {
    what: String,
    target: String,
    place: Option<(f64, f64)>,
    caption: String,
}

const PAD: f64 = 16.0;
const HEAD: f64 = 56.0;

fn resolve(t: &str, titles: &HashMap<String, String>) -> Option<String> {
    let t = t.trim();
    if titles.contains_key(t) {
        return Some(t.to_string());
    }
    let mut keys: Vec<&String> = titles.keys().collect();
    keys.sort();
    for k in keys {
        if k.rsplit("/").next() == Some(t) {
            return Some(k.clone());
        }
    }
    None
}

fn build(
    name: &str,
    groups: &HashMap<String, Vec<Item>>,
    titles: &HashMap<String, String>,
    placed: &mut HashSet<String>,
    path: &mut Vec<String>,
) -> (Vec<Boxed>, Vec<Frame>, f64, f64) {
    let mut cards: Vec<Boxed> = Vec::new();
    let mut frames: Vec<Frame> = Vec::new();
    let mut taken: HashSet<(i64, i64)> = HashSet::new();
    let mut mw = PAD + BOX_W + PAD;
    let mut mh = HEAD + BOX_H + PAD;
    path.push(name.to_string());
    if let Some(items) = groups.get(name) {
        for it in items {
            let mut file: Option<String> = None;
            if it.what == "box" {
                if path.iter().any(|p| p == &it.target)
                    || !groups.contains_key(&it.target)
                {
                    continue;
                }
            } else {
                match resolve(&it.target, titles) {
                    Some(k) => {
                        if placed.contains(&k) {
                            continue;
                        }
                        file = Some(k);
                    }
                    None => continue,
                }
            }
            let (mut px, mut py) = it.place.unwrap_or((0.0, 0.0));
            let mut guard = 0;
            while taken.contains(&(px.round() as i64, py.round() as i64))
                && guard < 1000
            {
                px += 1.0;
                guard += 1;
            }
            taken.insert((px.round() as i64, py.round() as i64));
            let x = PAD + px * STEP_X;
            let y = HEAD + py * STEP_Y;
            if let Some(k) = file {
                placed.insert(k.clone());
                desc_set(&format!("k:{}", k), &it.caption);
                let title = titles.get(&k).cloned().unwrap_or_default();
                cards.push(Boxed { key: k, title, x, y });
                mw = mw.max(x + BOX_W + PAD);
                mh = mh.max(y + BOX_H + PAD);
            } else {
                let (c, f, w, h) =
                    { desc_set(&format!("l:{}", it.target), &it.caption); build(&it.target, groups, titles, placed, path) };
                frames.push(Frame { title: it.target.clone(), x, y, w, h });
                for mut b in c {
                    b.x += x;
                    b.y += y;
                    cards.push(b);
                }
                for mut g in f {
                    g.x += x;
                    g.y += y;
                    frames.push(g);
                }
                mw = mw.max(x + w + PAD);
                mh = mh.max(y + h + PAD);
            }
        }
    }
    path.pop();
    (cards, frames, mw, mh)
}

fn arrange(store: &Store, width: f64) -> (Vec<Boxed>, Vec<Frame>) {
    *DESC.lock().unwrap_or_else(|e| e.into_inner()) = None;
    let files = store.of_kind("file");
    let mut titles: HashMap<String, String> = HashMap::new();
    for r in &files {
        titles.insert(r.key.clone(), r.field("title").unwrap_or("").to_string());
    }
    let recs = store.of_kind("layout-item");
    let mut rows: Vec<(String, i64, String, Item)> = Vec::new();
    for r in &recs {
        let lay = r.field("layout").unwrap_or("").trim().to_string();
        if lay.is_empty() {
            continue;
        }
        if r.field("what") == Some("layout") {
            desc_set(&format!("l:{}", lay), r.field("caption").unwrap_or("").trim());
            continue;
        }
        let line = r
            .field("line")
            .and_then(|s| s.parse::<i64>().ok())
            .unwrap_or(0);
        rows.push((
            r.source.clone(),
            line,
            lay,
            Item {
                what: r.field("what").unwrap_or("").to_string(),
                target: r.field("target").unwrap_or("").trim().to_string(),
                place: r.field("place").and_then(parse_place),
                caption: r.field("caption").unwrap_or("").trim().to_string(),
            },
        ));
    }
    rows.sort_by(|a, b| (a.0.clone(), a.1).cmp(&(b.0.clone(), b.1)));
    let mut groups: HashMap<String, Vec<Item>> = HashMap::new();
    let mut nested: HashSet<String> = HashSet::new();
    for (_, _, lay, item) in rows {
        if item.what == "box" {
            nested.insert(item.target.clone());
        }
        groups.entry(lay).or_default().push(item);
    }
    let mut names: Vec<String> = groups.keys().cloned().collect();
    names.sort();
    let mut placed: HashSet<String> = HashSet::new();
    let mut cards: Vec<Boxed> = Vec::new();
    let mut frames: Vec<Frame> = Vec::new();
    let mut sx = GAP;
    let mut sy = GAP;
    let mut rowh: f64 = 0.0;
    let mut any = false;
    for name in &names {
        if nested.contains(name) {
            continue;
        }
        let mut path: Vec<String> = Vec::new();
        let (c, f, w, h) = build(name, &groups, &titles, &mut placed, &mut path);
        if sx > GAP && sx + w > width {
            sx = GAP;
            sy += rowh + GAP;
            rowh = 0.0;
        }
        frames.push(Frame { title: name.clone(), x: sx, y: sy, w, h });
        for mut b in c {
            b.x += sx;
            b.y += sy;
            cards.push(b);
        }
        for mut g in f {
            g.x += sx;
            g.y += sy;
            frames.push(g);
        }
        sx += w + GAP;
        rowh = rowh.max(h);
        any = true;
    }
    let top = if any { sy + rowh } else { 0.0 };
    let mut rest = plain(store, width, &placed, top);
    cards.append(&mut rest);
    (cards, frames)
}

fn layout(store: &Store, width: f64) -> Vec<Boxed> {
    arrange(store, width).0
}

fn plain(
    store: &Store,
    width: f64,
    skip: &HashSet<String>,
    top: f64,
) -> Vec<Boxed> {
    let files = store.of_kind("file");
    let mut out: Vec<Boxed> = Vec::new();
    let mut loose: Vec<(String, String)> = Vec::new();
    let mut last_row: f64 = -1.0;
    for r in &files {
        if skip.contains(&r.key) {
            continue;
        }
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
                    y: GAP + py * STEP_Y + top,
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
            y: GAP + row * STEP_Y + top,
        });
    }
    out
}

static SCENE: Mutex<String> = Mutex::new(String::new());
static DESC: Mutex<Option<HashMap<String, String>>> = Mutex::new(None);

fn desc_set(k: &str, v: &str) {
    if v.is_empty() {
        return;
    }
    let mut g = DESC.lock().unwrap_or_else(|e| e.into_inner());
    g.get_or_insert_with(HashMap::new)
        .insert(k.to_string(), v.to_string());
}

fn desc_get(k: &str) -> String {
    let g = DESC.lock().unwrap_or_else(|e| e.into_inner());
    match g.as_ref().and_then(|m| m.get(k)) {
        Some(v) => v.clone(),
        None => String::new(),
    }
}

fn jq(s: &str) -> String {
    let mut o = String::from("\"");
    for c in s.chars() {
        match c as u32 {
            34 => o.push_str("\\\""),
            92 => o.push_str("\\\\"),
            x if x < 32 => o.push_str(" "),
            _ => o.push(c),
        }
    }
    o.push_str("\"");
    o
}

#[no_mangle]
pub extern "C" fn scene(width: f64) -> usize {
    let guard = DB.lock().unwrap_or_else(|e| e.into_inner());
    let store = match guard.as_ref() {
        Some(s) => s,
        None => return 0,
    };
    let (boxes, frames) = arrange(store, width);
    let mut o = format!("{{\"bw\":{},\"bh\":{},\"f\":[", BOX_W, BOX_H);
    for (i, f) in frames.iter().enumerate() {
        if i > 0 {
            o.push_str(",");
        }
        o.push_str(&format!(
            "{{\"t\":{},\"d\":{},\"x\":{},\"y\":{},\"w\":{},\"h\":{}}}",
            jq(&f.title),
            jq(&desc_get(&format!("l:{}", f.title))),
            f.x, f.y, f.w, f.h
        ));
    }
    o.push_str("],\"c\":[");
    for (i, b) in boxes.iter().enumerate() {
        if i > 0 {
            o.push_str(",");
        }
        let t = if b.title.is_empty() {
            b.key.rsplit("/").next().unwrap_or(&b.key).to_string()
        } else {
            b.title.clone()
        };
        o.push_str(&format!(
            "{{\"k\":{},\"t\":{},\"d\":{},\"x\":{},\"y\":{}}}",
            jq(&b.key),
            jq(&t),
            jq(&desc_get(&format!("k:{}", b.key))),
            b.x, b.y
        ));
    }
    o.push_str("],\"l\":[");
    let mut idx: HashMap<&str, usize> = HashMap::new();
    for (i, b) in boxes.iter().enumerate() {
        idx.insert(b.key.as_str(), i);
    }
    let names = name_map(store);
    let mut first = true;
    for r in store.of_kind("link") {
        let from = match idx.get(r.source.as_str()) {
            Some(i) => *i,
            None => continue,
        };
        let target = r.field("target").unwrap_or("").trim();
        let to = match names.get(target).and_then(|k| idx.get(k.as_str())) {
            Some(i) => *i,
            None => continue,
        };
        if from == to {
            continue;
        }
        let (ax, ay, bx, by) = anchors(&boxes[from], &boxes[to]);
        if !first {
            o.push_str(",");
        }
        first = false;
        o.push_str(&format!("[{},{},{},{}]", ax, ay, bx, by));
    }
    o.push_str("]}");
    let n = o.len();
    *SCENE.lock().unwrap_or_else(|e| e.into_inner()) = o;
    n
}

#[no_mangle]
pub extern "C" fn scene_ptr() -> *const u8 {
    SCENE.lock().unwrap_or_else(|e| e.into_inner()).as_ptr()
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

fn wrap(s: &str) -> Vec<String> {
    let w = 24;
    let mut lines: Vec<String> = Vec::new();
    let mut cur = String::new();
    for word in s.split_whitespace() {
        let mut word: String = word.to_string();
        while word.chars().count() > w {
            if !cur.is_empty() {
                lines.push(cur.clone());
                cur.clear();
            }
            lines.push(word.chars().take(w).collect());
            word = word.chars().skip(w).collect();
        }
        let sep = if cur.is_empty() { 0 } else { 1 };
        if cur.chars().count() + sep + word.chars().count() > w
            && !cur.is_empty()
        {
            lines.push(cur.clone());
            cur.clear();
        }
        if !cur.is_empty() {
            cur.push_str(" ");
        }
        cur.push_str(&word);
    }
    if !cur.is_empty() {
        lines.push(cur);
    }
    if lines.len() > 3 {
        lines.truncate(3);
        let mut l: String = lines[2].chars().take(w - 1).collect();
        l.push_str("…");
        lines[2] = l;
    }
    lines
}

static PICK: Mutex<String> = Mutex::new(String::new());

#[no_mangle]
pub extern "C" fn pick(width: f64, wx: f64, wy: f64) -> i32 {
    let guard = DB.lock().unwrap_or_else(|e| e.into_inner());
    let store = match guard.as_ref() {
        Some(s) => s,
        None => return -1,
    };
    for b in layout(store, width).iter().rev() {
        if wx >= b.x && wx <= b.x + BOX_W
            && wy >= b.y && wy <= b.y + BOX_H
        {
            *PICK.lock().unwrap_or_else(|e| e.into_inner()) = b.key.clone();
            return 1;
        }
    }
    0
}

#[no_mangle]
pub extern "C" fn pick_ptr() -> *const u8 {
    PICK.lock().unwrap_or_else(|e| e.into_inner()).as_ptr()
}

#[no_mangle]
pub extern "C" fn pick_len() -> usize {
    PICK.lock().unwrap_or_else(|e| e.into_inner()).len()
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
    let (boxes, frames) = arrange(store, width);
    unsafe {
        for f in &frames {
            rect(f.x - sx, f.y - sy, f.w, f.h);
            let l = f.title.clone();
            text(l.as_ptr(), l.len(), f.x - sx + 12.0, f.y - sy + 8.0);
        }
    }
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
                let _ = &t;
                let full = if b.title.is_empty() {
                    b.key.rsplit("/").next().unwrap_or(&b.key).to_string()
                } else {
                    b.title.clone()
                };
                for (i, l) in wrap(&full).iter().enumerate() {
                    text(l.as_ptr(), l.len(), b.x - sx + 12.0,
                        b.y - sy + 8.0 + 17.0 * i as f64);
                }
                drawn += 1;
            }
        }
    }
    drawn
}
