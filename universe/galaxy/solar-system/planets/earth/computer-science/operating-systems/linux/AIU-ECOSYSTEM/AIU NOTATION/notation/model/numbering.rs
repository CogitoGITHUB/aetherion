//! One job: the heading numbers — 1, 1.1, 1.1.1 — computed from the page.
//!
//! The number is never written by hand. The author writes a heading block and
//! says how deep it is with a `level:` declaration; the number follows from
//! where the heading sits in the page. That is the same law the addresses
//! follow: computed from kind and position, never authored.
//!
//! The rule, in one sentence: walk the headings in the order they appear; the
//! heading at level L takes the next number at that level and restarts every
//! deeper level; the number is those numbers joined with a dot.
//!
//! ```text
//!     heading start            -> 1
//!     heading start            -> 1.1
//!     heading start            -> 1.1.1
//!     heading start            -> 1.2
//!     heading start            -> 2
//! ```
//!
//! The Racket model has the same rule in its own numbering file, so a page
//! numbered by the binary and a document numbered by the model agree.

use crate::parser::{Node, Tree};

/// One heading and the number it was given.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NumberedHeading {
    /// The number, as it is written: "1", "1.1", "1.1.1".
    pub number: String,
    /// The level the heading declared, or 1 when it declared none.
    pub level: u32,
    /// The line the heading block starts on.
    pub line: usize,
}

/// The numbers of every heading in a page, kept so a caller can ask for the
/// number of the heading on a given line.
///
/// A heading's number cannot be known from the heading alone: it depends on
/// the headings before it. So the numbers are computed once for the whole
/// page and then looked up by line, and a caller that holds one node asks
/// this for the line that node is on.
#[derive(Debug, Clone, Default)]
pub struct HeadingNumbers {
    /// The numbers, in the order the headings appear.
    entries: Vec<NumberedHeading>,
}

// HeadingNumbers holds the numbers of the headings in a tree, so a caller
// can ask for the number of a heading by its line.
impl HeadingNumbers {
    /// The numbers of every heading in the tree.
    pub fn of(tree: &Tree) -> HeadingNumbers {
        HeadingNumbers { entries: heading_numbers(tree) }
    }

    /// The numbers, in the order the headings appear.
    pub fn entries(&self) -> &[NumberedHeading] {
        &self.entries
    }

    /// The number of the heading that starts on this line, or None when the
    /// line holds no heading.
    pub fn number_at(&self, line: usize) -> Option<&str> {
        self.entries
            .iter()
            .find(|heading| heading.line == line)
            .map(|heading| heading.number.as_str())
    }
}

const NUMBERED: &str = "chapter";

pub fn heading_numbers(tree: &Tree) -> Vec<NumberedHeading> {
    let mut counters: Vec<u32> = Vec::new();
    let mut out: Vec<NumberedHeading> = Vec::new();
    for node in &tree.nodes {
        walk(node, 0, &mut counters, &mut out);
    }
    out
}

fn walk(node: &Node, depth: u32, counters: &mut Vec<u32>, out: &mut Vec<NumberedHeading>) {
    if let Node::Block(block) = node {
        let mut inner = depth;
        if block.name == NUMBERED {
            inner = depth + 1;
            take_number(counters, inner);
            out.push(NumberedHeading {
                number: number_text(counters, inner),
                level: inner,
                line: block.line,
            });
        }
        for child in &block.children {
            walk(child, inner, counters, out);
        }
    }
}

fn take_number(counters: &mut Vec<u32>, level: u32) {
    let index = (level - 1) as usize;
    while counters.len() <= index {
        counters.push(0);
    }
    counters[index] += 1;
    counters.truncate(index + 1);
}

fn number_text(counters: &[u32], level: u32) -> String {
    let index = (level - 1) as usize;
    let taken: Vec<String> = counters
        .iter()
        .take(index + 1)
        .map(|c| c.to_string())
        .collect();
    taken.join(".")
}
