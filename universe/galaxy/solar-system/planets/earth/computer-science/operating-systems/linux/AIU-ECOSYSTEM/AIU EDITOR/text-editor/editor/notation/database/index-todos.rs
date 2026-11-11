use crate::buffer::Buffer;
use crate::database_record::Record;
use crate::database_store::Store;
use crate::parser::{parse, Node};

const KIND: &str = "todo";

fn collect_opaque_lines(nodes: &[Node], buffer: &Buffer, out: &mut Vec<(usize, usize)>) {
    for node in nodes {
        if let Node::Block(block) = node {
            if block.is_opaque() {
                let end_line = buffer.line_at(block.span.end);
                if end_line > block.line + 1 {
                    out.push((block.line + 1, end_line - 1));
                }
            }
            collect_opaque_lines(&block.children, buffer, out);
        }
    }
}

pub fn todo_records(source: &str, text: &str) -> Vec<Record> {
    let buffer = Buffer::from_text(text);
    let tree = parse(&buffer);
    let mut opaque: Vec<(usize, usize)> = Vec::new();
    collect_opaque_lines(&tree.nodes, &buffer, &mut opaque);
    let mut out: Vec<Record> = Vec::new();
    for (index, line) in text.split("\n").enumerate() {
        let number = index + 1;
        let hidden = opaque.iter().any(|(first, last)| number >= *first && number <= *last);
        if hidden {
            continue;
        }
        if let Some(words) = line.trim_start().strip_prefix("todo:") {
            let key = format!("{}:{}", source, number);
            out.push(
                Record::new(KIND, &key, source)
                    .with_field("line", &number.to_string())
                    .with_field("text", words.trim()),
            );
        }
    }
    out
}

pub fn index_todos(store: &mut Store, source: &str, text: &str) -> Result<(), String> {
    store.replace_source(source, KIND, todo_records(source, text))
}

pub fn forget_todos(store: &mut Store, source: &str) -> Result<(), String> {
    store.replace_source(source, KIND, Vec::new())
}

#[cfg(test)]
mod tests {
    use super::*;

    const PAGE: &str = "paragraph start\ntodo: fix this\nPlanned.\nparagraph end\n\ncode start\ntodo: hidden\ncode end\n";

    #[test]
    fn a_todo_line_gets_a_record_with_its_line_and_text() {
        let mut store = Store::new();
        index_todos(&mut store, "a/page.aiu", PAGE).unwrap();
        let record = store.get("todo", "a/page.aiu:2").unwrap();
        assert_eq!(record.field("line"), Some("2"));
        assert_eq!(record.field("text"), Some("fix this"));
    }

    #[test]
    fn a_todo_line_inside_a_code_block_is_not_indexed() {
        let mut store = Store::new();
        index_todos(&mut store, "a/page.aiu", PAGE).unwrap();
        assert_eq!(store.of_kind("todo").len(), 1);
    }

    #[test]
    fn indexing_again_replaces_the_todos_of_that_source_only() {
        let mut store = Store::new();
        index_todos(&mut store, "a/page.aiu", PAGE).unwrap();
        index_todos(&mut store, "b/page.aiu", PAGE).unwrap();
        index_todos(&mut store, "a/page.aiu", "paragraph start\nnothing\nparagraph end\n").unwrap();
        assert!(store.get("todo", "a/page.aiu:2").is_none());
        assert!(store.get("todo", "b/page.aiu:2").is_some());
    }

    #[test]
    fn forgetting_todos_keeps_the_file_record() {
        let mut store = Store::new();
        store.put(Record::new("file", "a/page.aiu", "a/page.aiu"));
        index_todos(&mut store, "a/page.aiu", PAGE).unwrap();
        forget_todos(&mut store, "a/page.aiu").unwrap();
        assert_eq!(store.from_source("a/page.aiu").len(), 1);
        assert!(store.get("file", "a/page.aiu").is_some());
    }
}
