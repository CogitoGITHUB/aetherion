use crate::buffer::Buffer;
use crate::database_record::Record;
use crate::database_store::Store;
use crate::parser::{parse, Node};

const KIND: &str = "block";

fn declared_name(declarations: &[crate::parser::Declaration]) -> String {
    for declaration in declarations {
        if declaration.keyword == "name" {
            return declaration.value.trim().to_string();
        }
    }
    String::new()
}

fn collect_blocks(
    nodes: &[Node],
    buffer: &Buffer,
    source: &str,
    parent: &str,
    depth: usize,
    out: &mut Vec<Record>,
) {
    for node in nodes {
        if let Node::Block(block) = node {
            let key = format!("{}:{}", source, block.line);
            out.push(
                Record::new(KIND, &key, source)
                    .with_field("block", &block.name)
                    .with_field("line", &block.line.to_string())
                    .with_field("end-line", &buffer.line_at(block.span.end).to_string())
                    .with_field("depth", &depth.to_string())
                    .with_field("parent", parent)
                    .with_field("declared-name", &declared_name(&block.declarations)),
            );
            collect_blocks(&block.children, buffer, source, &block.name, depth + 1, out);
        }
    }
}

pub fn block_records(source: &str, text: &str) -> Vec<Record> {
    let buffer = Buffer::from_text(text);
    let tree = parse(&buffer);
    let mut out: Vec<Record> = Vec::new();
    collect_blocks(&tree.nodes, &buffer, source, "", 0, &mut out);
    out
}

pub fn index_blocks(store: &mut Store, source: &str, text: &str) -> Result<(), String> {
    store.replace_source(source, KIND, block_records(source, text))
}

pub fn forget_blocks(store: &mut Store, source: &str) -> Result<(), String> {
    store.replace_source(source, KIND, Vec::new())
}

#[cfg(test)]
mod tests {
    use super::*;

    const PAGE: &str = "section start\nparagraph start\nhello\nparagraph end\nsection end\n\nparagraph start\nbye\nparagraph end\n";

    fn paragraph_parents(store: &Store) -> Vec<String> {
        store
            .of_kind("block")
            .iter()
            .filter(|r| r.field("block") == Some("paragraph"))
            .map(|r| r.field("parent").unwrap_or("?").to_string())
            .collect()
    }

    #[test]
    fn every_block_gets_one_record_with_its_parent_and_depth() {
        let mut store = Store::new();
        index_blocks(&mut store, "a/page.aiu", PAGE).unwrap();
        assert_eq!(store.of_kind("block").len(), 3);
        let mut parents = paragraph_parents(&store);
        parents.sort();
        assert_eq!(parents, vec!["".to_string(), "section".to_string()]);
        let inner = store
            .of_kind("block")
            .into_iter()
            .find(|r| r.field("parent") == Some("section"))
            .unwrap();
        assert_eq!(inner.field("depth"), Some("1"));
    }

    #[test]
    fn indexing_again_replaces_the_blocks_of_that_source_only() {
        let mut store = Store::new();
        index_blocks(&mut store, "a/page.aiu", PAGE).unwrap();
        index_blocks(&mut store, "b/page.aiu", PAGE).unwrap();
        index_blocks(&mut store, "a/page.aiu", "paragraph start\nx\nparagraph end\n").unwrap();
        assert_eq!(store.from_source("a/page.aiu").len(), 1);
        assert_eq!(store.from_source("b/page.aiu").len(), 3);
    }

    #[test]
    fn forgetting_blocks_keeps_the_file_record() {
        let mut store = Store::new();
        store.put(Record::new("file", "a/page.aiu", "a/page.aiu"));
        index_blocks(&mut store, "a/page.aiu", PAGE).unwrap();
        forget_blocks(&mut store, "a/page.aiu").unwrap();
        assert_eq!(store.from_source("a/page.aiu").len(), 1);
        assert!(store.get("file", "a/page.aiu").is_some());
    }
}
