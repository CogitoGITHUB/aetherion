//! One job: the boxed `view` command, the page drawn as nested boxes with each contract on the block it judges.
//! Walks the tree the Rust parser already built; the older line drawing stays in view.rs and is chosen with --flat.
use notation::buffer::Buffer;
use notation::parser::{parse, Block, ErrorKind, Node};

/// One drawn line: its text with colour codes, the columns it shows, and whether it is a divider inside a box.
struct L {
    s: String,
    n: usize,
    sep: bool,
}

/// One contract of a file type, as contracts.dat holds it; for a question, arg is the question text.
struct Contract {
    rule: bool,
    section: String,
    block: String,
    name: String,
    arg: String,
    id: String,
}

/// The page being drawn, with the contracts of its type and the running counts.
struct Boxes {
    text: String,
    lines: Vec<String>,
    starts: Vec<usize>,
    width: usize,
    plain: bool,
    counters: [u32; 12],
    seen_title: bool,
    problems: Vec<String>,
    cs: Vec<Contract>,
    ok: usize,
    broken: usize,
    open: usize,
    unchecked: usize,
}

/// The colour codes a block may ask for with a color: line.
fn color_code(name: &str) -> Option<u32> {
    match name.to_lowercase().as_str() {
        "red" => Some(31), "green" => Some(32), "yellow" => Some(33), "blue" => Some(34),
        "magenta" => Some(35), "cyan" => Some(36), "white" => Some(37),
        "gray" | "grey" => Some(90), _ => None,
    }
}

/// The value of one declaration of a block, if it has it.
fn decl(b: &Block, key: &str) -> Option<String> {
    b.declarations.iter().find(|d| d.keyword == key).map(|d| d.value.clone())
}

/// Break text into lines of at most w characters, at spaces.
fn wrap(text: &str, w: usize) -> Vec<String> {
    let w = w.max(1);
    let mut acc: Vec<String> = Vec::new();
    let mut cur = String::new();
    for word in text.split_whitespace() {
        if cur.is_empty() {
            cur = word.to_string();
        } else if cur.chars().count() + 1 + word.chars().count() <= w {
            cur.push_str(" ");
            cur.push_str(word);
        } else {
            acc.push(cur);
            cur = word.to_string();
        }
    }
    if !cur.is_empty() {
        acc.push(cur);
    }
    acc
}

/// Join body lines into paragraphs; a blank line starts a new one.
fn groups(lines: &[String]) -> Vec<String> {
    let mut acc: Vec<String> = Vec::new();
    let mut cur: Vec<String> = Vec::new();
    for l in lines {
        if l.trim().is_empty() {
            if !cur.is_empty() {
                acc.push(cur.join(" "));
                cur.clear();
            }
        } else {
            cur.push(l.trim().to_string());
        }
    }
    if !cur.is_empty() {
        acc.push(cur.join(" "));
    }
    acc
}

/// Cut a string to at most n columns, ending in an ellipsis when it was cut.
fn clip(s: &str, n: usize) -> String {
    if s.chars().count() <= n {
        return s.to_string();
    }
    if n == 0 {
        return String::new();
    }
    let mut t: String = s.chars().take(n - 1).collect();
    t.push_str("…");
    t
}

/// Title lettering: capitals with a space between letters and three between words.
fn big(s: &str) -> String {
    s.to_uppercase().split_whitespace().map(|w| w.chars().map(|c| c.to_string()).collect::<Vec<_>>().join(" ")).collect::<Vec<_>>().join("   ")
}

/// A divider line inside a box.
fn divider() -> L {
    L { s: String::new(), n: 0, sep: true }
}

