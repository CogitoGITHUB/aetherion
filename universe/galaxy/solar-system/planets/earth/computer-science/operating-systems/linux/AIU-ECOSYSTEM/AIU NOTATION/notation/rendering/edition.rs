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

fn box_label(row: &str) -> Option<String> {
    let start = row.find("╭─┤ ")? + "╭─┤ ".len();
    let rest = &row[start..];
    let end = rest.find(" ├")?;
    let label = &rest[..end];
    let (num, _) = label.split_once(" · ")?;
    Some(num.to_string())
}

pub fn render(text: &str, name: &str, width: usize, lines: usize) -> String {
    let body = lines.max(8) - 4;
    crate::boxview::set_pages(Vec::new());
    let first = strip(&crate::boxview::render_boxes(text, width, true, false));
    let mut pages: Vec<(String, usize)> = Vec::new();
    let f1 = first.lines().position(|r| box_label(r).is_some());
    let pad = match f1 {
        Some(f) => (body - f % body) % body,
        None => 0,
    };
    let fp = match f1 {
        Some(f) => (f + pad) / body,
        None => 0,
    };
    for (i, row) in first.lines().enumerate() {
        if let Some(label) = box_label(row) {
            if !pages.iter().any(|p| p.0 == label) {
                pages.push((label, (i + pad) / body + 1 - fp));
            }
        }
    }
    crate::boxview::set_pages(pages);
    let second = strip(&crate::boxview::render_boxes(text, width, true, false));
    let mut rows: Vec<&str> = second.lines().collect();
    let f2 = rows.iter().position(|r| box_label(r).is_some());
    let mut fp2 = 0usize;
    if let Some(f) = f2 {
        let q = (body - f % body) % body;
        for _ in 0..q {
            rows.insert(f, "");
        }
        fp2 = (f + q) / body;
    }
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
            out.push_str(rows[k]);
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
