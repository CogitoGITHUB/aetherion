use crate::*;

pub(crate) fn request_view_workspace(session: &mut Session, at: usize, request: &Value) -> Result<bool, String> {
    let what = request
        .get("what")
        .and_then(|value| value.as_str())
        .unwrap_or("list")
        .to_string();
    let project = request
        .get("project")
        .and_then(|value| value.as_str())
        .unwrap_or("")
        .to_string();
    let name = request
        .get("name")
        .and_then(|value| value.as_str())
        .unwrap_or("")
        .to_string();
    let directory = session.workspace_dir.clone();
    let workspace_name = session.workspace.clone();
    let answer = match what.as_str() {
        "create" | "project" | "open" => {
            workspace::write(&directory, &workspace_name, &what, &name)
        }
        _ => workspace::read(&directory, &workspace_name, &what),
    };
    let record = session.record(Fields {
        kind: if answer.ok { "info" } else { "fail" },
        who: "holder",
        what: "the workspace was read",
        why: "the client asked what the workspace holds",
        how: "the shared workspace engine was asked, and it answered in its own envelope",
        inputs: json!({ "what": what, "name": name, "project": project }),
        outputs: json!({ "workspace": answer.data, "why": answer.reason }),
        result: json!({}),
    });
    session.write(&record);
    answer_client(session, at, &record);
    Ok(true)
}
