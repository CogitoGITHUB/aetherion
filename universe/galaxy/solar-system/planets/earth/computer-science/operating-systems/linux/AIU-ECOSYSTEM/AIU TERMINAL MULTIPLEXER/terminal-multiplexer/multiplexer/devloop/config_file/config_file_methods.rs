use super::*;

impl ConfigFile {
    pub fn start(state_dir: &Path) -> ConfigFile {
        ConfigFile::at(state_dir, config_path())
    }

    pub fn at(state_dir: &Path, named: Option<PathBuf>) -> ConfigFile {
        let baked = baked_path(state_dir);
        let followed = named.clone().unwrap_or_else(|| baked.clone());

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

        if let Ok(config) = Config::read(&baked) {
            return ConfigFile {
                path: baked.clone(),
                stamp: stamp_of(&baked),
                config,
                origin: baked.display().to_string(),
                problem: None,
            };
        }

        ConfigFile {
            path: followed,
            stamp: None,
            config: Config::defaults(),
            origin: "the built-in defaults".to_string(),
            problem: None,
        }
    }

    pub fn config(&self) -> &Config {
        &self.config
    }

    pub fn path(&self) -> &Path {
        &self.path
    }

    pub fn origin(&self) -> &str {
        &self.origin
    }

    pub fn problem(&self) -> Option<&str> {
        self.problem.as_deref()
    }

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