/// The contracts of one file type, read from contracts.dat in the target folder; None when the file is missing.
fn load_contracts(kind: &str) -> Option<Vec<Contract>> {
    let mut cands: Vec<std::path::PathBuf> = Vec::new();
    if let Ok(p) = std::env::var("AIU_CONTRACTS") { cands.push(p.into()); }
    let mut exes: Vec<std::path::PathBuf> = Vec::new();
    if let Some(a) = std::env::args().next() { exes.push(a.into()); }
    if let Ok(b) = std::env::var("AIU_NOTATION_BIN") { exes.push(b.into()); }
    if let Ok(e) = std::env::current_exe() { exes.push(e); }
    for e in exes {
        for d in e.ancestors().skip(1).take(4) {
            cands.push(d.join("contracts.dat"));
        }
    }
    let path = cands.into_iter().find(|p| p.exists())?;
    let text = std::fs::read_to_string(path).ok()?;
    let mut res: Vec<Contract> = Vec::new();
    for l in text.lines() {
        let f: Vec<&str> = l.split("\t").collect();
        if f.len() < 5 || f[0] != kind {
            continue;
        }
        let rule = f[1] == "rule";
        res.push(Contract {
            rule,
            section: f[2].to_string(),
            block: f[3].to_string(),
            name: if rule { f[4].to_string() } else { String::new() },
            arg: if rule { f.get(5).unwrap_or(&"").to_string() } else { f[4].to_string() },
            id: if rule { String::new() } else { f.get(5).unwrap_or(&"").to_string() },
        });
    }
    Some(res)
}

/// The drawing methods of the boxed view.
impl Boxes {
    /// The 1-based line a byte offset falls on.
    fn line_of(&self, byte: usize) -> usize {
        self.starts.partition_point(|&s| s <= byte)
    }

    /// The line a block end marker is on.
    fn end_line(&self, b: &Block) -> usize {
        let e = b.span.end.saturating_sub(1).min(self.text.len().saturating_sub(1));
        self.line_of(e)
    }

    /// The text lines of a block: not its markers, declarations or child blocks.
    fn body(&self, b: &Block) -> Vec<String> {
        let s = self.line_of(b.span.start);
        let e = self.end_line(b);
        let mut kids: Vec<(usize, usize)> = Vec::new();
        for n in &b.children {
            if let Node::Block(c) = n {
                kids.push((self.line_of(c.span.start), self.end_line(c)));
            }
        }
        let mut res: Vec<String> = Vec::new();
        let mut ln = s + 1 + b.declarations.len();
        while ln < e {
            if !kids.iter().any(|&(a, z)| ln >= a && ln <= z) {
                res.push(self.lines.get(ln - 1).cloned().unwrap_or_default());
            }
            ln += 1;
        }
        res
    }

    /// A block body as one line of text, used for titles.
    fn text_of(&self, b: &Block) -> String {
        let v: Vec<String> = self.body(b).iter().map(|l| l.trim().to_string()).filter(|l| !l.is_empty()).collect();
        v.join(" ")
    }

    /// Colour the text with ANSI codes, unless plain.
    fn sgr_todo(&self, codes: &[u32], s: &str) -> String {
        if self.plain || codes.is_empty() || s.is_empty() {
            return s.to_string();
        }
        let c: Vec<String> = codes.iter().map(|n| n.to_string()).collect();
        format!("\x1b[{}m{}\x1b[0m", c.join(";"), s)
    }

    /// Style the text with ANSI codes, never a colour: only the todo box keeps red.
    fn sgr(&self, codes: &[u32], s: &str) -> String {
        let kept: Vec<u32> = codes.iter().copied().filter(|n| *n < 30).collect();
        let codes = &kept[..];
        if self.plain || codes.is_empty() || s.is_empty() {
            return s.to_string();
        }
        let c: Vec<String> = codes.iter().map(|n| n.to_string()).collect();
        format!("\x1b[{}m{}\x1b[0m", c.join(";"), s)
    }

    /// The style and colour codes a block asks for.
    fn style(&self, b: &Block) -> Vec<u32> {
        let mut v: Vec<u32> = Vec::new();
        let st = decl(b, "style").unwrap_or_default();
        for t in st.split_whitespace() {
            match t { "bold" => v.push(1), "dim" => v.push(2), "italic" => v.push(3), "underline" => v.push(4), _ => {} }
        }
        if let Some(c) = decl(b, "color").and_then(|c| color_code(&c)) {
            v.push(c);
        }
        v
    }

