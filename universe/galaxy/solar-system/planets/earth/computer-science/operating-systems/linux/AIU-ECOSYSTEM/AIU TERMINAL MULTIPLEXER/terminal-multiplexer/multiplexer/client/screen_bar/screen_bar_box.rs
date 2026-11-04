pub(crate) fn box_pad(text: &str, width: usize) -> String {
    let have = text.chars().count();
    format!("{}{}", text, " ".repeat(width.saturating_sub(have)))
}

pub(crate) fn box_cut(text: &str, width: usize) -> String {
    text.chars().take(width).collect()
}

pub(crate) fn edge_line(left_corner: &str, right_corner: &str, left: &str, right: &str, width: usize) -> String {
    let head = format!("{}─ {} ", left_corner, left);
    let tail_wanted = if right.is_empty() { String::new() } else { format!(" {} ", right) };
    let head_len = head.chars().count();
    let tail = if head_len + tail_wanted.chars().count() + 2 < width { tail_wanted } else { String::new() };
    let head = if head_len + 1 > width { box_cut(&head, width.saturating_sub(1)) } else { head };
    let fill = width.saturating_sub(head.chars().count() + tail.chars().count() + 1);
    format!("{}{}{}{}", head, "─".repeat(fill), tail, right_corner)
}

pub(crate) fn rule_line(left_corner: &str, right_corner: &str, width: usize) -> String {
    format!("{}{}{}", left_corner, "─".repeat(width.saturating_sub(2)), right_corner)
}

pub(crate) fn body_line(text: &str, width: usize) -> String {
    let inner = width.saturating_sub(4).max(1);
    format!("│ {} │", box_pad(&box_cut(text, inner), inner))
}

pub(crate) fn mark_row(names: &[String], active: Option<usize>, inner: usize) -> String {
    let cells: Vec<String> = names
        .iter()
        .enumerate()
        .map(|(at, name)| if Some(at) == active { format!("● {}", name) } else { name.clone() })
        .collect();
    let text = |start: usize| -> String {
        let lead = if start > 0 { "‹ " } else { "" };
        format!("{}{}", lead, cells[start.min(cells.len())..].join("   "))
    };
    let mut start = 0;
    while let Some(at) = active {
        if start < at && text(start).chars().count() > inner {
            start += 1;
        } else {
            break;
        }
    }
    text(start)
}
