use crate::buffer::Buffer;
use crate::database_record::Record;
use crate::database_store::Store;
use crate::parser::{parse, Node};

const KIND: &str = "tag";

fn collect_title_tags(
    nodes: &[Node],
    buffer: &Buffer,
    lines: &[&str],
    source: &str,
    out: &mut Vec<Record>,
) {
    for node in nodes {
        if let Node::Block(block) = node {
            if block.name == "title" {
                let end_line = buffer.line_at(block.span.end);
                let mut number = block.line + 1;
                while number < end_line {
                    if let Some(line) = lines.get(number - 1) {
                        if let Some(words) = line.trim_start().strip_prefix("tags:") {
                            let spaced = words.replace(",", " ");
                            for tag in spaced.split_whitespace() {
                                let key = format!("{}:{}", source, tag);
                                let known = out.iter().any(|r| r.key == key);
                                if !known {
                                    out.push(
                                        Record::new(KIND, &key, source)
                                            .with_field("tag", tag)
                                            .with_field("line", &number.to_string()),
                                    );
                                }
                            }
                        }
                    }
                    number += 1;
                }
            }
            collect_title_tags(&block.children, buffer, lines, source, out);
        }
    }
}

pub fn tag_records(source: &str, text: &str) -> Vec<Record> {
    let buffer = Buffer::from_text(text);
    let tree = parse(&buffer);
    let lines: Vec<&str> = text.split("\n").collect();
    let mut out: Vec<Record> = Vec::new();
    collect_title_tags(&tree.nodes, &buffer, &lines, source, &mut out);
    out
}

pub fn index_tags(store: &mut Store, source: &str, text: &str) -> Result<(), String> {
    store.replace_source(source, KIND, tag_records(source, text))
}

pub fn forget_tags(store: &mut Store, source: &str) -> Result<(), String> {
    store.replace_source(source, KIND, Vec::new())
}

#[cfg(test)]
mod tests {
    use super::*;

    const PAGE: &str = "title start\nkind: default\ntags: notation contracts\nPlan\ntitle end\n\nparagraph start\ntags: not-a-tag\nparagraph end\n";

    #[test]
    fn each_tag_of_the_title_gets_one_record_with_its_line() {
        let mut store = Store::new();
        index_tags(&mut store, "a/page.aiu", PAGE).unwrap();
        assert_eq!(store.of_kind("tag").len(), 2);
        let record = store.get("tag", "a/page.aiu:contracts").unwrap();
        assert_eq!(record.field("tag"), Some("contracts"));
        assert_eq!(record.field("line"), Some("3"));
    }

    #[test]
    fn a_tags_line_outside_the_title_is_not_indexed() {
        let mut store = Store::new();
        index_tags(&mut store, "a/page.aiu", PAGE).unwrap();
        assert!(store.get("tag", "a/page.aiu:not-a-tag").is_none());
    }

    #[test]
    fn indexing_again_replaces_the_tags_of_that_source_only() {
        let mut store = Store::new();
        index_tags(&mut store, "a/page.aiu", PAGE).unwrap();
        index_tags(&mut store, "b/page.aiu", PAGE).unwrap();
        index_tags(&mut store, "a/page.aiu", "title start\ntags: other\nPlan\ntitle end\n").unwrap();
        assert!(store.get("tag", "a/page.aiu:contracts").is_none());
        assert!(store.get("tag", "a/page.aiu:other").is_some());
        assert!(store.get("tag", "b/page.aiu:contracts").is_some());
    }

    #[test]
    fn forgetting_tags_keeps_the_file_record() {
        let mut store = Store::new();
        store.put(Record::new("file", "a/page.aiu", "a/page.aiu"));
        index_tags(&mut store, "a/page.aiu", PAGE).unwrap();
        forget_tags(&mut store, "a/page.aiu").unwrap();
        assert_eq!(store.from_source("a/page.aiu").len(), 1);
        assert!(store.get("file", "a/page.aiu").is_some());
    }
}