    /// One line of text with its colour codes.
    fn line(&self, codes: &[u32], s: &str) -> L {
        L { s: self.sgr(codes, s), n: s.chars().count(), sep: false }
    }

    /// Text wrapped and clipped to the width, one drawn line each.
    fn wrapped(&self, codes: &[u32], text: &str, w: usize) -> Vec<L> {
        wrap(text, w).iter().map(|l| self.line(codes, &clip(l, w))).collect()
    }

    /// One contract row wrapped to the width, the marker on its first line.
    fn row(&self, mark: &str, codes: &[u32], text: &str, w: usize) -> Vec<L> {
        let mut res: Vec<L> = Vec::new();
        let room = w.saturating_sub(2).max(8);
        for (k, l) in wrap(text, room).iter().enumerate() {
            let lead = if k == 0 { mark } else { "  " };
            let mut x = self.line(codes, &format!("{}{}", lead, clip(l, room)));
            x.s.push_str(&" ".repeat(w.saturating_sub(x.n)));
            x.n = w.max(x.n);
            res.push(x);
        }
        res
    }

    /// Draw a box of the given total width around the inner lines, with the label in its top edge.
    fn frame(&self, label: &str, tcodes: &[u32], inner: Vec<L>, w: usize, heavy: bool, center: bool) -> Vec<L> {
        let (tl, tr, bl, br, h, v, ml, mr) = if heavy {
            ("╔", "╗", "╚", "╝", "═", "║", "╠", "╣")
        } else {
            ("╭", "╮", "╰", "╯", "─", "│", "├", "┤")
        };
        let w = w.max(10);
        let lab = clip(label, w - 6);
        let fill = w - lab.chars().count() - 4;
        let (dl, dr) = (1, fill - 1);
        let mut res: Vec<L> = Vec::new();
        let top = format!("{}{}{}{}",
            self.sgr(&[2], &format!("{}{} ", tl, h.repeat(dl))), self.sgr(tcodes, &lab),
            self.sgr(&[2], &format!(" {}", h.repeat(dr))), self.sgr(&[2], tr));
        res.push(L { s: top, n: w, sep: false });
        for l in inner {
            if l.sep {
                let s = self.sgr(&[2], &format!("{}{}{}", ml, h.repeat(w - 2), mr));
                res.push(L { s, n: w, sep: false });
            } else {
                let room = (w - 4).saturating_sub(l.n);
                let (lp, rp) = if center { (room / 2, room - room / 2) } else { (0, room) };
                let s = format!("{}{}{}{}{}", self.sgr(&[2], &format!("{} ", v)), " ".repeat(lp), l.s, " ".repeat(rp), self.sgr(&[2], &format!(" {}", v)));
                res.push(L { s, n: w, sep: false });
            }
        }
        let bottom = self.sgr(&[2], &format!("{}{}{}", bl, h.repeat(w - 2), br));
        res.push(L { s: bottom, n: w, sep: false });
        res
    }

    /// Collect the block kind and section title of every block, in page order, as the contracts see them.
    fn collect(&self, ns: &[Node], sec: &str, acc: &mut Vec<(String, String)>) {
        for n in ns {
            if let Node::Block(b) = n {
                if b.name == "section" {
                    let t = b.children.iter().find_map(|c| match c { Node::Block(t) if t.name == "title" => Some(t), _ => None });
                    let title = t.map(|t| self.text_of(t)).unwrap_or_default();
                    self.collect(&b.children, &title, acc);
                } else {
                    acc.push((b.name.clone(), sec.to_string()));
                }
            }
        }
    }

    /// How a block breaks a rule, or None when it keeps it.
    fn rule_failure(&self, b: &Block, c: &Contract) -> Option<String> {
        let ls = self.body(b);
        let words = ls.join(" ").split_whitespace().count();
        let n: usize = c.arg.parse().unwrap_or(0);
        match c.name.as_str() {
            "max-words" => (words > n).then(|| format!("has {} words, the most allowed is {}", words, n)),
            "min-words" => (words < n).then(|| format!("has {} words, the least allowed is {}", words, n)),
            "max-lines" => (ls.len() > n).then(|| format!("has {} lines, the most allowed is {}", ls.len(), n)),
            "needs-declaration" => decl(b, &c.arg).is_none().then(|| format!("has no {}: declaration", c.arg)),
            _ => None,
        }
    }

