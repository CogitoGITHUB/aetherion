use super::*;

impl ConfigFile {
    /// start is the config as a program finds it: the file the environment
    /// names, else the last good bake in this state directory, else the
    /// built-in defaults.
    pub fn start(state_dir: &Path) -> ConfigFile {
        ConfigFile::at(state_dir, config_path())
    }

    /// at is start with the sources given, so a caller that knows its config
    /// file needs no environment at all. The baked defaults stay in the state
    /// directory.
    pub fn at(state_dir: &Path, named: Option<PathBuf>) -> ConfigFile {
        let baked = baked_path(state_dir);
        let followed = named.clone().unwrap_or_else(|| baked.clone());

        // 1. the file the environment names, when it is there. A file that
        //    does not parse does not take the program down: the last good
        //    bake answers, and the reason is kept for the message line.
        if let Some(path) = &named {
            if stamp_of(path).is_some() {
                let stamp = stamp_of(path);
                match Config::read(path) {
                    Ok(config) => {
                        return ConfigFile {
                            path: path.clone(),
                            stamp,
                            config,
                            origin: path.display().to_string(),
                            problem: None,
                        }
                    }
                    Err(why) => {
                        let (config, origin) = match Config::read(&baked) {
                            Ok(found) => (
                                found,
                                format!("the last good bake at {}", baked.display()),
                            ),
                            Err(_) => (Config::defaults(), "the built-in defaults".to_string()),
                        };
                        return ConfigFile {
                            path: path.clone(),
                            stamp,
                            config,
                            origin,
                            problem: Some(format!("the config is not used: {}", why)),
                        };
                    }
                }
            }
        }

        // 2. the baked defaults, when a bake has written them.
        if let Ok(config) = Config::read(&baked) {
            return ConfigFile {
                path: baked.clone(),
                stamp: stamp_of(&baked),
                config,
                origin: baked.display().to_string(),
                problem: None,
            };
        }

        // 3. the built-in defaults. The file the environment names is still
        //    followed, so the first write of it is a change like any other.
        ConfigFile {
            path: followed,
            stamp: None,
            config: Config::defaults(),
            origin: "the built-in defaults".to_string(),
            problem: None,
        }
    }

    /// config answers the config in force now.
    pub fn config(&self) -> &Config {
        &self.config
    }

    /// path answers the file this config follows: the one the environment
    /// names when it named one, else the baked defaults.
    pub fn path(&self) -> &Path {
        &self.path
    }

    /// origin answers where the config came from, in words the client prints
    /// at its start: a path when a file answered, or the built-in defaults.
    pub fn origin(&self) -> &str {
        &self.origin
    }

    /// problem answers why a config file that is there was not used, so the
    /// client can say it in its message line. None when nothing went wrong.
    pub fn problem(&self) -> Option<&str> {
        self.problem.as_deref()
    }

    /// reload_if_changed looks at the file this config follows and answers
    /// what it found. The file is read only when its write time or its length
    /// is not the one it had when it was read: a file that did not change is
    /// not parsed again. A file that does not parse leaves the config in
    /// force and answers the reason, and the stamp is taken, so the same
    /// unchanged file is reported once and not on every turn of the loop.
    pub fn reload_if_changed(&mut self) -> Reload {
        let now = stamp_of(&self.path);
        if now == self.stamp {
            return Reload::Unchanged;
        }
        let stamp = match now {
            Some(found) => found,
            None => {
                self.stamp = None;
                return Reload::Broken(format!(
                    "the config file {} is not there any more; the config in force stays",
                    self.path.display()
                ));
            }
        };
        self.stamp = Some(stamp);
        match Config::read(&self.path) {
            Ok(config) => {
                self.config = config.clone();
                self.origin = self.path.display().to_string();
                self.problem = None;
                Reload::Changed(config)
            }
            Err(why) => Reload::Broken(format!(
                "{}; the config in force stays",
                why
            )),
        }
    }
}

