#![allow(dead_code)]

pub struct Rect {
    pub top: u16,
    pub left: u16,
    pub rows: u16,
    pub cols: u16,
}

const MIN_COLS: u16 = 6;
const MIN_ROWS: u16 = 3;

pub fn rects(
    direction: &str,
    weights: &[u16],
    cols: u16,
    rows: u16,
    top: u16,
) -> Vec<Rect> {
    let total: u32 = weights.iter().map(|weight| (*weight).max(1) as u32).sum();
    let total = total.max(1);
    let mut held: Vec<Rect> = Vec::new();
    if direction == "column" {
        let mut top = top;
        let mut used: u32 = 0;
        for (at, weight) in weights.iter().enumerate() {
            let weight = (*weight).max(1) as u32;
            let height = if at + 1 == weights.len() {
                (rows as u32).saturating_sub(used)
            } else {
                (rows as u32 * weight) / total
            };
            used += height;
            let height = height.max(MIN_ROWS as u32) as u16;
            held.push(Rect {
                top,
                left: 1,
                rows: height,
                cols,
            });
            top += height;
        }
    } else {
        let mut left: u16 = 1;
        let mut used: u32 = 0;
        for (at, weight) in weights.iter().enumerate() {
            let weight = (*weight).max(1) as u32;
            let width = if at + 1 == weights.len() {
                (cols as u32).saturating_sub(used)
            } else {
                (cols as u32 * weight) / total
            };
            used += width;
            let width = width.max(MIN_COLS as u32) as u16;
            held.push(Rect {
                top,
                left,
                rows,
                cols: width,
            });
            left += width;
        }
    }
    held
}

#[cfg(test)]
#[path = "geometry_test/geometry_test_behavior.rs"]
mod tests;
