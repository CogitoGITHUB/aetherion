use super::*;

pub fn config_path() -> Option<PathBuf> {
    if let Ok(named) = std::env::var(ENV_NAME) {
        if named.is_empty() == false {
            return Some(PathBuf::from(named));
        }
    }
    if let Ok(home) = std::env::var("XDG_CONFIG_HOME") {
        if home.is_empty() == false {
            return Some(PathBuf::from(home).join(DIRECTORY).join(CONFIG_FILE));
        }
    }
    if let Ok(home) = std::env::var("HOME") {
        if home.is_empty() == false {
            return Some(
                PathBuf::from(home)
                    .join(".config")
                    .join(DIRECTORY)
                    .join(CONFIG_FILE),
            );
        }
    }
    None
}

pub fn baked_path(state_dir: &Path) -> PathBuf {
    state_dir.join(BAKED_DIR).join(CONFIG_FILE)
}

