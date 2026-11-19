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
            if block.name == "settings" {
                let key = format!("{}:{}", source, block.line);
                out.push(
                    Record::new(KIND, &key, source)
                        .with_field("what", "settings")
                        .with_field("layout", parent)
                        .with_field("line", &block.line.to_string())
                        .with_field("width", &get("width"))
                        .with_field("height", &get("height"))
                        .with_field("gap", &get("gap"))
                        .with_field("stepx", &get("stepx"))
                        .with_field("stepy", &get("stepy"))
                        .with_field("margin", &get("margin"))
                        .with_field("pad", &get("pad"))
                        .with_field("head", &get("head"))
                        .with_field("curve", &get("curve"))
                        .with_field("scope", &get("scope"))
                        .with_field("padv", &get("padv"))
                        .with_field("padh", &get("padh"))
                        .with_field("titlesize", &get("titlesize"))
                        .with_field("descsize", &get("descsize"))
                        .with_field("labelsize", &get("labelsize")),
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
