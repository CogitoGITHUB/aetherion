use crate::*;

/// call runs one tool and answers the MCP result: the envelope as the text,
/// and whether it was a refusal.
pub(crate) fn call(id: Value, name: &str, arguments: &Value, sessions_dir: &PathBuf) -> Value {
    let cap = match tools::of(name) {
        Some(found) => found,
        None => return error(id, -32602, format!("there is no tool named {}", name)),
    };
    if cap.mutates && !token_given(arguments, sessions_dir) {
        let refused = Answer::refused(
            "tool",
            RULE_GATE,
            &format!(
                "{} changes what a session does, so it needs the human's token, and it was refused",
                name
            ),
        );
        return result(id, refused.line(), true);
    }
    if !declared_agrees(&cap) {
        let refused = Answer::refused(
            "tool",
            RULE_DECLARATION,
            &format!(
                "the declaration and the gate disagree about {}, so it was refused",
                name
            ),
        );
        return result(id, refused.line(), true);
    }
    match tools::run(&cap, arguments, sessions_dir) {
        Ok(data) => {
            let answered = Answer::answered("tool", data);
            result(id, answered.line(), false)
        }
        Err(why) => {
            let refused = Answer::refused("tool", RULE_GATE, &why);
            result(id, refused.line(), true)
        }
    }
}

/// declared_agrees answers whether the declaration and the gate say the same
/// thing about one capability. The gate here is the token: a capability the
/// declaration calls a change must ask for the human's token.
pub(crate) fn declared_agrees(cap: &tools::Capability) -> bool {
    !cap.mutates || cap.name.starts_with("multiplexer_")
}

/// token_given answers whether the arguments carry the human's token: the
/// server compares it with its own, so a caller cannot grant itself the
/// right to change a session.
pub(crate) fn token_given(arguments: &Value, sessions_dir: &PathBuf) -> bool {
    let given = arguments
        .get("confirm")
        .and_then(|value| value.as_str())
        .unwrap_or("");
    let own = engine_token(sessions_dir);
    !given.is_empty() && !own.is_empty() && given == own
}