    /// The contract rows under one block: broken rules, then open questions, then rules that hold.
    fn rows(&mut self, b: &Block, sec: &str, w: usize, tag: &str) -> Vec<L> {
        if self.cs.is_empty() {
            return Vec::new();
        }
        let cs = std::mem::take(&mut self.cs);
        let mut bad: Vec<L> = Vec::new();
        let mut ask: Vec<L> = Vec::new();
        let mut qn = 0u32;
        let mut good: Vec<L> = Vec::new();
        for c in &cs {
            if c.block != b.name || !(c.section == "*" || c.section == sec) {
                continue;
            }
            if c.rule {
                if c.name == "must-match" || c.name == "must-not-match" {
                    good.extend(self.row("- ", &[2, 33], &format!("{}not checked here: {} {} (run aiu check)", tag, c.name, c.arg), w));
                    self.unchecked += 1;
                } else if let Some(why) = self.rule_failure(b, c) {
                    bad.extend(self.row("✘ ", &[1, 31], &format!("{}RULE BROKEN, line {}: {} ({} {})", tag, b.line, why, c.name, c.arg), w));
                    self.broken += 1;
                } else {
                    good.extend(self.row("✔ ", &[32], &format!("{}holds: {} {}", tag, c.name, c.arg), w));
                    self.ok += 1;
                }
            } else {
                qn += 1;
                ask.extend(self.row("? ", &[33], &format!("{}Q{}: {}", tag, qn, c.arg), w));
                let ans = b.children.iter().find_map(|k| match k {
                    Node::Block(a) if a.name == "answer" && !c.id.is_empty() && decl(a, "for").as_deref() == Some(c.id.as_str()) => Some(a),
                    _ => None,
                }).filter(|a| !self.text_of(a).is_empty());
                ask.extend(self.row("  ", &[2], &"┄".repeat(w.saturating_sub(8).max(4)), w));
                match ans {
                    Some(a) => {
                        let saved = decl(a, "asked").unwrap_or_default();
                        if !saved.is_empty() && saved != c.arg {
                            ask.extend(self.row("≠ ", &[1, 33], &format!("STALE: the question changed. This answer was for: {}", saved), w));
                        }
                        let t = self.text_of(a);
                        ask.extend(self.row("✔ ", &[32], &t, w));
                        self.ok += 1;
                    }
                    None => {
                        ask.extend(self.row("… ", &[2], "no answer yet", w));
                        self.open += 1;
                    }
                }
            }
        }
        self.cs = cs;
        bad.extend(ask);
        bad.extend(good);
        bad
    }

    /// Draw a run of nodes as stacked boxes; the node that starts at byte skip is left out.
    fn nodes(&mut self, ns: &[Node], skip: usize, sec: &str, depth: usize, width: usize) -> Vec<L> {
        let mut out: Vec<L> = Vec::new();
        for n in ns {
            match n {
                Node::Block(b) => {
                    if b.span.start == skip || b.name == "answer" {
                        continue;
                    }
                    let mut one = self.draw(b, sec, depth, width);
                    if depth == 0 && !out.is_empty() {
                        out.push(self.line(&[], ""));
                    }
                    out.append(&mut one);
                }
                Node::Error(e) => {
                    if e.kind == ErrorKind::StrayText {
                        out.push(self.line(&[1, 31], &clip(&format!("! stray text (outside any block): {}", e.what), width)));
                    } else {
                        self.problems.push(format!("line {}: {}", e.line, e.what));
                    }
                }
            }
        }
        out
    }

