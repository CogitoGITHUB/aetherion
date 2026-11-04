
use std::fs::OpenOptions;
use std::io::Write;
use std::os::unix::fs::OpenOptionsExt;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};

#[path = "log_type/log_type_structs.rs"]
mod log_type_structs;
pub(crate) use log_type_structs::*;
#[path = "log_type/log_type_methods.rs"]
mod log_type_methods;
#[path = "log_file/log_file_paths.rs"]
mod log_file_paths;
pub(crate) use log_file_paths::*;
#[cfg(test)]
#[path = "log_test/log_test_rotation.rs"]
mod tests;
