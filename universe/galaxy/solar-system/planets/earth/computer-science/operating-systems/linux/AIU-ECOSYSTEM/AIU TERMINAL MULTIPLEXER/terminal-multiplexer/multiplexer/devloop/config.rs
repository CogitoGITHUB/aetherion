#![allow(dead_code)]

use serde_json::{json, Value};
use std::path::{Path, PathBuf};
use std::time::SystemTime;

const DIRECTORY: &str = "aiu-multiplexer";

const CONFIG_FILE: &str = "config.json";

const ENV_NAME: &str = "AIU_MULTIPLEXER_CONFIG";

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
