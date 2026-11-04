
use serde_json::Value;

pub fn lines(view: &str, data: &Value) -> Vec<String> {
    match view {
        "context" => context(data),
        _ => workspaces(data),
    }
}

fn workspaces(data: &Value) -> Vec<String> {
    let mut lines: Vec<String> = Vec::new();
    let held = list(data, "workspaces");
    lines.push(format!("  the workspaces: {}", held.len()));
    for one in &held {
        let name = text(one, "name").unwrap_or_default();
        let id = text(one, "id").unwrap_or_default();
        lines.push(format!("    {}  {}", id, name));
        let projects = list(one, "projects");
        lines.push(format!("      the projects: {}", projects.len()));
        for project in &projects {
            let project_name = text(project, "name").unwrap_or_default();
            let project_id = text(project, "id").unwrap_or_default();
            let roots = strings(project, "roots");
            let mut line = format!("        {}  {}", project_id, project_name);
            if !roots.is_empty() {
                line.push_str(&format!("  {}", roots.join(", ")));
            }
            lines.push(line);
        }
        let context = one.get("context").cloned().unwrap_or(Value::Null);
        lines.push(format!("      the context: {}", the_context(&context)));
    }
    if held.is_empty() {
        lines.push("  there is no workspace yet".to_string());
    }
    lines.push(format!("  the project: {}", the_project(data)));
    lines
}

fn context(data: &Value) -> Vec<String> {
    let mut lines: Vec<String> = Vec::new();
    lines.push(format!("  the workspace: {}", the_workspace(data)));
    lines.push(format!("  the project: {}", the_project(data)));
    let held = list(data, "workspaces");
    for one in &held {
        let context = one.get("context").cloned().unwrap_or(Value::Null);
        lines.push(format!("  the resources: {}", strings(&context, "resources").len()));
        for resource in strings(&context, "resources") {
            lines.push(format!("    {}", resource));
        }
    }
    lines
}

fn the_workspace(data: &Value) -> String {
    let id = text(data, "workspace").unwrap_or_default();
    if id.is_empty() {
        return "none".to_string();
    }
    for one in list(data, "workspaces") {
        if text(&one, "id").as_deref() == Some(id.as_str()) {
            return text(&one, "name").unwrap_or(id);
        }
    }
    id
}

fn the_project(data: &Value) -> String {
    let project = text(data, "project").unwrap_or_default();
    if project.is_empty() {
        return "none".to_string();
    }
    project
}

fn the_context(context: &Value) -> String {
    let project = text(context, "project").unwrap_or_default();
    let resources = strings(context, "resources");
    if project.is_empty() {
        return format!("no project, {} resources", resources.len());
    }
    format!("the project {}, {} resources", project, resources.len())
}

fn text(value: &Value, key: &str) -> Option<String> {
    value
        .get(key)
        .and_then(|part| part.as_str())
        .map(|found| found.to_string())
}

fn strings(value: &Value, key: &str) -> Vec<String> {
    value
        .get(key)
        .and_then(|part| part.as_array())
        .map(|found| {
            found
                .iter()
                .filter_map(|part| part.as_str())
                .map(|part| part.to_string())
                .collect()
        })
        .unwrap_or_default()
}

fn list(value: &Value, key: &str) -> Vec<Value> {
    value
        .get(key)
        .and_then(|part| part.as_array())
        .cloned()
        .unwrap_or_default()
}

#[cfg(test)]
#[path = "workspace_test/workspace_test_behavior.rs"]
mod tests;
