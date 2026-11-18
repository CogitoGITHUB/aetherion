//! One job: the `view` command, the page formatted for a terminal with numbers, frames and colour.
//! Replaces the second parser in the old Racket viewer: this walks the tree the Rust parser already built.
use notation::buffer::Buffer;
use notation::parser::{parse, Block, ErrorKind, Node};

/// The page being drawn: its lines, where each starts, and the output so far.
struct View<'a> {
    text: &'a str,
    lines: Vec<&'a str>,
    starts: Vec<usize>,
    cols: usize,
    plain: bool,
    out: String,
    last_blank: bool,
    numbers: notation::numbering::HeadingNumbers,
    seen_title: bool,
    problems: Vec<String>,
}


/// The value of one declaration of a block, if it has it.
fn decl<'b>(b: &'b Block, key: &str) -> Option<&'b str> {
    b.declarations.iter().find(|d| d.keyword == key).map(|d| d.value.as_str())
}

/// Break text into lines of at most w characters, at spaces.
fn wrap(text: &str, w: usize) -> Vec<String> {
    let mut acc: Vec<String> = Vec::new();
    let mut cur = String::new();
    for word in text.split_whitespace() {
        if cur.is_empty() {
            cur = word.to_string();
        } else if cur.chars().count() + 1 + word.chars().count() <= w {
            cur.push(' ');
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

impl<'a> View<'a> {
    /// The 1-based line a byte offset falls on.
    fn line_of(&self, byte: usize) -> usize {
        self.starts.partition_point(|&s| s <= byte)
    }

    /// The line a block's end marker is on.
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
        let mut res = Vec::new();
        let mut ln = s + 1 + b.declarations.len();
        while ln < e {
            if !kids.iter().any(|&(a, z)| ln >= a && ln <= z) {
                res.push(self.lines.get(ln - 1).copied().unwrap_or("").to_string());
            }
            ln += 1;
        }
        res
    }

    /// A block's body as one line of text, used for titles.
    fn text_of(&self, b: &Block) -> String {
        let v: Vec<String> = self.body(b).iter().map(|l| l.trim().to_string()).filter(|l| !l.is_empty()).collect();
        v.join(" ")
    }

    /// Colour the text with ANSI codes, unless plain.
    fn sgr(&self, codes: &[u32], s: &str) -> String {
        if self.plain || s.is_empty() {
            return s.to_string();
        }
        crate::theme::paint(codes, s)
    }

    /// Print one line.
    fn out(&mut self, s: &str) {
        self.out.push_str(s);
        self.out.push('\n');
        self.last_blank = false;
    }

    /// Print a blank line unless one was just printed.
    fn gap(&mut self) {
        if !self.last_blank {
            self.out.push('\n');
            self.last_blank = true;
        }
    }

    /// The style and colour codes a block asks for.
    fn style(&self, b: &Block) -> Vec<u32> {
        let mut v = Vec::new();
        for t in decl(b, "style").unwrap_or("").split_whitespace() {
            match t { "bold" => v.push(1), "dim" => v.push(2), "italic" => v.push(3), "underline" => v.push(4), _ => {} }
        }
        v
    }

    /// Print wrapped lines with the given codes.
    fn wrapped(&mut self, codes: &[u32], text: &str) {
        for l in wrap(text, self.cols) {
            let s = self.sgr(codes, &l);
            self.out(&s);
        }
    }

    /// Print a rule under a heading, as long as the text up to the width.
    fn rule(&mut self, ch: &str, len: usize) {
        let n = self.cols.min(len.max(3));
        let s = self.sgr(&[2], &ch.repeat(n));
        self.out(&s);
    }

    /// Print the file title, with its kind and tags.
    fn file_title(&mut self, b: &Block) {
        let text = self.text_of(b);
        let mut codes = vec![1, 33];
        codes.extend(self.style(b));
        self.gap();
        self.wrapped(&codes, &text);
        self.rule("═", text.chars().count());
        if let Some(k) = decl(b, "kind").filter(|k| !k.is_empty() && !reading()) {
            let s = self.sgr(&[1, 36], &format!("kind: {}", k));
            self.out(&s);
        }
        if let Some(t) = decl(b, "tags").filter(|t| !t.is_empty() && !reading()) {
            let s = self.sgr(&[2], &format!("tags: {}", t));
            self.out(&s);
        }
        self.gap();
    }

    /// Print a numbered section heading.
    fn heading(&mut self, depth: usize, label: &str, text: &str, b: &Block) {
        let mut codes: Vec<u32> = match depth.min(3) { 1 => vec![1, 36], 2 => vec![1, 34], _ => vec![1] };
        codes.extend(self.style(b));
        let line = format!("{}  {}", label, text);
        self.gap();
        self.wrapped(&codes, &line);
        if depth == 1 {
            self.rule("─", line.chars().count());
        }
        self.gap();
    }

fn tag(&mut self, b: &Block) {
if reading() { return; }
if let Some(n) = self.numbers.block_number_at(b.line) {
let s = self.sgr(&[2], n);
self.out(&s);
}
}
    /// Print a paragraph or comment, wrapped, one group at a time.
    fn paragraph(&mut self, b: &Block) {
self.tag(b);
        let codes = self.style(b);
        for (k, g) in groups(&self.body(b)).iter().enumerate() {
            if k > 0 {
                self.gap();
            }
            self.wrapped(&codes, g);
        }
    }

    /// Items one per line: bullets for a list, numbers for steps.
    fn content_items(&mut self, b: &Block) {
        self.tag(b);
        let mut n = 0;
        for l in self.body(b) {
            if l.trim().is_empty() { continue; }
            n += 1;
            let mark = if b.name == "steps" {
                format!("{}.", n)
            } else {
                "•".to_string()
            };
            self.wrapped(&[], &format!("{} {}", mark, l.trim()));
        }
    }

    /// A head line, then the body: definition, example, exercise, callout.
    fn content_headed(&mut self, b: &Block) {
        self.tag(b);
        let lines = self.body(b);
        let blank = |l: &&String| l.trim().is_empty();
        let mut rest = lines.iter().skip_while(blank);
        let head = rest.next().cloned().unwrap_or_default();
        let tail: Vec<String> = rest.cloned().collect();
        let name = format!("{} · {}", b.name, head.trim());
        let s = self.sgr(&[1, 36], &name);
        self.out(&s);
        for (k, g) in groups(&tail).iter().enumerate() {
            if k > 0 { self.gap(); }
            self.wrapped(&[], g);
        }
    }

    /// An equation in a frame, as written.
    fn content_formula(&mut self, b: &Block) {
        self.tag(b);
        let mut body = self.body(b);
        while body.first().map_or(false, |l| l.trim().is_empty()) {
            body.remove(0);
        }
        while body.last().map_or(false, |l| l.trim().is_empty()) {
            body.pop();
        }
        let top = self.sgr(&[2], "┌─ formula");
        self.out(&top);
        for l in body {
            let bar = self.sgr(&[2], "│ ");
            let s = format!("{}{}", bar, self.sgr(&[32], &l));
            self.out(&s);
        }
        let bottom = self.sgr(&[2], "└─");
        self.out(&bottom);
    }

    /// Blank room for hand work. The first line is the number of lines.
    fn content_space(&mut self, b: &Block) {
        self.tag(b);
        let body = self.body(b);
        let first = body.iter().find(|l| !l.trim().is_empty());
        let rows = first
            .and_then(|l| l.trim().parse::<usize>().ok())
            .unwrap_or(8).min(60);
        let name = format!("┌─ space · {} lines", rows);
        let top = self.sgr(&[2], &name);
        self.out(&top);
        for _ in 0..rows {
            let s = self.sgr(&[2], "│");
            self.out(&s);
        }
        let bottom = self.sgr(&[2], "└─");
        self.out(&bottom);
    }

    /// Print a code block in a frame, exactly as written.
    fn code(&mut self, b: &Block) {
self.tag(b);
        let lang = decl(b, "language").unwrap_or("").to_string();
        let label = if lang.is_empty() { "code".to_string() } else { lang };
        let mut body = self.body(b);
        while body.first().map_or(false, |l| l.trim().is_empty()) { body.remove(0); }
        while body.last().map_or(false, |l| l.trim().is_empty()) { body.pop(); }
        let top = self.sgr(&[2], &format!("┌─ {}", label));
        self.out(&top);
        for l in body {
            let s = format!("{}{}", self.sgr(&[2], "│ "), self.sgr(&[32], &l));
            self.out(&s);
        }
        let bottom = self.sgr(&[2], "└─");
        self.out(&bottom);
    }

    /// Print one node: a block with what it holds, or an error.
    fn node(&mut self, n: &Node, depth: usize) {
        match n {
            Node::Block(b) => self.block(b, depth),
            Node::Error(e) => {
                if e.kind == ErrorKind::StrayText {
                    self.gap();
                    let s = self.sgr(&[1, 31], &format!("! stray text (outside any block): {}", e.what));
                    self.out(&s);
                } else {
                    self.problems.push(format!("line {}: {}", e.line, e.what));
                }
            }
        }
    }

    /// Print one block at a section depth.
    fn block(&mut self, b: &Block, depth: usize) {
        let first = b.children.iter().find_map(|n| if let Node::Block(c) = n { Some(c) } else { None });
        match b.name.as_str() {
            "chapter" | "appendix" | "part" => {
                let d = (depth + 1).min(11);
                let kd = if b.name == "part" { depth } else { d };
                let label = self.numbers.number_at(b.line).unwrap_or("").to_string();
                let label = if label.is_empty() {
                    b.name.clone()
                } else {
                    label
                };
                let title = b.children.iter().find_map(|n| match n { Node::Block(c) if c.name == "title" => Some(c), _ => None });
                match title {
                    Some(t) => {
                        let text = self.text_of(t);
                        self.heading(d, &label, &text, t);
                        if first.map_or(true, |f| f.span.start != t.span.start) {
                            let l = self.line_of(t.span.start);
                            self.problems.push(format!("line {}: a chapter title must be its first block", l));
                        }
                    }
                    None => {
                        self.heading(d, &label, "(untitled chapter)", b);
                        let l = self.line_of(b.span.start);
                        self.problems.push(format!("line {}: chapter has no title block", l));
                    }
                }
                for n in &b.children {
                    if let (Node::Block(c), Some(t)) = (n, title) {
                        if c.span.start == t.span.start { continue; }
                    }
                    self.node(n, kd);
                }
                return;
            }
            "title" => {
                if depth == 0 && !self.seen_title {
                    self.seen_title = true;
                    self.file_title(b);
                } else {
                    self.gap();
                    let mut codes = vec![1];
                    codes.extend(self.style(b));
                    let t = self.text_of(b);
                    let s = self.sgr(&codes, &t);
                    self.out(&s);
                    self.gap();
                }
            }
            "comment" | "answer" | "mark" if reading() => { return; }
            "paragraph" | "aside" | "quote" | "abstract" | "dedication" | "epigraph" | "acknowledgments" | "comment" | "reference" | "footnote" | "cover" | "title-page" | "copyright" | "preface" | "volume" => { self.gap(); self.paragraph(b); }
            "definition" | "example" | "exercise" | "claim" | "evidence" | "hypothesis" | "remark" | "callout" | "pin" => {
                self.gap();
                self.content_headed(b);
            }
            "list" | "steps" => { self.gap(); self.content_items(b); }
            "formula" => { self.gap(); self.content_formula(b); }
            "space" => { self.gap(); self.content_space(b); }
            "code" => { self.gap(); self.code(b); }
            "contract" => { if reading() { return; } }
            other => {
                self.gap();
                let s = self.sgr(&[2, 33], &format!("? unknown block: {}", other));
                self.out(&s);
                self.paragraph(b);
            }
        }
        for n in &b.children {
            self.node(n, depth);
        }
    }
}

/// The page formatted for a terminal of the given width, with colour unless plain.
pub fn render_view(text: &str, width: usize, plain: bool, contracts: bool) -> String {
    let tree = parse(&Buffer::from_text(text));
    let mut starts = vec![0usize];
    for (i, ch) in text.char_indices() {
        if ch == '\n' { starts.push(i + 1); }
    }
    let mut v = View {
        text, lines: text.split('\n').collect(), starts, cols: width.saturating_sub(2), plain,
        out: String::new(), last_blank: true, numbers: notation::numbering::HeadingNumbers::of(&tree), seen_title: false, problems: Vec::new(),
    };
    for n in &tree.nodes {
        v.node(n, 0);
    }
    let has_title = tree.nodes.iter().any(|n| matches!(n, Node::Block(b) if b.name == "title"));
    if !has_title {
        v.problems.push("line 1: the file has no title block".to_string());
    }
    if !v.problems.is_empty() {
        v.gap();
        let n = v.problems.len();
        let head = v.sgr(&[1, 31], &format!("{} problem{} found:", n, if n == 1 { "" } else { "s" }));
        v.out(&head);
        for p in v.problems.clone() {
            let s = v.sgr(&[31], &format!("  {}", p));
            v.out(&s);
        }
        let hint = v.sgr(&[2], "run: aiu check FILE   for the full check");
        v.out(&hint);
    }
    if contracts { v.panel(&tree.nodes); }
    v.out
}

/// The end of the to-do sentence of a broken rule, as the checker words it.
const RULE_TODO_END: &str = "; the checker never edits it";

/// One contract of a file type, as the data file holds it; for a question, arg is the question text.
struct Contract {
    rule: bool,
    section: String,
    block: String,
    name: String,
    arg: String,
}

/// The contracts of one file type, read from the nearest .notation folder.
fn load_contracts(kind: &str) -> Option<Vec<Contract>> {
    let rows = crate::contract_files::read(kind)?;
    Some(rows.into_iter().map(|r| Contract {
        rule: r.rule,
        section: r.section,
        block: r.block,
        name: r.name,
        arg: r.arg,
    }).collect())
}

/// Whether a contract names this block in this section; the section * means any section.
fn applies(c: &Contract, b: &Block, sec: &str) -> bool {
    c.block == b.name && (c.section == "*" || c.section == sec)
}

impl<'a> View<'a> {
    /// Collect every block that is not a section, with the title of the section it sits in, in page order.
    fn placed<'t>(&self, nodes: &'t [Node], sec: &str, acc: &mut Vec<(&'t Block, String)>) {
        for n in nodes {
            if let Node::Block(b) = n {
                if b.name == "chapter" {
                    let t = b.children.iter().find_map(|c| match c {
                        Node::Block(t) if t.name == "title" => Some(t),
                        _ => None,
                    });
                    let title = t.map(|t| self.text_of(t)).unwrap_or_default();
                    self.placed(&b.children, &title, acc);
                } else {
                    acc.push((b, sec.to_string()));
                }
            }
        }
    }

    /// How a block breaks a rule, or None when it keeps it.
    fn rule_failure(&self, b: &Block, c: &Contract) -> Option<String> {
        match c.name.as_str() {
            "needs-declaration" => decl(b, &c.arg).is_none().then(|| format!("has no {}: declaration", c.arg)),
            _ => None,
        }
    }

    /// Print the contracts panel after the page: every contract of the type with its state, then each finding.
    fn panel(&mut self, nodes: &[Node]) {
        let kind: Option<String> = nodes
            .iter()
            .find_map(|n| match n { Node::Block(b) if b.name == "title" => Some(b), _ => None })
            .and_then(|t| decl(t, "kind"))
            .and_then(|k| k.split_whitespace().next())
            .map(|k| k.to_string());
        self.gap();
        let head = self.sgr(&[1, 36], "Contracts (rules are checked; questions are not verified)");
        self.out(&head);
        let kind = match kind {
            Some(k) => k,
            None => {
                let s = self.sgr(&[2], "this page has no kind: line, so no contract applies");
                self.out(&s);
                return;
            }
        };
        let cs = match load_contracts(&kind) {
            Some(c) => c,
            None => {
                let s = self.sgr(&[1, 31], "no .notation folder for this kind up the tree");
                self.out(&s);
                return;
            }
        };
        if cs.is_empty() {
            let s = self.sgr(&[2], &format!("no contracts apply to the kind {}", kind));
            self.out(&s);
            return;
        }
        let mut placed: Vec<(&Block, String)> = Vec::new();
        self.placed(nodes, "", &mut placed);
        let mut fs: Vec<(usize, bool, String, String)> = Vec::new();
        for (b, sec) in &placed {
            for c in &cs {
                if !applies(c, b, sec) {
                    continue;
                }
                let wh = if sec.is_empty() { "the page".to_string() } else { format!("the section {}", sec) };
                if c.rule {
                    if let Some(bad) = self.rule_failure(b, c) {
                        fs.push((b.line, true, format!("a {} block in {} {}", c.block, wh, bad),
                            format!("change the block so the rule {} {} holds{}", c.name, c.arg, RULE_TODO_END)));
                    }
                } else {
                    fs.push((b.line, false,
                        format!("a {} block in {} must answer: {} (the checker cannot verify this)", c.block, wh, c.arg),
                        "have a person or an AI judge the block against the question".to_string()));
                }
            }
        }
        let t = self.sgr(&[1], &format!("contracts of the type {}:", kind));
        self.out(&t);
        for c in &cs {
            let n = placed.iter().filter(|(b, s)| applies(c, b, s)).count();
            let hits: Vec<String> = placed.iter()
                .filter(|(b, s)| applies(c, b, s))
                .filter(|(b, _)| !c.rule || self.rule_failure(b, c).is_some())
                .map(|(b, _)| b.line.to_string())
                .collect();
            let at = hits.join(", ");
            let wh = if c.section == "*" { "any section".to_string() } else { format!("section {}", c.section) };
            let label = if c.rule {
                format!("rule: {} in {}: {} {}", c.block, wh, c.name, c.arg)
            } else {
                format!("question: {} in {}: {}", c.block, wh, c.arg)
            };
            let regex_rule = c.rule && (c.name == "must-match" || c.name == "must-not-match");
            let (codes, status): (Vec<u32>, String) = if n == 0 {
                (vec![2], "no matching block".to_string())
            } else if regex_rule {
                (vec![2, 33], "not checked by view, run aiu check".to_string())
            } else if !c.rule {
                (vec![33], if hits.is_empty() { "not verified".to_string() } else { format!("not verified (line {})", at) })
            } else if !hits.is_empty() {
                (vec![1, 31], format!("BROKEN, line {}", at))
            } else {
                (vec![32], format!("holds in {} block{}", n, if n == 1 { "" } else { "s" }))
            };
            for l in wrap(&label, self.cols.saturating_sub(4)) {
                self.out(&format!("  {}", l));
            }
            let s = self.sgr(&codes, &format!("    -> {}", status));
            self.out(&s);
        }
        if fs.is_empty() {
            let s = self.sgr(&[2], "no contract findings");
            self.out(&s);
            return;
        }
        self.gap();
        for (line, rule, what, todo) in &fs {
            let label = format!("{}  line {}", if *rule { "RULE BROKEN" } else { "OPEN QUESTION" }, line);
            let s = self.sgr(if *rule { &[1, 31] } else { &[1, 33] }, &label);
            self.out(&s);
            for l in wrap(what, self.cols.saturating_sub(2)) {
                self.out(&format!("  {}", l));
            }
            for l in wrap(&format!("to do: {}", todo), self.cols.saturating_sub(2)) {
                let s = self.sgr(&[2], &format!("  {}", l));
                self.out(&s);
            }
        }
        let broken = fs.iter().filter(|f| f.1).count();
        let s = self.sgr(&[2], &format!("rules broken: {}, open questions: {}", broken, fs.len() - broken));
        self.out(&s);
    }
}

/// A wrap margin: the named environment variable when set, else the default.
#[allow(dead_code)]
fn env_k(name: &str, default: usize) -> usize {
    std::env::var(name).ok().and_then(|v| v.parse().ok()).unwrap_or(default)
}

static READ: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);

pub fn set_read(on: bool) { READ.store(on, std::sync::atomic::Ordering::Relaxed); }

fn reading() -> bool { READ.load(std::sync::atomic::Ordering::Relaxed) }
