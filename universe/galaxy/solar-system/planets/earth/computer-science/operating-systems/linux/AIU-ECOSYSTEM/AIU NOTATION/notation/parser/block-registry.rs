use std::fs;
use std::path::Path;
use std::sync::{OnceLock, RwLock};

struct Active {
    names: Vec<String>,
    opaque: Vec<String>,
}

static ACTIVE: RwLock<Option<Active>> = RwLock::new(None);
static DEFAULT_ACTIVE: OnceLock<Active> = OnceLock::new();

fn with_active<T>(read: impl Fn(&Active) -> T) -> T {
    if let Some(active) = ACTIVE.read().unwrap().as_ref() {
        return read(active);
    }
    let fallback = DEFAULT_ACTIVE.get_or_init(|| {
        read_folder(&Path::new(env!("CARGO_MANIFEST_DIR")).join("blocktypes"))
            .expect("the default blocktypes folder next to the manifest is missing or empty")
    });
    read(fallback)
}

pub fn is_registered(name: &str) -> bool {
    with_active(|a| a.names.iter().any(|n| n == name))
}

pub fn is_opaque_name(name: &str) -> bool {
    with_active(|a| a.opaque.iter().any(|n| n == name))
}

pub fn registered_names() -> Vec<String> {
    with_active(|a| a.names.clone())
}

fn read_folder(folder: &Path) -> Option<Active> {
    let mut paths: Vec<_> = fs::read_dir(folder)
        .ok()?
        .filter_map(|e| e.ok())
        .map(|e| e.path())
        .filter(|p| p.extension().and_then(|e| e.to_str()) == Some("blocktype"))
        .collect();
    paths.sort();
    let mut names: Vec<String> = Vec::new();
    let mut opaque: Vec<String> = Vec::new();
    for path in paths {
        let text = fs::read_to_string(&path).ok()?;
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
        if let Some(name) = name {
            if is_opaque {
                opaque.push(name.clone());
            }
            names.push(name);
        }
    }
    if names.is_empty() {
        None
    } else {
        Some(Active { names, opaque })
    }
}

pub fn load_near(file: &Path) -> Option<String> {
    let start = fs::canonicalize(file).ok()?;
    let mut dir = start.parent().map(|p| p.to_path_buf());
    while let Some(d) = dir {
        let folder = d.join(".notation").join("blocktypes");
        if folder.is_dir() {
            if let Some(active) = read_folder(&folder) {
                *ACTIVE.write().unwrap() = Some(active);
                return Some(folder.display().to_string());
            }
        }
        dir = d.parent().map(|p| p.to_path_buf());
    }
    None
}
