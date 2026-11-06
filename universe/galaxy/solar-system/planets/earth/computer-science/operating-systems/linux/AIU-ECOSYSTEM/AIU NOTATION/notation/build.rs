use std::env;
use std::fs;
use std::path::Path;

fn main() {
    println!("cargo:rerun-if-changed=blocktypes");
    let mut entries: Vec<_> = fs::read_dir("blocktypes")
        .expect("blocktypes folder missing")
        .map(|e| e.expect("unreadable blocktypes entry").path())
        .collect();
    entries.sort();
    let mut names: Vec<String> = Vec::new();
    let mut opaque: Vec<String> = Vec::new();
    for path in entries {
        if path.extension().and_then(|e| e.to_str()) != Some("blocktype") {
            continue;
        }
        let text = fs::read_to_string(&path).expect("unreadable block type file");
        let mut name: Option<String> = None;
        let mut is_opaque = false;
        for line in text.lines() {
            if let Some(v) = line.strip_prefix("name:") {
                name = Some(v.trim().to_string());
            }
            if let Some(v) = line.strip_prefix("opaque:") {
                is_opaque = v.trim() == "yes";
            }
        }
        let name = name.unwrap_or_else(|| panic!("{} has no name line", path.display()));
        if is_opaque {
            opaque.push(name.clone());
        }
        names.push(name);
    }
    let list = |v: &Vec<String>| v.iter().map(|n| format!("{:?}", n)).collect::<Vec<_>>().join(", ");
    let out = format!(
        "pub const BLOCK_NAMES: &[&str] = &[{}];\npub const OPAQUE_NAMES: &[&str] = &[{}];\n",
        list(&names),
        list(&opaque)
    );
    let target = Path::new(&env::var("OUT_DIR").expect("OUT_DIR missing")).join("block-types.rs");
    fs::write(target, out).expect("cannot write block-types.rs");
}
