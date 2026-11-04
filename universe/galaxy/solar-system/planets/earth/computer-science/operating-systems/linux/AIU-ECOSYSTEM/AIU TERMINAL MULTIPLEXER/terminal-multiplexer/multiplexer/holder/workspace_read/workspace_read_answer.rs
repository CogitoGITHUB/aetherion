use super::*;

pub struct Answer {
    pub ok: bool,
    pub data: Value,
    pub reason: String,
}

pub(crate) static REQUESTS: AtomicU64 = AtomicU64::new(0);

pub fn read(state_dir: &Path, workspace: &str, what: &str) -> Answer {
    let engine = match Engine::open(state_dir) {
        Ok(engine) => engine,
        Err(why) => return refused(&why),
    };
    let listed = engine.apply(&request("workspace.list", json!({}), workspace));
    if !completed(&listed) {
        return refused(&reason(&listed));
    }
    let mut held: Vec<Value> = Vec::new();
    let mut current = String::new();
    let mut project = String::new();
    for one in list(data_of(&listed), "workspaces") {
        let id = text(&one, "id").unwrap_or_default();
        let name = text(&one, "name").unwrap_or_default();
        let chosen = if workspace.is_empty() {
            held.len() == 0
        } else {
            id == workspace || name == workspace
        };
        let projects = engine.apply(&request("project.list", json!({}), &id));
        let context = engine.apply(&request("context.read", json!({}), &id));
        let context_project = data_of(&context)
            .get("context")
            .and_then(|context| text(context, "project"))
            .unwrap_or_default();
        let projects_held = list(data_of(&projects), "projects");
        let context_name = projects_held
            .iter()
            .find(|one| text(one, "id").as_deref() == Some(context_project.as_str()))
            .and_then(|one| text(one, "name"))
            .unwrap_or_else(|| context_project.clone());
        if chosen {
            current = id.clone();
            project = context_name.clone();
        }
        held.push(json!({
            "id": id,
            "name": name,
            "projects": projects_held
                .iter()
                .map(|project| json!({
                    "id": text(project, "id").unwrap_or_default(),
                    "name": text(project, "name").unwrap_or_default(),
                    "roots": strings(project, "roots"),
                    "tags": strings(project, "tags"),
                }))
                .collect::<Vec<Value>>(),
            "context": {
                "project": context_name,
                "project-id": context_project,
                "resources": data_of(&context)
                    .get("context")
                    .map(|context| strings(context, "resources"))
                    .unwrap_or_default(),
            },
        }));
    }
    Answer {
        ok: true,
        data: json!({
            "workspaces": held,
            "workspace": current,
            "project": project,
            "view": what,
        }),
        reason: String::new(),
    }
}

