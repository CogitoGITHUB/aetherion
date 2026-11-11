use std::fs;
use std::path::{Path, PathBuf};

use crate::database_file_format::save;
use crate::database_index_blocks::index_blocks;
use crate::database_index_files::index_file;
use crate::database_index_links::index_links;
use crate::database_index_names::{duplicate_names, index_names};
use crate::database_index_tags::index_tags;
use crate::database_index_todos::index_todos;
use crate::database_store::Store;

fn skipped_folder(name: &str) -> bool {
    name == "target" || name == "compiled" || name == ".notation" || name == ".git"
}

fn collect_aiu_files(folder: &Path, out: &mut Vec<PathBuf>) -> Result<(), String> {
    let entries = fs::read_dir(folder)
        .map_err(|e| format!("cannot read folder {}: {}", folder.display(), e))?;
    let mut paths: Vec<PathBuf> = entries.filter_map(|e| e.ok()).map(|e| e.path()).collect();
    paths.sort();
    for path in paths {
        let name = match path.file_name() {
            Some(n) => n.to_string_lossy().to_string(),
            None => String::new(),
        };
        if path.is_dir() {
            if !skipped_folder(&name) {
                collect_aiu_files(&path, out)?;
            }
        } else if name.ends_with(".aiu") {
            out.push(path);
        }
    }
    Ok(())
}

fn source_name(root: &Path, path: &Path) -> String {
    let relative = path.strip_prefix(root).unwrap_or(path);
    let parts: Vec<String> = relative
        .components()
        .map(|c| c.as_os_str().to_string_lossy().to_string())
        .collect();
    parts.join("/")
}

pub fn index_folder(root: &Path) -> Result<String, String> {
    let mut files: Vec<PathBuf> = Vec::new();
    collect_aiu_files(root, &mut files)?;
    if let Some(first) = files.first() {
        if let Some(found) = crate::block_registry::load_near(first.as_path()) {
            eprintln!("notation: block types from {}", found);
        }
    }
    let mut store = Store::new();
    let mut unreadable = 0usize;
    let mut indexed = 0usize;
    for path in &files {
        let source = source_name(root, path);
        let text = match fs::read_to_string(path) {
            Ok(t) => t,
            Err(_) => {
                unreadable += 1;
                continue;
            }
        };
        index_file(&mut store, &source, &text)?;
        index_blocks(&mut store, &source, &text)?;
        index_tags(&mut store, &source, &text)?;
        index_todos(&mut store, &source, &text)?;
        index_links(&mut store, &source, &text)?;
        index_names(&mut store, &source, &text)?;
        indexed += 1;
    }
    for (name, places) in duplicate_names(&store) {
        eprintln!("notation: duplicate name {} at {}", name, places.join(", "));
    }
    let database = root.join(".notation").join("index.db");
    save(&store, &database).map_err(|e| format!("cannot save {}: {}", database.display(), e))?;
    Ok(format!(
        "indexed {} files, {} records, {} unreadable, saved {}",
        indexed,
        store.len(),
        unreadable,
        database.display()
    ))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::database_file_format::load;

    const PAGE: &str = "paragraph start\ntodo: one\nparagraph end\n\nlink start\nname: l\ntarget: t\nlink end\n";
    const TITLED: &str = "title start\ntags: x\nTitle\ntitle end\n";

    fn make_folder(name: &str) -> PathBuf {
        let root = std::env::temp_dir().join(format!("aiu-index-folder-{}-{}", name, std::process::id()));
        let _ = fs::remove_dir_all(&root);
        fs::create_dir_all(root.join("a").join("target")).unwrap();
        fs::create_dir_all(root.join(".notation")).unwrap();
        fs::write(root.join("a").join("page.aiu"), PAGE).unwrap();
        fs::write(root.join("a").join("target").join("skip.aiu"), PAGE).unwrap();
        fs::write(root.join(".notation").join("admin.aiu"), PAGE).unwrap();
        fs::write(root.join("b.aiu"), TITLED).unwrap();
        fs::write(root.join("notes.txt"), PAGE).unwrap();
        root
    }

    #[test]
    fn the_folder_is_walked_and_the_database_is_saved() {
        let root = make_folder("walk");
        let summary = index_folder(&root).unwrap();
        assert!(summary.starts_with("indexed 2 files"));
        let store = load(&root.join(".notation").join("index.db")).unwrap();
        assert_eq!(store.of_kind("file").len(), 2);
        assert!(store.get("file", "a/page.aiu").is_some());
        assert!(store.get("file", "b.aiu").is_some());
        assert_eq!(store.of_kind("todo").len(), 1);
        assert_eq!(store.of_kind("link").len(), 1);
        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn target_and_notation_and_other_extensions_are_skipped() {
        let root = make_folder("skip");
        index_folder(&root).unwrap();
        let store = load(&root.join(".notation").join("index.db")).unwrap();
        assert!(store.get("file", "a/target/skip.aiu").is_none());
        assert!(store.get("file", ".notation/admin.aiu").is_none());
        assert!(store.get("file", "notes.txt").is_none());
        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn indexing_twice_gives_the_same_database() {
        let root = make_folder("twice");
        index_folder(&root).unwrap();
        let first = load(&root.join(".notation").join("index.db")).unwrap().len();
        index_folder(&root).unwrap();
        let second = load(&root.join(".notation").join("index.db")).unwrap().len();
        assert_eq!(first, second);
        let _ = fs::remove_dir_all(&root);
    }
}
