fn roman(mut n: usize) -> String {
    let t = [(10, "x"), (9, "ix"), (5, "v"), (4, "iv"), (1, "i")];
    let mut s = String::new();
    for &(v, r) in t.iter() {
        while n >= v {
            s.push_str(r);
            n -= v;
        }
    }
    s
}

fn strip(s: &str) -> String {
    let mut out = String::new();
    let mut skip = false;
    for c in s.chars() {
        if c as u32 == 27 {
            skip = true;
            continue;
        }
        if skip {
            if c.is_alphabetic() {
                skip = false;
            }
            continue;
        }
        out.push(c);
    }
    out
}

fn is_front(row: &str) -> bool {
    let n = match row.find(" · ") {
        Some(p) => p + " · ".len(),
        None => return false,
    };
    let rest = &row[n..];
    let end = rest.find(" ├").unwrap_or(rest.len());
    matches!(
        &rest[..end],
        "dedication" | "epigraph" | "abstract" | "acknowledgments"
    )
}

fn box_label(row: &str) -> Option<String> {
    let start = row.find("╭─┤ ")? + "╭─┤ ".len();
    let rest = &row[start..];
    let end = rest.find(" ├")?;
    let label = &rest[..end];
    let (num, _) = label.split_once(" · ")?;
    Some(num.to_string())
}

fn pad_to(out: &mut Vec<String>, body: usize) {
    while out.len() % body != 0 {
        out.push(String::new());
    }
}

fn lay(text: &str, body: usize) -> (Vec<String>, usize) {
    let mut out: Vec<String> = Vec::new();
    let mut fp = 0usize;
    let mut seen = false;
    for row in text.lines() {
        if row.contains("\u{E000}") {
            pad_to(&mut out, body);
            continue;
        }
        if let Some(at) = row.find("\u{E001}") {
            let digits: String = row[at + 3..]
                .chars()
                .take_while(|c| c.is_ascii_digit())
                .collect();
            let n: usize = digits.parse().unwrap_or(0);
            if n > 0 && n <= body && out.len() % body + n > body {
                pad_to(&mut out, body);
            }
            continue;
        }
        if !seen && box_label(row).is_some() && !is_front(row) {
            seen = true;
            pad_to(&mut out, body);
            fp = out.len() / body;
        }
        out.push(row.to_string());
    }
    (out, fp)
}

pub fn render(text: &str, name: &str, width: usize, lines: usize, margin: usize) -> String {
    let body = lines.max(8) - 4;
    let inner = width.saturating_sub(margin * 2).max(20);
    crate::boxview::set_pages(Vec::new());
    crate::boxview::set_edition(true);
    let first = strip(&crate::boxview::render_boxes(text, inner, true, false));
    let (rows1, fp) = lay(&first, body);
    let mut pages: Vec<(String, usize)> = Vec::new();
    for (i, row) in rows1.iter().enumerate() {
        if let Some(label) = box_label(row) {
            if !pages.iter().any(|p| p.0 == label) {
                pages.push((label, (i / body + 1).saturating_sub(fp)));
            }
        }
    }
    crate::boxview::set_pages(pages);
    let second = strip(&crate::boxview::render_boxes(text, inner, true, false));
    let (rows, fp2) = lay(&second, body);
    let total = ((rows.len() + body - 1) / body).max(1);
    let file = std::path::Path::new(name)
        .file_name()
        .map(|f| f.to_string_lossy().to_string())
        .unwrap_or_default();
    let rule = "─".repeat(width);
    let mut out = String::new();
    for page in 0..total {
        let from = page * body;
        let to = (from + body).min(rows.len());
        out.push_str(&format!("{}\n{}\n", file, rule));
        for k in from..to {
            out.push_str(&" ".repeat(margin));
            out.push_str(&rows[k]);
            out.push_str("\n");
        }
        for _ in (to - from)..body {
            out.push_str("\n");
        }
        let foot = if page < fp2 {
            format!("page {}", roman(page + 1))
        } else {
            format!("page {} of {}", page + 1 - fp2, total - fp2)
        };
        out.push_str(&format!("{}\n{:>w$}\n\n", rule, foot, w = width));
    }
    out
}