    /// Draw a section as a box holding its title rows, then its blocks, each in a box of its own.
    fn section(&mut self, b: &Block, depth: usize, width: usize) -> Vec<L> {
        let d = (depth + 1).min(11);
        self.counters[d] += 1;
        for k in d + 1..12 {
            self.counters[k] = 0;
        }
        let num: Vec<String> = (1..=d).map(|k| self.counters[k].to_string()).collect();
        let num = num.join(".");
        let title = b.children.iter().find_map(|n| match n { Node::Block(c) if c.name == "title" => Some(c), _ => None });
        let iw = width.saturating_sub(4);
        let mut head: Vec<L> = Vec::new();
        let mut skip = usize::MAX;
        let mut ttext = "(untitled section)".to_string();
        let mut codes: Vec<u32> = match d { 1 => vec![1, 36], 2 => vec![1, 34], _ => vec![1] };
        match title {
            Some(t) => {
                skip = t.span.start;
                ttext = self.text_of(t);
                codes.extend(self.style(t));
                let first = b.children.iter().find_map(|n| if let Node::Block(c) = n { Some(c) } else { None });
                if first.map_or(true, |f| f.span.start != t.span.start) {
                    let l = self.line_of(t.span.start);
                    self.problems.push(format!("line {}: a section title must be its first block", l));
                }
                head = self.rows(t, &ttext, iw, "title: ");
            }
            None => {
                let l = self.line_of(b.span.start);
                self.problems.push(format!("line {}: section has no title block", l));
            }
        }
        let kids = self.nodes(&b.children, skip, &ttext, d, iw);
        let mut inner: Vec<L> = Vec::new();
        let has_head = !head.is_empty();
        inner.extend(head);
        if has_head && !kids.is_empty() {
            inner.push(divider());
        }
        inner.extend(kids);
        if inner.is_empty() {
            inner.push(self.line(&[], ""));
        }
        self.frame(&format!("section {} · {}", num, ttext), &codes, inner, width, false, true)
    }

    /// Draw one block as a box, with its contract rows under it when contracts are shown.
    fn draw(&mut self, b: &Block, sec: &str, depth: usize, width: usize) -> Vec<L> {
        let todo = decl(b, "todo");
        let iw = width.saturating_sub(4);
        let mut inner: Vec<L> = Vec::new();
        let mut label = b.name.clone();
        let mut tcodes: Vec<u32> = vec![1];
        match b.name.as_str() {
            "section" => return self.section(b, depth, width),
            "title" => {
                let text = self.text_of(b);
                let mut codes: Vec<u32> = vec![1, 33];
                codes.extend(self.style(b));
                let first = depth == 0 && !self.seen_title;
                let tl: Vec<String> = if first { wrap(&text, (iw / 2).saturating_sub(2)).iter().map(|l| big(l)).collect() } else { wrap(&text, iw) };
                if first { inner.push(self.line(&[], "")); }
                for l in tl { inner.push(self.line(&codes, &clip(&l, iw))); }
                if first { inner.push(self.line(&[], "")); }
                if depth == 0 && !self.seen_title {
                    self.seen_title = true;
                    if let Some(k) = decl(b, "kind").filter(|k| !k.is_empty()) {
                        inner.push(self.line(&[1, 36], &clip(&format!("kind: {}", k), iw)));
                    }
                    if let Some(t) = decl(b, "tags").filter(|t| !t.is_empty()) {
                        inner.push(self.line(&[2], &clip(&format!("tags: {}", t), iw)));
                    }
                }
            }
            "paragraph" | "comment" => {
                let mut codes = self.style(b);
                if b.name == "comment" {
                    codes = vec![2, 33];
                    tcodes = vec![2, 33];
                    let n = b.children.iter().filter(|c| matches!(c, Node::Block(_))).count();
                    label = if n == 0 { "comment".to_string() } else { format!("comment · on {} block{}", n, if n == 1 { "" } else { "s" }) };
                }
                for (k, g) in groups(&self.body(b)).iter().enumerate() {
                    if k > 0 {
                        inner.push(self.line(&[], ""));
                    }
                    inner.extend(self.wrapped(&codes, g, iw));
                }
            }
            "code" => {
                let lang = decl(b, "language").unwrap_or_default();
                label = if lang.is_empty() { "code".to_string() } else { format!("code · {}", lang) };
                let mut body = self.body(b);
                while body.first().map_or(false, |l| l.trim().is_empty()) { body.remove(0); }
                while body.last().map_or(false, |l| l.trim().is_empty()) { body.pop(); }
                for l in body {
                    inner.push(self.line(&[32], &clip(&l.replace("\t", "    "), iw)));
                }
            }
            "heading" => {
                let t = self.text_of(b);
                inner.extend(self.wrapped(&[1, 36], &t, iw));
            }
            other => {
                label = format!("unknown block: {}", other);
                tcodes = vec![2, 33];
                for g in groups(&self.body(b)) {
                    inner.extend(self.wrapped(&[], &g, iw));
                }
            }
        }
        if b.children.iter().any(|n| matches!(n, Node::Block(_))) {
            let kids = self.nodes(&b.children, usize::MAX, sec, depth + 1, iw);
            if !kids.is_empty() {
                if !inner.is_empty() {
                    inner.push(self.line(&[], ""));
                }
                inner.extend(kids);
            }
        }
        if inner.is_empty() {
            inner.push(self.line(&[], ""));
        }
        let rows = self.rows(b, sec, iw, "");
        if !rows.is_empty() {
            inner.push(divider());
            inner.extend(rows);
        }
        let center = b.name != "code";
        match todo {
            Some(v) => self.todo_side(&label, &tcodes, inner, width, center, &v),
            None => self.frame(&label, &tcodes, inner, width, false, center),
        }
    }

