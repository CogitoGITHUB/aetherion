use crate::buffer::Buffer;
use crate::database_record::Record;
use crate::database_store::Store;
use crate::parser::{parse, Node};

const KIND: &str = "link";

fn collect_links(
    nodes: &[Node],
    buffer: &Buffer,
    source: &str,
    parent: &str,
    out: &mut Vec<Record>,
) {
    for node in nodes {
        if let Node::Block(block) = node {
            let mut inner = parent.to_string();
            if block.name == "link" {
                let get = |key: &str| {
                    block
                        .declarations
                        .iter()
                        .find(|d| d.keyword == key)
                        .map(|d| d.value.trim().to_string())
                        .unwrap_or_default()
                };
                let name = get("name");
                let end = buffer.line_at(block.span.end.saturating_sub(1));
                let key = format!("{}:{}", source, block.line);
                out.push(
                    Record::new(KIND, &key, source)
                        .with_field("name", &name)
                        .with_field("face", &get("face"))
.with_field("relation", &{ let r = get("relation"); if r.is_empty() { "reference".to_string() } else { r } })
.with_field("mode", &{ let m = get("mode"); if m.is_empty() { "link".to_string() } else { m } })
                        .with_field("target", &get("target"))
                        .with_field("line", &block.line.to_string())
                        .with_field("end-line", &end.to_string())
                        .with_field("parent", parent),
                );
                inner = name;
            }
            collect_links(&block.children, buffer, source, &inner, out);
        }
    }
}

pub fn link_records(source: &str, text: &str) -> Vec<Record> {
    let buffer = Buffer::from_text(text);
    let tree = parse(&buffer);
    let mut out: Vec<Record> = Vec::new();
    collect_links(&tree.nodes, &buffer, source, "", &mut out);
    out
}

pub fn index_links(store: &mut Store, source: &str, text: &str) -> Result<(), String> {
    store.replace_source(source, KIND, link_records(source, text))
}

pub fn forget_links(store: &mut Store, source: &str) -> Result<(), String> {
    store.replace_source(source, KIND, Vec::new())
}

pub fn broken_links(store: &Store) -> Vec<(String, String)> {
    let mut known: std::collections::HashSet<String> = std::collections::HashSet::new();
    for r in store.of_kind("name") {
        if let Some(n) = r.field("name") {
            known.insert(n.to_string());
        }
    }
    for r in store.of_kind("file") {
        known.insert(r.key.clone());
        if let Some(last) = r.key.rsplit("/").next() {
            known.insert(last.to_string());
        }
    }
    let mut out: Vec<(String, String)> = Vec::new();
    for r in store.of_kind("link") {
        let t = r.field("target").unwrap_or("").trim().to_string();
        if t.is_empty() || !known.contains(&t) {
            out.push((r.key.clone(), t));
        }
    }
    out.sort();
    out
}

pub fn backlinks_of(store: &Store, target: &str) -> Vec<(String, String)> {
    let mut out: Vec<(String, String)> = Vec::new();
    for r in store.of_kind("link") {
        if r.field("target").unwrap_or("").trim() == target {
            out.push((r.key.clone(), r.field("relation").unwrap_or("reference").to_string()));
        }
    }
    out.sort();
    out
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
