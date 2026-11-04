// One job: the bake — the config in force becomes the baked defaults in the
// state directory, and it is kept as the last good only when it reads back as
// the config that was written.
//
// The baked file is generated and says so: it is JSON, so the generator line is
// a key of its own, and the config reader ignores a key it does not know. The
// baked defaults are what a client with no user config starts from, so the bake
// is how a working config travels into a program that reads no file at startup.
//
// The check is made here and it is a read-back, not a promise: a bake that
// cannot be read back as the config it came from is not good, and the last good
// stays the last good (last_good.rs).
//
// The rebuild is MANUAL: the owner runs mux-bake when they decide, it may run
// long, and it says what it did when it is done. There is no timer and no
// watcher anywhere in here.

use super::config::{baked_path, Config};
use super::last_good;
use serde_json::Value;
use std::path::{Path, PathBuf};

/// Bake is what the bake did: the path it wrote, whether that file is good,
/// the reason when it is not, and where the last good one stands.
pub struct Bake {
    /// path is the baked defaults file this bake wrote, or tried to write.
    pub path: PathBuf,
    /// good says whether the file read back as the config that was asked for.
    pub good: bool,
    /// reason is why the bake is not good, in a sentence a person reads.
    pub reason: Option<String>,
    /// last_good is the path of the last good bake after this one ran.
    pub last_good: Option<PathBuf>,
}

impl Bake {
    /// report answers what the bake did, one line each: the path, whether it is
    /// good and why when it is not, and where the last good one stands.
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

/// baked_text answers the text of the baked file: the config as first-class
/// defaults, with the line that says the file was generated.
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

/// not_good answers a bake that did not happen, with the reason and the last
/// good record as it stands.
fn not_good(state_dir: &Path, why: String) -> Bake {
    Bake {
        path: baked_path(state_dir),
        good: false,
        reason: Some(why),
        last_good: last_good::last_good(state_dir),
    }
}

/// bake writes the config as the baked defaults, reads the file back, and
/// records it as the last good only when it reads back as the config that was
/// written. It answers the path, whether it is good, why not, and where the
/// last good one stands.
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

    // The check: the file read back, parsed, and compared with what was
    // written. A bake that cannot be read back is not a bake.
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

/// bake_file reads the config one file holds and bakes it. A file that does not
/// hold a config is refused before anything is written: nothing is baked on a
/// guess, and the last good stays.
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