    /// Draw a block box with TODO or DONE in its top-right corner and, when there is a description, a tray hung on its bottom edge.
    fn todo_side(&self, label: &str, tcodes: &[u32], inner: Vec<L>, width: usize, center: bool, v: &str) -> Vec<L> {
        let t = v.trim();
        let (first, rest) = match t.split_once(" ") { Some((x, y)) => (x, y.trim()), None => (t, "") };
        let (done, desc) = if first == "done" { (true, rest) } else if first == "open" { (false, rest) } else { (false, t) };
        let badge = if done { "DONE" } else { "TODO" };
        let red: Vec<u32> = if done { vec![] } else { vec![31] };
        let w = width.max(10);
        let mut framed = self.frame(label, tcodes, inner, width, false, center);
        let lab = clip(label, w.saturating_sub(badge.len() + 12));
        let fill = w.saturating_sub(lab.chars().count() + badge.len() + 8);
        let top = format!("{}{}{}{}{}",
            self.sgr(&[2], "╭─ "), self.sgr(tcodes, &lab),
            self.sgr(&[2], &format!(" {} ", "─".repeat(fill))), self.sgr_todo(&[&[1u32][..], &red[..]].concat(), badge), self.sgr(&[2], " ─╮"));
        framed[0] = L { s: top, n: w, sep: false };
        if desc.is_empty() {
            return framed;
        }
        framed.pop();
        let mut out = framed;
        let lab2 = format!(" {} ", if done { "DONE" } else { "TODO · open" });
        let fill2 = w.saturating_sub(3 + lab2.chars().count());
        out.push(L { s: self.sgr_todo(&red, &format!("╰─{}{}╯", lab2, "─".repeat(fill2))), n: w, sep: false });
        let tw = w.saturating_sub(4).max(4);
        let mut rows = wrap(desc, tw);
        if rows.is_empty() { rows.push(String::new()); }
        for r in rows {
            let r = clip(&r, tw);
            let pad = tw.saturating_sub(r.chars().count());
            out.push(L { s: format!("{} {}{} {}", self.sgr_todo(&red, "│"), self.sgr_todo(&red, &r), " ".repeat(pad), self.sgr_todo(&red, "│")), n: w, sep: false });
        }
        out.push(L { s: self.sgr_todo(&red, &format!("╰{}╯", "─".repeat(w.saturating_sub(2)))), n: w, sep: false });
        out
    }
}

