use super::*;

/// ConfigFile is the config in force and the file it follows: the path, what
/// the file looked like when it was read, what it said, and where it came
/// from in words a person reads.
pub struct ConfigFile {
    pub(crate) path: PathBuf,
    pub(crate) stamp: Option<Stamp>,
    pub(crate) config: Config,
    pub(crate) origin: String,
    pub(crate) problem: Option<String>,
}

