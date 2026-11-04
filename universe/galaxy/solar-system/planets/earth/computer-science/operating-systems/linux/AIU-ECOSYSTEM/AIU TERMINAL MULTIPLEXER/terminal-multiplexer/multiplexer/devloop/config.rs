#![allow(dead_code)]
// One job: the config — the values the client honors, where the file is read
// from, and whether it changed since the screen last looked.
//
// The file is JSON and the keys are the wire's: one object, kebab-case names.
// The two values the client honors today are the level (how much of the
// screen's own furniture is drawn, 0 to 3) and the tab bar (whether it is
// drawn at all):
//
//   { "level": 2, "tab-bar": true }
//
// Where the file comes from, in order: the file named by
// AIU_MULTIPLEXER_CONFIG, then $XDG_CONFIG_HOME/aiu-multiplexer/config.json,
// then $HOME/.config/aiu-multiplexer/config.json, then the baked defaults in
// the state directory, then the built-in defaults.
//
// resolve is the ONE place this area reads the environment — the same rule
// the machine area keeps for the Racket side, kept here for the Rust floor
// so no other file has to spell a home path.
//
// The reload is a CHECK, never a watcher: reload_if_changed reads the file's
// write time and its length and answers whether the file really changed. There
// is no timer and no thread in here; the caller asks when its own loop turns,
// and while a config does not parse the old one stays in force.

use serde_json::{json, Value};
use std::path::{Path, PathBuf};
use std::time::SystemTime;

/// DIRECTORY is the directory under the config home that is this program's.
const DIRECTORY: &str = "aiu-multiplexer";

/// CONFIG_FILE is the name of the config file inside that directory.
const CONFIG_FILE: &str = "config.json";

/// ENV_NAME is the environment value that names a config file outright.
const ENV_NAME: &str = "AIU_MULTIPLEXER_CONFIG";

/// BAKED_DIR is the directory in the state directory the bake writes into.
const BAKED_DIR: &str = "baked";

#[path = "config_type/config_type_values.rs"]
mod config_type_values;
pub(crate) use config_type_values::*;
#[path = "config_type/config_type_reload.rs"]
mod config_type_reload;
pub(crate) use config_type_reload::*;
#[path = "config_path/config_path_locate.rs"]
mod config_path_locate;
pub(crate) use config_path_locate::*;
#[path = "config_file/config_file_type.rs"]
mod config_file_type;
pub(crate) use config_file_type::*;
#[path = "config_file/config_file_methods.rs"]
mod config_file_methods;
#[cfg(test)]
#[path = "config_test/config_test_behavior.rs"]
mod tests;
