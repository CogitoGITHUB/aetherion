use super::*;

/// Config is what the client honors: how much of the screen's own furniture is
/// drawn (0 to 3) and whether the tab bar is drawn with it.
#[derive(Clone, Debug, PartialEq)]
pub struct Config {
    /// level is the visual level: 0 hides every row of the screen's own
    /// furniture, 3 is the most the screen draws.
    pub level: u8,
    /// tab_bar says whether the tab bar is drawn at level 1 and above.
    pub tab_bar: bool,
}

impl Config {
    /// defaults answers the config a program with no file at all runs with:
    /// level 2, the mode row, the tab bar, the specifics and the events.
    pub fn defaults() -> Config {
        Config {
            level: 2,
            tab_bar: true,
        }
    }

    /// read answers the config one file holds, with the path in the reason
    /// when it does not hold one.
    pub fn read(path: &Path) -> Result<Config, String> {
        let text = std::fs::read_to_string(path)
            .map_err(|why| format!("{} cannot be read: {}", path.display(), why))?;
        Config::from_json(&text)
            .map_err(|why| format!("{} does not hold a config: {}", path.display(), why))
    }

    /// from_json answers the config a text holds. A key the config does not
    /// know is ignored, so a newer file still runs on an older client; a value
    /// the config does know and cannot use is a reason, not a guess.
    pub fn from_json(text: &str) -> Result<Config, String> {
        let value: Value =
            serde_json::from_str(text).map_err(|why| format!("it is not JSON: {}", why))?;
        Config::from_value(&value)
    }

    /// from_value answers the config one JSON value holds.
    pub fn from_value(value: &Value) -> Result<Config, String> {
        if value.is_object() == false {
            return Err("it is not a JSON object".to_string());
        }
        let mut config = Config::defaults();
        if let Some(found) = value.get("level") {
            let level = found
                .as_u64()
                .ok_or("the level is not a whole number")?;
            if level > 3 {
                return Err(format!("the level {} is higher than 3", level));
            }
            config.level = level as u8;
        }
        if let Some(found) = value.get("tab-bar") {
            config.tab_bar = found
                .as_bool()
                .ok_or("the tab bar is not true or false")?;
        }
        Ok(config)
    }

    /// to_value answers the config as the one object the file holds.
    pub fn to_value(&self) -> Value {
        json!({ "level": self.level, "tab-bar": self.tab_bar })
    }

    /// to_json answers the config as the text a file holds, one key per line,
    /// so a person can read it and change it.
    pub fn to_json(&self) -> String {
        let mut text = serde_json::to_string_pretty(&self.to_value())
            .unwrap_or_else(|_| "{}".to_string());
        text.push('\n');
        text
    }
}

