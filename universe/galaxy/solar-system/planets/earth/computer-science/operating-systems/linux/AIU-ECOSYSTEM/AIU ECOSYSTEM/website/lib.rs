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
    let mut mw = cfg().pad + cfg().bw + cfg().pad;
    let mut mh = cfg().head + cfg().bh + cfg().pad;
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
            let x = cfg().pad + px * cfg().sx;
            let y = cfg().head + py * cfg().sy;
            if let Some(k) = file {
                placed.insert(k.clone());
                desc_set(&format!("k:{}", k), &it.caption);
                let title = titles.get(&k).cloned().unwrap_or_default();
                cards.push(Boxed { key: k, title, x, y });
                mw = mw.max(x + cfg().bw + cfg().pad);
                mh = mh.max(y + cfg().bh + cfg().pad);
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
                mw = mw.max(x + w + cfg().pad);
                mh = mh.max(y + h + cfg().pad);
            }
        }
    }
    path.pop();
    (cards, frames, mw, mh)
}

fn build_far(
    name: &str,
    groups: &HashMap<String, Vec<Item>>,
    titles: &HashMap<String, String>,
    placed: &mut HashSet<String>,
    path: &mut Vec<String>,
    u: f64,
) -> (Vec<Boxed>, Vec<Frame>, f64, f64) {
    let pad = 8.0 * u;
    let head = 30.0 * u;
    let gap = 8.0 * u;
    let cap = desc_get(&format!("l:{}", name));
    let tpx = name.chars().count() as f64 * 8.0 + 32.0;
    let mut cards: Vec<Boxed> = Vec::new();
    let mut kids: Vec<(f64, f64, String, Vec<Boxed>, Vec<Frame>, f64, f64)> = Vec::new();
    path.push(name.to_string());
    if let Some(items) = groups.get(name) {
        for it in items {
            if it.what == "box" {
                if path.iter().any(|p| p == &it.target)
                    || !groups.contains_key(&it.target)
                {
                    continue;
                }
                desc_set(&format!("l:{}", it.target), &it.caption);
                let (c, f, w, h) =
                    build_far(&it.target, groups, titles, placed, path, u);
                let (px, py) = it.place.unwrap_or((0.0, 0.0));
                kids.push((px, py, it.target.clone(), c, f, w, h));
            } else if let Some(k) = resolve(&it.target, titles) {
                if placed.contains(&k) {
                    continue;
                }
                placed.insert(k.clone());
                desc_set(&format!("k:{}", k), &it.caption);
                let title = titles.get(&k).cloned().unwrap_or_default();
                cards.push(Boxed { key: k, title, x: pad, y: head });
            }
        }
    }
    path.pop();
    let mut frames: Vec<Frame> = Vec::new();
    if kids.is_empty() {
        let clen = cap.chars().count() as f64;
        let wpx = if clen > 0.0 { tpx.max(200.0) } else { tpx.max(110.0) };
        let lines = if clen > 0.0 {
            (clen * 6.5 / (wpx - 32.0)).ceil().min(6.0)
        } else {
            0.0
        };
        let extra = if lines > 0.0 { lines * 16.0 + 6.0 } else { 0.0 };
        let hpx = (30.0 + extra + 8.0).max(44.0);
        return (cards, frames, wpx * u, hpx * u);
    }
    let mut cells: Vec<(i64, i64, String, Vec<Boxed>, Vec<Frame>, f64, f64)> = Vec::new();
    let mut taken: HashSet<(i64, i64)> = HashSet::new();
    for (px, py, t, c, f, w, h) in kids {
        let mut gx = (px.round() as i64).max(0);
        let gy = (py.round() as i64).max(0);
        let mut guard = 0;
        while taken.contains(&(gx, gy)) && guard < 1000 {
            gx += 1;
            guard += 1;
        }
        taken.insert((gx, gy));
        cells.push((gx, gy, t, c, f, w, h));
    }
    let mut xs: Vec<i64> = cells.iter().map(|k| k.0).collect();
    xs.sort();
    xs.dedup();
    let mut ys: Vec<i64> = cells.iter().map(|k| k.1).collect();
    ys.sort();
    ys.dedup();
    let mut cw = vec![0.0_f64; xs.len()];
    let mut rh = vec![0.0_f64; ys.len()];
    for k in &cells {
        let i = xs.iter().position(|v| *v == k.0).unwrap_or(0);
        let j = ys.iter().position(|v| *v == k.1).unwrap_or(0);
        cw[i] = cw[i].max(k.5);
        rh[j] = rh[j].max(k.6);
    }
    let mut cx: Vec<f64> = Vec::new();
    let mut a = pad;
    for w in &cw {
        cx.push(a);
        a += w + gap;
    }
    let tot_w = a - gap + pad;
    let mut cy: Vec<f64> = Vec::new();
    let mut b = head;
    for h in &rh {
        cy.push(b);
        b += h + gap;
    }
    let tot_h = b - gap + pad;
    for (gx, gy, t, c, f, w, h) in cells {
        let i = xs.iter().position(|v| *v == gx).unwrap_or(0);
        let j = ys.iter().position(|v| *v == gy).unwrap_or(0);
        let x = cx[i];
        let y = cy[j];
        frames.push(Frame { title: t, x, y, w, h });
        for mut bb in c {
            bb.x += x;
            bb.y += y;
            cards.push(bb);
        }
        for mut g in f {
            g.x += x;
            g.y += y;
            frames.push(g);
        }
    }
    (cards, frames, tot_w.max(tpx * u), tot_h)
}

