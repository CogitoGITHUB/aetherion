use crate::buffer::Buffer;
use crate::database_record::Record;
use crate::database_store::Store;
use crate::parser::{parse, Node};

const KIND: &str = "file";

fn count_blocks(nodes: &[Node]) -> usize {
    let mut total = 0usize;
    for node in nodes {
        if let Node::Block(block) = node {
            total += 1 + count_blocks(&block.children);
        }
    }
    total
}

fn declared_kind(nodes: &[Node]) -> String {
    for node in nodes {
        if let Node::Block(block) = node {
            if block.name == "title" {
                for declaration in &block.declarations {
                    if declaration.keyword == "kind" {
                        return declaration.value.trim().to_string();
                    }
                }
            }
        }
    }
    String::new()
}

pub fn file_record(source: &str, text: &str) -> Record {
    let buffer = Buffer::from_text(text);
    let tree = parse(&buffer);
    Record::new(KIND, source, source)
        .with_field("kind", &declared_kind(&tree.nodes))
        .with_field("lines", &buffer.line_count().to_string())
        .with_field("bytes", &buffer.len().to_string())
        .with_field("blocks", &count_blocks(&tree.nodes).to_string())
        .with_field("errors", &tree.errors().len().to_string())
}

pub fn index_file(store: &mut Store, source: &str, text: &str) -> Result<(), String> {
    store.replace_source(source, KIND, vec![file_record(source, text)])
}

pub fn forget_file(store: &mut Store, source: &str) -> Result<(), String> {
    store.replace_source(source, KIND, Vec::new())
}

#[cfg(test)]
mod tests {
    use super::*;

    const PAGE: &str = "title start\nkind: todo\nTODO\ntitle end\n\nparagraph start\nhello\nparagraph end\n";

    #[test]
    fn a_page_gives_one_file_record_with_its_counts() {
        let mut store = Store::new();
        index_file(&mut store, "a/todo.aiu", PAGE).unwrap();
        let record = store.get("file", "a/todo.aiu").unwrap();
        assert_eq!(record.field("kind"), Some("todo"));
        assert_eq!(record.field("blocks"), Some("2"));
        assert_eq!(record.field("errors"), Some("0"));
        assert_eq!(record.field("bytes"), Some(PAGE.len().to_string().as_str()));
    }

    #[test]
    fn indexing_again_replaces_the_record_and_keeps_other_kinds() {
        let mut store = Store::new();
        store.put(Record::new("tag", "todo", "a/todo.aiu"));
        index_file(&mut store, "a/todo.aiu", PAGE).unwrap();
        index_file(&mut store, "a/todo.aiu", "paragraph start\nx\nparagraph end\n").unwrap();
        assert_eq!(store.of_kind("file").len(), 1);
        assert_eq!(store.get("file", "a/todo.aiu").unwrap().field("blocks"), Some("1"));
        assert!(store.get("tag", "todo").is_some());
    }

    #[test]
    fn forgetting_a_file_removes_only_its_file_record() {
        let mut store = Store::new();
        index_file(&mut store, "a/todo.aiu", PAGE).unwrap();
        index_file(&mut store, "b/note.aiu", PAGE).unwrap();
        forget_file(&mut store, "a/todo.aiu").unwrap();
        assert!(store.get("file", "a/todo.aiu").is_none());
        assert!(store.get("file", "b/note.aiu").is_some());
    }
}
