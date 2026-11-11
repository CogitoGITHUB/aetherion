#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Record {
    pub kind: String,
    pub key: String,
    pub source: String,
    pub fields: Vec<(String, String)>,
}

impl Record {
    pub fn new(kind: &str, key: &str, source: &str) -> Record {
        Record {
            kind: kind.to_string(),
            key: key.to_string(),
            source: source.to_string(),
            fields: Vec::new(),
        }
    }

    pub fn with_field(mut self, name: &str, value: &str) -> Record {
        self.fields.push((name.to_string(), value.to_string()));
        self
    }

    pub fn field(&self, name: &str) -> Option<&str> {
        self.fields
            .iter()
            .find(|pair| pair.0 == name)
            .map(|pair| pair.1.as_str())
    }
}
