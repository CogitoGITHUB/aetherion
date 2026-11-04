
use serde_json::Value;

pub const EXIT_OK: i32 = 0;

pub const EXIT_REFUSAL: i32 = 2;

pub const EXIT_CANNOT_RUN: i32 = 3;

pub const PROGRAM: &str = "aiu-multiplexer";

pub const VERSION: &str = "1";

pub struct Answer {
    pub kind: String,
    pub ok: bool,
    pub data: Value,
    pub refusal: Value,
    pub events: Value,
}

impl Answer {
    pub fn answered(kind: &str, data: Value) -> Answer {
        Answer {
            kind: kind.to_string(),
            ok: true,
            data,
            refusal: Value::Object(serde_json::Map::new()),
            events: Value::Array(Vec::new()),
        }
    }

    pub fn refused(kind: &str, rule: &str, message: &str) -> Answer {
        let mut refusal = serde_json::Map::new();
        refusal.insert("rule".to_string(), Value::from(rule));
        refusal.insert("message".to_string(), Value::from(message));
        Answer {
            kind: kind.to_string(),
            ok: false,
            data: Value::Object(serde_json::Map::new()),
            refusal: Value::Object(refusal),
            events: Value::Array(Vec::new()),
        }
    }

    pub fn line(&self) -> String {
        format!(
            "{{\"program\":\"{}\",\"version\":\"{}\",\"kind\":{},\"ok\":{},\"data\":{},\"refusal\":{},\"events\":{}}}",
            PROGRAM,
            VERSION,
            quoted(&self.kind),
            self.ok,
            self.data,
            self.refusal,
            self.events
        )
    }
}

fn quoted(text: &str) -> String {
    Value::from(text).to_string()
}
