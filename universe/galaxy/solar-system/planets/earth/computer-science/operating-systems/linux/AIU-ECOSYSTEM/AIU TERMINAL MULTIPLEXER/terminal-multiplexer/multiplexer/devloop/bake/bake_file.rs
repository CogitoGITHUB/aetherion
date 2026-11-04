
use super::config::{baked_path, Config};
use super::last_good;
use serde_json::Value;
use std::path::{Path, PathBuf};

pub struct Bake {
    pub path: PathBuf,
    pub good: bool,
    pub reason: Option<String>,
    pub last_good: Option<PathBuf>,
}

impl Bake {
    pub fn report(&self) -> Vec<String> {
        let mut lines: Vec<String> = Vec::new();
        lines.push(format!("the baked defaults: {}", self.path.display()));
        if self.good {
            lines.push(
                "good: the bake was read back, and it is the config that was asked for"
                    .to_string(),
            );
            lines.push(format!("the last good is now: {}", self.path.display()));
        } else {
            let why = self
                .reason
                .clone()
                .unwrap_or_else(|| "the bake gave no reason, which is a fault of its own".to_string());
            lines.push(format!("not good: {}", why));
            match &self.last_good {
                Some(path) => lines.push(format!("the last good stays: {}", path.display())),
                None => lines.push(
                    "the last good: none yet, and this bake did not become one".to_string(),
                ),
            }
        }
        lines
    }
}

fn baked_text(config: &Config) -> String {
    let mut value = config.to_value();
    if let Value::Object(fields) = &mut value {
        fields.insert(
            "generated-by".to_string(),
            Value::from("mux-bake — the config as first-class defaults; do not edit by hand"),
        );
    }
    let mut text = serde_json::to_string_pretty(&value).unwrap_or_else(|_| "{}".to_string());
    text.push('\n');
    text
}

fn not_good(state_dir: &Path, why: String) -> Bake {
    Bake {
        path: baked_path(state_dir),
        good: false,
        reason: Some(why),
        last_good: last_good::last_good(state_dir),
    }
}

pub fn bake(state_dir: &Path, config: &Config) -> Bake {
    let path = baked_path(state_dir);
    if let Some(parent) = path.parent() {
        if let Err(why) = std::fs::create_dir_all(parent) {
            return not_good(
                state_dir,
                format!(
                    "the baked directory {} cannot be made: {}",
                    parent.display(),
                    why
                ),
            );
        }
    }

    let text = baked_text(config);
    if let Err(why) = std::fs::write(&path, text.as_bytes()) {
        return not_good(
            state_dir,
            format!("{} cannot be written: {}", path.display(), why),
        );
    }

    let back = match last_good::read_text(&path) {
        Ok(text) => text,
        Err(why) => return not_good(state_dir, why),
    };
    match Config::from_json(&back) {
        Err(why) => not_good(
            state_dir,
            format!("{} does not read back as a config: {}", path.display(), why),
        ),
        Ok(found) if found != *config => not_good(
            state_dir,
            format!(
                "{} reads back as another config than the one that was written",
                path.display()
            ),
        ),
        Ok(_) => match last_good::keep_last_good(state_dir, &path) {
            Ok(()) => Bake {
                path: path.clone(),
                good: true,
                reason: None,
                last_good: Some(path),
            },
            Err(why) => not_good(
                state_dir,
                format!("the bake is good and it could not be recorded: {}", why),
            ),
        },
    }
}

pub fn bake_file(state_dir: &Path, source: &Path) -> Bake {
    match Config::read(source) {
        Ok(config) => bake(state_dir, &config),
        Err(why) => not_good(
            state_dir,
            format!(
                "{}; nothing was baked and the last good stays" ,
                why
            ),
        ),
    }
}


#[cfg(test)]
#[path = "bake_test/bake_test_behavior.rs"]
mod tests;