/// The page drawn as boxes for a terminal of the given width, with colour unless plain and contracts on their blocks when asked.
pub fn render_boxes(text: &str, width: usize, plain: bool, contracts: bool) -> String {
    let tree = parse(&Buffer::from_text(text));
    let mut starts = vec![0usize];
    for (i, _) in text.match_indices("\n") {
        starts.push(i + 1);
    }
    let kind: Option<String> = tree.nodes.iter()
        .find_map(|n| match n { Node::Block(b) if b.name == "title" => Some(b), _ => None })
        .and_then(|t| decl(t, "kind"))
        .and_then(|k| k.split_whitespace().next().map(|s| s.to_string()));
    let mut cs: Vec<Contract> = Vec::new();
    let mut note: Option<String> = None;
    if contracts {
        match &kind {
            None => note = Some("no kind: line, so no contract applies".to_string()),
            Some(k) => match load_contracts(k) {
                None => note = Some("no contract data: run aiu see FILE --contracts once to write it".to_string()),
                Some(c) => {
                    if c.is_empty() {
                        note = Some(format!("no contracts apply to the kind {}", k));
                    } else {
                        cs = c;
                    }
                }
            },
        }
    }
    let mut v = Boxes {
        text: text.to_string(),
        lines: text.split("\n").map(|l| l.to_string()).collect(),
        starts,
        width: width.saturating_sub(2).max(24),
        plain,
        counters: [0; 12],
        seen_title: false,
        problems: Vec::new(),
        cs,
        ok: 0,
        broken: 0,
        open: 0,
        unchecked: 0,
    };
    let mut present: Vec<(String, String)> = Vec::new();
    v.collect(&tree.nodes, "", &mut present);
    let wd = v.width;
    let page = v.nodes(&tree.nodes, usize::MAX, "", 0, wd);
    let has_title = tree.nodes.iter().any(|n| matches!(n, Node::Block(b) if b.name == "title"));
    if !has_title {
        v.problems.push("line 1: the file has no title block".to_string());
    }
    let cs = std::mem::take(&mut v.cs);
    let mut out = String::new();
    if contracts {
        let missing: Vec<&Contract> = cs.iter()
            .filter(|c| c.section != "*" && !present.iter().any(|(n, s)| *n == c.block && (c.section == "*" || *s == c.section)))
            .collect();
        let iw = wd.saturating_sub(4);
        let mut inner: Vec<L> = Vec::new();
        if let Some(n) = &note {
            inner.extend(v.wrapped(&[2], n, iw));
        } else {
            let head = format!("rules broken: {} · open questions: {} · holding: {} · missing: {}", v.broken, v.open, v.ok, missing.len());
            let codes: Vec<u32> = if v.broken > 0 { vec![1, 31] } else { vec![1, 32] };
            inner.extend(v.wrapped(&codes, &head, iw));
            if v.unchecked > 0 {
                inner.extend(v.wrapped(&[2, 33], &format!("not checked by view: {} (run aiu check)", v.unchecked), iw));
            }
            if !missing.is_empty() {
                inner.push(divider());
                for c in &missing {
                    let wh = if c.section == "*" { "any section".to_string() } else { format!("section {}", c.section) };
                    let t = if c.rule { format!("{} {}", c.name, c.arg) } else { c.arg.clone() };
                    inner.extend(v.row("- ", &[2], &format!("missing: {} in {}: {}", c.block, wh, t), iw));
                }
            }
        }
        let label = match &kind { Some(k) => format!("CONTRACTS · {}", k), None => "CONTRACTS".to_string() };
        for l in v.frame(&label, &[1, 36], inner, wd, true, true) {
            out.push_str(&l.s);
            out.push_str("\n");
        }
        out.push_str("\n");
    }
    for l in &page {
        out.push_str(&l.s);
        out.push_str("\n");
    }
    if !v.problems.is_empty() {
        let n = v.problems.len();
        out.push_str(&format!("\n{}\n", v.sgr(&[1, 31], &format!("{} problem{} found:", n, if n == 1 { "" } else { "s" }))));
        for p in &v.problems {
            out.push_str(&format!("{}\n", v.sgr(&[31], &format!("  {}", p))));
        }
        out.push_str(&format!("{}\n", v.sgr(&[2], "run: aiu check FILE   for the full check")));
    }
    out
}

