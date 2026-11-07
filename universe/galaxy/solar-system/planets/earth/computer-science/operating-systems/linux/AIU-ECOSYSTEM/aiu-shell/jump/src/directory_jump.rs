use crate::config;
use crate::db::{Database, Stream, StreamOptions};
use crate::util;
use anyhow::Result;
use std::path::Path;

pub fn remember_directory(path: &Path) {
    let _ = try_remember_directory(path);
}

fn try_remember_directory(path: &Path) -> Result<()> {
    let exclude_dirs = config::exclude_dirs()?;
    let max_age = config::maxage()?;
    let now = util::current_time()?;
    let resolved = if config::resolve_symlinks() {
        util::canonicalize(path)?
    } else {
        util::resolve_path(path)?
    };
    let text = util::path_to_str(&resolved)?;
    if text.contains("\n") || text.contains("\r") {
        return Ok(());
    }
    if exclude_dirs.iter().any(|glob| glob.matches(text)) {
        return Ok(());
    }
    if !Path::new(text).is_dir() {
        return Ok(());
    }
    let mut database = Database::open()?;
    database.add_update(text, 1.0, now);
    if database.dirty() {
        database.age(max_age);
    }
    database.save()
}

pub fn best_match(words: &str) -> Option<String> {
    let keywords: Vec<&str> = words.split_whitespace().collect();
    if keywords.is_empty() {
        return None;
    }
    let now = util::current_time().ok()?;
    let exclude = config::exclude_dirs().ok()?;
    let mut database = Database::open().ok()?;
    let found = {
        let options = StreamOptions::new(now)
            .with_keywords(keywords)
            .with_exclude(exclude)
            .with_exists(true)
            .with_resolve_symlinks(config::resolve_symlinks());
        let mut stream = Stream::new(&mut database, options);
        stream.next().map(|dir| dir.path.to_string())
    };
    let _ = database.save();
    found
}
