use super::*;

pub struct ConfigFile {
    pub(crate) path: PathBuf,
    pub(crate) stamp: Option<Stamp>,
    pub(crate) config: Config,
    pub(crate) origin: String,
    pub(crate) problem: Option<String>,
}