/// The drawing methods that find the answer slots a page lacks.
impl Boxes {
    /// Walk the blocks, collect the answer slots to add, and note stale and retired answers.
    fn fill_walk(&self, ns: &[Node], sec: &str, add: &mut Vec<(usize, String)>, rep: &mut Vec<String>) {
        for n in ns {
            if let Node::Block(b) = n {
                if b.name == "section" {
                    let t = b.children.iter().find_map(|c| match c { Node::Block(t) if t.name == "title" => Some(t), _ => None });
                    let title = t.map(|t| self.text_of(t)).unwrap_or_default();
                    self.fill_walk(&b.children, &title, add, rep);
                    continue;
                }
                if b.name == "answer" {
                    continue;
                }
                for c in &self.cs {
                    if c.rule || c.id.is_empty() || c.block != b.name || !(c.section == "*" || c.section == sec) {
                        continue;
                    }
                    let has = b.children.iter().any(|k| matches!(k, Node::Block(a) if a.name == "answer" && decl(a, "for").as_deref() == Some(c.id.as_str())));
                    if has {
                        continue;
                    }
                    if b.name == "code" {
                        rep.push(format!("line {}: code block skipped, question {} needs a person", b.line, c.id));
                        continue;
                    }
                    add.push((self.end_line(b), format!("answer start\nfor: {}\nasked: {}\nanswer end", c.id, c.arg)));
                }
                for k in &b.children {
                    if let Node::Block(a) = k {
                        if a.name == "answer" {
                            let id = decl(a, "for").unwrap_or_default();
                            match self.cs.iter().find(|c| !c.rule && c.id == id) {
                                None => rep.push(format!("line {}: RETIRED question {}, answer kept: {}", a.line, id, decl(a, "asked").unwrap_or_default())),
                                Some(c) => {
                                    let saved = decl(a, "asked").unwrap_or_default();
                                    if !saved.is_empty() && saved != c.arg {
                                        rep.push(format!("line {}: STALE answer {}, question now: {}", a.line, id, c.arg));
                                    }
                                }
                            }
                        }
                    }
                }
                self.fill_walk(&b.children, sec, add, rep);
            }
        }
    }
}

/// The page with an empty answer slot added under every question that has none, and a report of what was added or needs a person.
pub fn fill_page(text: &str) -> Result<(String, Vec<String>), String> {
    let tree = parse(&Buffer::from_text(text));
    let mut starts = vec![0usize];
    for (i, _) in text.match_indices("\n") {
        starts.push(i + 1);
    }
    let kind: Option<String> = tree.nodes.iter()
        .find_map(|n| match n { Node::Block(b) if b.name == "title" => Some(b), _ => None })
        .and_then(|t| decl(t, "kind"))
        .and_then(|k| k.split_whitespace().next().map(|s| s.to_string()));
    let k = kind.ok_or("no kind: line, so no questions apply")?;
    let cs = load_contracts(&k).ok_or("no contract data: run aiu update, or aiu see FILE --contracts once")?;
    let v = Boxes {
        text: text.to_string(),
        lines: text.split("\n").map(|l| l.to_string()).collect(),
        starts,
        width: 60,
        plain: true,
        counters: [0; 12],
        seen_title: false,
        problems: Vec::new(),
        cs,
        ok: 0,
        broken: 0,
        open: 0,
        unchecked: 0,
    };
    let mut add: Vec<(usize, String)> = Vec::new();
    let mut rep: Vec<String> = Vec::new();
    v.fill_walk(&tree.nodes, "", &mut add, &mut rep);
    let mut out: Vec<String> = Vec::new();
    for (i, l) in v.lines.iter().enumerate() {
        for (ln, t) in &add {
            if *ln == i + 1 {
                out.push(t.clone());
            }
        }
        out.push(l.clone());
    }
    rep.insert(0, format!("added {} answer slot(s)", add.len()));
    Ok((out.join("\n"), rep))
}
