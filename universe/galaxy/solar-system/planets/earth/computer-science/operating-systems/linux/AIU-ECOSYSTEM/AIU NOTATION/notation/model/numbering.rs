use crate::parser::{Node, Tree};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NumberedHeading {
    pub number: String,
    pub level: u32,
    pub line: usize,
}

#[derive(Debug, Clone, Default)]
pub struct HeadingNumbers {
    entries: Vec<NumberedHeading>,
    blocks: Vec<(usize, String)>,
}

impl HeadingNumbers {
    pub fn of(tree: &Tree) -> HeadingNumbers {
        let entries = heading_numbers(tree);
        let mut blocks: Vec<(usize, String)> = Vec::new();
        let mut count = 0u32;
        number_blocks(&tree.nodes, "", "", &mut count, &entries, &mut blocks);
        HeadingNumbers { entries, blocks }
    }

    pub fn entries(&self) -> &[NumberedHeading] {
        &self.entries
    }

    pub fn number_at(&self, line: usize) -> Option<&str> {
        self.entries
            .iter()
            .find(|heading| heading.line == line)
            .map(|heading| heading.number.as_str())
    }

    pub fn block_number_at(&self, line: usize) -> Option<&str> {
        self.blocks
            .iter()
            .find(|entry| entry.0 == line)
            .map(|entry| entry.1.as_str())
    }
}

const NUMBERED: &str = "chapter";

const UNNUMBERED: [&str; 12] = [
    "title", "comment", "answer", "contract", "row", "header",
    "contents", "index", "bibliography", "pin",
    "glossary", "part",
];

pub fn heading_numbers(tree: &Tree) -> Vec<NumberedHeading> {
    let mut counters: Vec<u32> = Vec::new();
    let mut out: Vec<NumberedHeading> = Vec::new();
    let mut apps = 0u32;
    for node in &tree.nodes {
        walk(node, 0, &mut counters, &mut apps, &mut out);
    }
    out
}

fn walk(
    node: &Node,
    depth: u32,
    counters: &mut Vec<u32>,
    apps: &mut u32,
    out: &mut Vec<NumberedHeading>,
) {
    if let Node::Block(block) = node {
        if block.name == "appendix" {
            *apps += 1;
            let code = (64 + (*apps).min(26)) as u8;
            let letter = char::from(code).to_string();
            out.push(NumberedHeading {
                number: letter.clone(),
                level: depth + 1,
                line: block.line,
            });
            let mut own: Vec<u32> = Vec::new();
            let mut none = 0u32;
            let mut sub: Vec<NumberedHeading> = Vec::new();
            for child in &block.children {
                walk(child, 1, &mut own, &mut none, &mut sub);
            }
            for mut h in sub {
                let rest = h.number.splitn(2, ".").nth(1)
                    .unwrap_or("").to_string();
                h.number = format!("{}.{}", letter, rest);
                h.level += depth;
                out.push(h);
            }
            return;
        }
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
            walk(child, inner, counters, apps, out);
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

fn number_blocks(
    nodes: &[Node],
    chapter: &str,
    chain: &str,
    count: &mut u32,
    chapters: &[NumberedHeading],
    blocks: &mut Vec<(usize, String)>,
) {
    for node in nodes {
        if let Node::Block(block) = node {
            if block.name == NUMBERED || block.name == "appendix" {
                let found = chapters.iter().find(|c| c.line == block.line);
                let own = found.map(|c| c.number.clone()).unwrap_or_default();
                let mut inner = 0u32;
                number_blocks(&block.children, &own, "", &mut inner, chapters, blocks);
            } else if UNNUMBERED.contains(&block.name.as_str()) {
                number_blocks(&block.children, chapter, chain, count, chapters, blocks);
            } else {
                *count += 1;
                let local = if chain.is_empty() {
                    count.to_string()
                } else {
                    format!("{}.{}", chain, count)
                };
                let label = if chapter.is_empty() {
                    local.clone()
                } else {
                    format!("{}>{}", chapter, local)
                };
                blocks.push((block.line, label));
                let mut inner = 0u32;
                number_blocks(&block.children, chapter, &local, &mut inner, chapters, blocks);
            }
        }
    }
}
