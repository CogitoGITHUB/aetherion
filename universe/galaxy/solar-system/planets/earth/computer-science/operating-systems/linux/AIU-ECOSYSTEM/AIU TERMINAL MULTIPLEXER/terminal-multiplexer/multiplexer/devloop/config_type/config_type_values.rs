use super::*;

#[derive(Clone, Debug, PartialEq)]
pub struct Config {
    pub level: u8,
    pub tab_bar: bool,
}

impl Config {
    pub fn defaults() -> Config {
        Config {
            level: 2,
            tab_bar: true,
        }
    }

    pub fn read(path: &Path) -> Result<Config, String> {
        let text = std::fs::read_to_string(path)
            .map_err(|why| format!("{} cannot be read: {}", path.display(), why))?;
        Config::from_json(&text)
            .map_err(|why| format!("{} does not hold a config: {}", path.display(), why))
    }

    pub fn from_json(text: &str) -> Result<Config, String> {
        let value: Value =
            serde_json::from_str(text).map_err(|why| format!("it is not JSON: {}", why))?;
        Config::from_value(&value)
    }

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

    pub fn to_value(&self) -> Value {
        json!({ "level": self.level, "tab-bar": self.tab_bar })
    }

    pub fn to_json(&self) -> String {
        let mut text = serde_json::to_string_pretty(&self.to_value())
            .unwrap_or_else(|_| "{}".to_string());
        text.push('\n');
        text
    }
}

