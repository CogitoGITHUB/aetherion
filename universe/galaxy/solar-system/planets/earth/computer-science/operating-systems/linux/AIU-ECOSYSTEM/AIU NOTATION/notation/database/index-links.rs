use crate::buffer::Buffer;
use crate::database_record::Record;
use crate::database_store::Store;
use crate::parser::{parse, Node};

const KIND: &str = "link";

struct OpenLink {
    line: usize,
    name: String,
    target: String,
    header_open: bool,
}

fn collect_opaque_lines_for_links(nodes: &[Node], buffer: &Buffer, out: &mut Vec<(usize, usize)>) {
    for node in nodes {
        if let Node::Block(block) = node {
            if block.is_opaque() {
                let end_line = buffer.line_at(block.span.end);
                if end_line > block.line + 1 {
                    out.push((block.line + 1, end_line - 1));
                }
            }
            collect_opaque_lines_for_links(&block.children, buffer, out);
        }
    }
}

pub fn link_records(source: &str, text: &str) -> Vec<Record> {
    let buffer = Buffer::from_text(text);
    let tree = parse(&buffer);
    let mut opaque: Vec<(usize, usize)> = Vec::new();
    collect_opaque_lines_for_links(&tree.nodes, &buffer, &mut opaque);
    let mut open: Vec<OpenLink> = Vec::new();
    let mut out: Vec<Record> = Vec::new();
    for (index, line) in text.split("\n").enumerate() {
        let number = index + 1;
        let hidden = opaque.iter().any(|(first, last)| number >= *first && number <= *last);
        if hidden {
            continue;
        }
        let trimmed = line.trim();
        if trimmed == "link start" {
            open.push(OpenLink {
                line: number,
                name: String::new(),
                target: String::new(),
                header_open: true,
            });
        } else if trimmed == "link end" {
            if let Some(done) = open.pop() {
                let parent = match open.last() {
                    Some(outer) => outer.name.clone(),
                    None => String::new(),
                };
                let key = format!("{}:{}", source, done.line);
                out.push(
                    Record::new(KIND, &key, source)
                        .with_field("name", &done.name)
                        .with_field("target", &done.target)
                        .with_field("line", &done.line.to_string())
                        .with_field("end-line", &number.to_string())
                        .with_field("parent", &parent),
                );
            }
        } else if let Some(current) = open.last_mut() {
            if current.header_open {
                if let Some(words) = trimmed.strip_prefix("name:") {
                    current.name = words.trim().to_string();
                } else if let Some(words) = trimmed.strip_prefix("target:") {
                    current.target = words.trim().to_string();
                } else {
                    current.header_open = false;
                }
            }
        }
    }
    out
}

pub fn index_links(store: &mut Store, source: &str, text: &str) -> Result<(), String> {
    store.replace_source(source, KIND, link_records(source, text))
}

pub fn forget_links(store: &mut Store, source: &str) -> Result<(), String> {
    store.replace_source(source, KIND, Vec::new())
}

#[cfg(test)]
mod tests {
    use super::*;

    const PAGE: &str = "link start\nname: link-a\ntarget: paragraph-x\nshown words\nlink end\n\nlink start\nname: link-b\ntarget: section-y\nlink end\n";

    #[test]
    fn each_link_block_gets_one_record_with_name_target_and_lines() {
        let mut store = Store::new();
        index_links(&mut store, "a/page.aiu", PAGE).unwrap();
        assert_eq!(store.of_kind("link").len(), 2);
        let record = store.get("link", "a/page.aiu:1").unwrap();
        assert_eq!(record.field("name"), Some("link-a"));
        assert_eq!(record.field("target"), Some("paragraph-x"));
        assert_eq!(record.field("line"), Some("1"));
        assert_eq!(record.field("end-line"), Some("5"));
        assert_eq!(record.field("parent"), Some(""));
    }

    #[test]
    fn a_link_inside_a_shown_link_records_its_outer_link_as_parent() {
        let mut store = Store::new();
        let nested = "link start\nname: outer\ntarget: t1\nlink start\nname: inner\ntarget: t2\nlink end\nlink end\n";
        index_links(&mut store, "a/page.aiu", nested).unwrap();
        let inner = store.get("link", "a/page.aiu:4").unwrap();
        assert_eq!(inner.field("parent"), Some("outer"));
        let outer = store.get("link", "a/page.aiu:1").unwrap();
        assert_eq!(outer.field("parent"), Some(""));
        assert_eq!(outer.field("end-line"), Some("8"));
    }

    #[test]
    fn a_link_inside_a_code_block_is_not_indexed() {
        let mut store = Store::new();
        let page = "code start\nlink start\nname: hidden\ntarget: t\nlink end\ncode end\n";
        index_links(&mut store, "a/page.aiu", page).unwrap();
        assert_eq!(store.of_kind("link").len(), 0);
    }

    #[test]
    fn a_link_that_never_closes_gets_no_record() {
        let mut store = Store::new();
        index_links(&mut store, "a/page.aiu", "link start\nname: open\ntarget: t\n").unwrap();
        assert_eq!(store.of_kind("link").len(), 0);
    }

    #[test]
    fn indexing_again_replaces_the_links_of_that_source_only() {
        let mut store = Store::new();
        index_links(&mut store, "a/page.aiu", PAGE).unwrap();
        index_links(&mut store, "b/page.aiu", PAGE).unwrap();
        index_links(&mut store, "a/page.aiu", "paragraph start\nnothing\nparagraph end\n").unwrap();
        assert!(store.get("link", "a/page.aiu:1").is_none());
        assert!(store.get("link", "b/page.aiu:1").is_some());
    }

    #[test]
    fn forgetting_links_keeps_the_file_record() {
        let mut store = Store::new();
        store.put(Record::new("file", "a/page.aiu", "a/page.aiu"));
        index_links(&mut store, "a/page.aiu", PAGE).unwrap();
        forget_links(&mut store, "a/page.aiu").unwrap();
        assert_eq!(store.from_source("a/page.aiu").len(), 1);
        assert!(store.get("file", "a/page.aiu").is_some());
    }
}
