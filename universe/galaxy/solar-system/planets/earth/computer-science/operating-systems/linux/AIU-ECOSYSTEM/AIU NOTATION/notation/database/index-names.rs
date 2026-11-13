use std::collections::BTreeMap;

use crate::buffer::Buffer;
use crate::database_record::Record;
use crate::database_store::Store;
use crate::parser::{parse, Node};

const KIND: &str = "name";

fn collect_names(nodes: &[Node], source: &str, out: &mut Vec<Record>) {
    for node in nodes {
        if let Node::Block(block) = node {
            for declaration in &block.declarations {
                if declaration.keyword == "name" {
                    let value = declaration.value.trim();
                    if !value.is_empty() {
                        let key = format!("{}:{}", source, block.line);
                        out.push(
                            Record::new(KIND, &key, source)
                                .with_field("name", value)
                                .with_field("block", &block.name)
                                .with_field("line", &block.line.to_string()),
                        );
                    }
                    break;
                }
            }
            collect_names(&block.children, source, out);
        }
    }
}

pub fn name_records(source: &str, text: &str) -> Vec<Record> {
    let buffer = Buffer::from_text(text);
    let tree = parse(&buffer);
    let mut out: Vec<Record> = Vec::new();
    collect_names(&tree.nodes, source, &mut out);
    out
}

pub fn index_names(store: &mut Store, source: &str, text: &str) -> Result<(), String> {
    store.replace_source(source, KIND, name_records(source, text))
}

pub fn forget_names(store: &mut Store, source: &str) -> Result<(), String> {
    store.replace_source(source, KIND, Vec::new())
}

pub fn duplicate_names(store: &Store) -> Vec<(String, Vec<String>)> {
    let mut places: BTreeMap<String, Vec<String>> = BTreeMap::new();
    for record in store.of_kind(KIND) {
        let name = record.field("name").unwrap_or("").to_string();
        places.entry(name).or_default().push(record.key.clone());
    }
    let mut out: Vec<(String, Vec<String>)> = Vec::new();
    for (name, mut where_found) in places {
        if where_found.len() > 1 {
            where_found.sort();
            out.push((name, where_found));
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    const PAGE: &str = "paragraph start\nname: paragraph-one\nhello\nparagraph end\n\nchapter start\nname: section-two\nparagraph start\nname: paragraph-three\nbye\nparagraph end\nchapter end\n\nparagraph start\nunnamed\nparagraph end\n";

    #[test]
    fn each_named_block_gets_one_record_and_unnamed_blocks_none() {
        let mut store = Store::new();
        index_names(&mut store, "a/page.aiu", PAGE).unwrap();
        assert_eq!(store.of_kind("name").len(), 3);
        assert!(store.get("name", "a/page.aiu:2").is_none());
        let first = store.get("name", "a/page.aiu:1").unwrap();
        assert_eq!(first.field("name"), Some("paragraph-one"));
        assert_eq!(first.field("block"), Some("paragraph"));
        assert_eq!(first.field("line"), Some("1"));
    }

    #[test]
    fn a_name_used_twice_in_the_ecosystem_is_reported_with_its_places() {
        let mut store = Store::new();
        index_names(&mut store, "a/page.aiu", PAGE).unwrap();
        index_names(&mut store, "b/page.aiu", PAGE).unwrap();
        let duplicates = duplicate_names(&store);
        assert_eq!(duplicates.len(), 3);
        let first = duplicates.iter().find(|d| d.0 == "paragraph-one").unwrap();
        assert_eq!(first.1, vec!["a/page.aiu:1".to_string(), "b/page.aiu:1".to_string()]);
    }

    #[test]
    fn names_that_are_all_different_report_no_duplicates() {
        let mut store = Store::new();
        index_names(&mut store, "a/page.aiu", PAGE).unwrap();
        assert!(duplicate_names(&store).is_empty());
    }

    #[test]
    fn indexing_again_replaces_the_names_of_that_source_only() {
        let mut store = Store::new();
        index_names(&mut store, "a/page.aiu", PAGE).unwrap();
        index_names(&mut store, "b/page.aiu", PAGE).unwrap();
        index_names(&mut store, "a/page.aiu", "paragraph start\nnothing\nparagraph end\n").unwrap();
        assert_eq!(store.of_kind("name").len(), 3);
        assert!(duplicate_names(&store).is_empty());
    }

    #[test]
    fn forgetting_names_keeps_the_file_record() {
        let mut store = Store::new();
        store.put(Record::new("file", "a/page.aiu", "a/page.aiu"));
        index_names(&mut store, "a/page.aiu", PAGE).unwrap();
        forget_names(&mut store, "a/page.aiu").unwrap();
        assert_eq!(store.from_source("a/page.aiu").len(), 1);
        assert!(store.get("file", "a/page.aiu").is_some());
    }
}
