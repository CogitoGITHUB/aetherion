use crate::database_record::Record;
use crate::database_store::Store;
use crate::buffer::Buffer;
use crate::parser::{parse, Node};

const KIND: &str = "layout-item";

fn collect(
    nodes: &[Node],
    source: &str,
    parent: &str,
    out: &mut Vec<Record>,
) {
    for node in nodes {
        if let Node::Block(block) = node {
            let get = |key: &str| {
                block
                    .declarations
                    .iter()
                    .find(|d| d.keyword == key)
                    .map(|d| d.value.trim().to_string())
                    .unwrap_or_default()
            };
            let mut inner = parent.to_string();
            if block.name == "layout" {
                inner = get("name");
                let key = format!("{}:{}", source, block.line);
                out.push(
                    Record::new(KIND, &key, source)
                        .with_field("what", "layout")
                        .with_field("target", "")
                        .with_field("place", "")
                        .with_field("layout", &inner)
                        .with_field("caption", &get("caption"))
                        .with_field("line", &block.line.to_string()),
                );
            }
            if block.name == "card" || block.name == "box" {
                let key = format!("{}:{}", source, block.line);
                out.push(
                    Record::new(KIND, &key, source)
                        .with_field("what", &block.name)
                        .with_field("target", &get("target"))
                        .with_field("place", &get("place"))
                        .with_field("layout", parent)
                        .with_field("caption", &get("caption"))
                        .with_field("line", &block.line.to_string()),
                );
            }
            collect(&block.children, source, &inner, out);
        }
    }
}

pub fn layout_records(source: &str, text: &str) -> Vec<Record> {
    let buffer = Buffer::from_text(text);
    let tree = parse(&buffer);
    let mut out: Vec<Record> = Vec::new();
    collect(&tree.nodes, source, "", &mut out);
    out
}

pub fn index_layouts(
    store: &mut Store,
    source: &str,
    text: &str,
) -> Result<(), String> {
    store.replace_source(source, KIND, layout_records(source, text))
}