fn arrange(store: &Store, width: f64) -> (Vec<Boxed>, Vec<Frame>) {
    set_cfg(store);
    let width = if far_z() > 0.0 { width / far_z() } else { width };
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
    let mut sx = cfg().gap;
    let mut sy = cfg().gap;
    let mut rowh: f64 = 0.0;
    let mut any = false;
    for name in &names {
        if nested.contains(name) {
            continue;
        }
        let mut path: Vec<String> = Vec::new();
        let (c, f, w, h) = if far_z() > 0.0 {
            build_far(name, &groups, &titles, &mut placed, &mut path, 1.0 / far_z())
        } else {
            build(name, &groups, &titles, &mut placed, &mut path)
        };
        if sx > cfg().gap && sx + w > width {
            sx = cfg().gap;
            sy += rowh + cfg().gap;
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
        sx += w + cfg().gap;
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
    for r in &files {
        if skip.contains(&r.key) || !r.key.starts_with(scope_get().as_str()) {
            continue;
        }
        let title = r.field("title").unwrap_or("").to_string();
        loose.push((r.key.clone(), title));
    }
    let cols = (((width - cfg().gap) / cfg().sx) as usize).max(1);
    let first = 0.0_f64;
    for (i, (key, title)) in loose.into_iter().enumerate() {
        let col = (i % cols) as f64;
        let row = first + (i / cols) as f64;
        out.push(Boxed {
            key,
            title,
            x: cfg().gap + col * cfg().sx,
            y: cfg().gap + row * cfg().sy + top,
        });
    }
    out
}

const SCOPE_DEFAULT: &str = "demo/";
static SCOPE_V: Mutex<String> = Mutex::new(String::new());

fn scope_get() -> String {
    SCOPE_V.lock().unwrap_or_else(|e| e.into_inner()).clone()
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
    let mut o = format!("{{\"bw\":{},\"bh\":{},\"f\":[", cfg().bw, cfg().bh);
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
        o.push_str(&format!("[{},{},{},{},{},{}]", ax, ay, bx, by, from, to));
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
        if wx >= b.x && wx <= b.x + cfg().bw
            && wy >= b.y && wy <= b.y + cfg().bh
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
            (a.x + cfg().bw, a.y + cfg().bh / 2.0, b.x, b.y + cfg().bh / 2.0)
        } else {
            (a.x, a.y + cfg().bh / 2.0, b.x + cfg().bw, b.y + cfg().bh / 2.0)
        }
    } else if dy >= 0.0 {
        (a.x + cfg().bw / 2.0, a.y + cfg().bh, b.x + cfg().bw / 2.0, b.y)
    } else {
        (a.x + cfg().bw / 2.0, a.y, b.x + cfg().bw / 2.0, b.y + cfg().bh)
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
        x + w >= sx - cfg().margin && x <= sx + width + cfg().margin && y + h >= sy - cfg().margin && y <= sy + height + cfg().margin
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
            if seen(b.x, b.y, cfg().bw, cfg().bh) {
                rect(b.x - sx, b.y - sy, cfg().bw, cfg().bh);
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

#[derive(Clone, Copy)]
struct Cfg {
    bw: f64,
    bh: f64,
    gap: f64,
    sx: f64,
    sy: f64,
    margin: f64,
    pad: f64,
    head: f64,
    curve: f64,
    pv: f64,
    ph: f64,
    ts: f64,
    ds: f64,
    ls: f64,
    zc: f64,
    zb: f64,
    ze: f64,
    zw: f64,
}

static CFG: Mutex<Option<Cfg>> = Mutex::new(None);

fn cfg_default() -> Cfg {
    Cfg {
        bw: BOX_W,
        bh: BOX_H,
        gap: GAP,
        sx: STEP_X,
        sy: STEP_Y,
        margin: MARGIN,
        pad: PAD,
        head: HEAD,
        curve: 0.5,
        pv: 10.0,
        ph: 12.0,
        ts: 15.0,
        ds: 12.0,
        ls: 13.0,
        zc: 50.0,
        zb: 30.0,
        ze: 16.0,
        zw: 6.0,
    }
}

static FAR: Mutex<f64> = Mutex::new(0.0);

fn far_z() -> f64 {
    *FAR.lock().unwrap_or_else(|e| e.into_inner())
}

#[no_mangle]
pub extern "C" fn set_far(z: f64) {
    *FAR.lock().unwrap_or_else(|e| e.into_inner()) = z;
}

fn cfg() -> Cfg {
    let mut c = cfg_base();
    let z = far_z();
    if z > 0.0 {
        c.gap = 10.0 / z;
    }
    c
}

fn cfg_base() -> Cfg {
    let g = CFG.lock().unwrap_or_else(|e| e.into_inner());
    match *g {
        Some(c) => c,
        None => cfg_default(),
    }
}

fn set_cfg(store: &Store) {
    let mut c = cfg_default();
    let recs = store.of_kind("layout-item");
    let mut scope = String::from(SCOPE_DEFAULT);
    let mut ord: Vec<(String, i64, usize)> = Vec::new();
    for (i, r) in recs.iter().enumerate() {
        if r.field("what") == Some("settings") {
            let ln = r
                .field("line")
                .and_then(|s| s.parse::<i64>().ok())
                .unwrap_or(0);
            ord.push((r.source.clone(), ln, i));
        }
    }
    ord.sort();
    for (_, _, i) in ord {
        let r = &recs[i];
        let num = |k: &str| {
            r.field(k)
                .and_then(|s| s.trim().parse::<f64>().ok())
                .filter(|v| *v > 0.0)
        };
        if let Some(v) = num("width") { c.bw = v; }
        if let Some(v) = num("height") { c.bh = v; }
        if let Some(v) = num("gap") { c.gap = v; }
        if let Some(v) = num("stepx") { c.sx = v; }
        if let Some(v) = num("stepy") { c.sy = v; }
        if let Some(v) = num("margin") { c.margin = v; }
        if let Some(v) = num("pad") { c.pad = v; }
        if let Some(v) = num("head") { c.head = v; }
        if let Some(v) = num("padv") { c.pv = v; }
        if let Some(v) = num("padh") { c.ph = v; }
        if let Some(v) = num("titlesize") { c.ts = v; }
        if let Some(v) = num("descsize") { c.ds = v; }
        if let Some(v) = num("labelsize") { c.ls = v; }
        if let Some(v) = num("zoomcut") { if v <= 100.0 { c.zc = v; } }
        if let Some(v) = num("zoomband") { if v >= 5.0 && v <= 90.0 { c.zb = v; } }
        if let Some(v) = num("zoomease") { if v >= 2.0 && v <= 100.0 { c.ze = v; } }
        if let Some(v) = num("zoomwheel") { if v >= 1.0 && v <= 100.0 { c.zw = v; } }
        let sc = r.field("scope").unwrap_or("").trim();
        if sc == "all" {
            scope = String::new();
        } else if !sc.is_empty() {
            scope = sc.to_string();
        }
        if let Some(v) = num("curve") {
            if v <= 1.0 { c.curve = v; }
        }
    }
    *SCOPE_V.lock().unwrap_or_else(|e| e.into_inner()) = scope;
    *CFG.lock().unwrap_or_else(|e| e.into_inner()) = Some(c);
}

#[no_mangle]
pub extern "C" fn curve() -> f64 {
    cfg().curve
}

#[no_mangle]
pub extern "C" fn style(i: i32) -> f64 {
    let c = cfg();
    match i {
        0 => c.pv,
        1 => c.ph,
        2 => c.ts,
        3 => c.ds,
        4 => c.ls,
        5 => c.zc / 100.0,
        6 => c.head,
        7 => c.zb / 100.0,
        8 => c.ze / 100.0,
        9 => c.zw / 10000.0,
        _ => 0.0,
    }
}
