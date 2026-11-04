use super::*;

/// write asks the engine to change the workspace, and answers with the
/// facts as they stand after the change.
///
/// The "what" says which change is asked for: a workspace is created, a
/// project is registered, or the context is opened on a project. The name
/// is what the change is about.
pub fn write(state_dir: &Path, workspace: &str, what: &str, name: &str) -> Answer {
    let engine = match Engine::open(state_dir) {
        Ok(engine) => engine,
        Err(why) => return refused(&why),
    };
    let (op, args) = match what {
        "create" => ("workspace.create", json!({ "name": name })),
        "project" => ("project.register", json!({ "name": name })),
        "open" => {
            // The owner names a project; the engine knows a project by its
            // own name, so the name is resolved here.
            let target = match the_project_of(&engine, workspace, name) {
                Some(target) => target,
                None => {
                    return refused(&format!(
                        "there is no project {} in the workspace",
                        name
                    ))
                }
            };
            ("context.write", json!({ "project": target }))
        }
        other => {
            return refused(&format!(
                "{} is not a change this seam makes",
                other
            ))
        }
    };
    let answered = engine.apply(&request(op, args, workspace));
    if !completed(&answered) {
        return refused(&reason(&answered));
    }
    let mut answer = read(state_dir, workspace, "list");
    if answer.ok {
        answer.data["changed"] = json!(answered.get("data").cloned().unwrap_or(json!({})));
    }
    answer
}

/// the_project_of answers the id of the project the owner named, in the
/// workspace this session works on.
pub(crate) fn the_project_of(engine: &Engine, workspace: &str, name: &str) -> Option<String> {
    let listed = engine.apply(&request("workspace.list", json!({}), workspace));
    let workspaces = list(data_of(&listed), "workspaces");
    let chosen = if workspace.is_empty() {
        if workspaces.len() == 1 {
            workspaces.first()
        } else {
            None
        }
    } else {
        workspaces
            .iter()
            .find(|one| text(one, "id").as_deref() == Some(workspace) || text(one, "name").as_deref() == Some(workspace))
    }?;
    let id = text(chosen, "id")?;
    let projects = engine.apply(&request("project.list", json!({}), &id));
    for one in list(data_of(&projects), "projects") {
        if text(&one, "id").as_deref() == Some(name) || text(&one, "name").as_deref() == Some(name) {
            return text(&one, "id");
        }
    }
    None
}

/// data_of answers the data of the engine's answer.
pub(crate) fn data_of(answer: &Value) -> &Value {
    answer.get("data").unwrap_or(&Value::Null)
}

/// request builds the engine's own request: the protocol, the name of
/// this request, the operation and its arguments.
pub(crate) fn request(op: &str, args: Value, workspace: &str) -> Value {
    let number = REQUESTS.fetch_add(1, Ordering::Relaxed);
    let mut request = json!({
        "protocol": workspace::PROTOCOL,
        "request": format!("multiplexer-{}", number),
        "op": op,
        "args": args,
    });
    if !workspace.is_empty() {
        request["workspace"] = json!(workspace);
    }
    request
}

