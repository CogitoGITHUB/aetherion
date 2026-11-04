use super::*;

/// Capability is one thing an agent may do, as the declaration says it.
pub struct Capability {
    pub name: String,
    pub mutates: bool,
    pub description: String,
}

/// capabilities answers every declared capability, in the order of the
/// declaration.
pub fn capabilities() -> Vec<Capability> {
    let declared: Value = match serde_json::from_str(DECLARATION) {
        Ok(value) => value,
        Err(_) => return Vec::new(),
    };
    let list = match declared.as_array() {
        Some(items) => items.clone(),
        None => return Vec::new(),
    };
    list.iter()
        .filter_map(|item| {
            let name = item.get("name")?.as_str()?.to_string();
            let mutates = item.get("mutates").and_then(|v| v.as_bool()).unwrap_or(false);
            let description = item
                .get("description")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string();
            Some(Capability {
                name,
                mutates,
                description,
            })
        })
        .collect()
}

/// of answers the capability of that name, or nothing.
pub fn of(name: &str) -> Option<Capability> {
    capabilities().into_iter().find(|cap| cap.name == name)
}

/// schema answers the input shape of one capability, the way the editor
/// declares it: the arguments in order, and the human's token when the tool
/// changes something.
pub fn schema(cap: &Capability) -> Value {
    let mut properties = serde_json::Map::new();
    properties.insert(
        "session".to_string(),
        json!({
            "type": "string",
            "description": "the session's name under the sessions directory"
        }),
    );
    properties.insert(
        "args".to_string(),
        json!({
            "type": "array",
            "description": "the arguments of the tool, in order"
        }),
    );
    properties.insert(
        "since".to_string(),
        json!({
            "type": "number",
            "description": "the record number to start from"
        }),
    );
    properties.insert(
        "data".to_string(),
        json!({
            "type": "string",
            "description": "the text to send to the session's shell"
        }),
    );
    properties.insert(
        "pane".to_string(),
        json!({
            "type": "string",
            "description": "the pane of the session to act on"
        }),
    );
    properties.insert(
        "words".to_string(),
        json!({
            "type": "array",
            "description": "the words of the command, in order: tab new, pane new, scroll up, copy PANE FIRST LAST, paste PANE"
        }),
    );
    properties.insert(
        "confirm".to_string(),
        json!({
            "type": "string",
            "description": "the human's token; a change needs it"
        }),
    );
    let required: Vec<Value> = if cap.mutates {
        vec![Value::from("confirm")]
    } else {
        Vec::new()
    };
    json!({
        "type": "object",
        "properties": Value::Object(properties),
        "required": Value::Array(required)
    })
}

