use crate::*;

pub(crate) fn request_view_git(session: &mut Session, at: usize, request: &Value) -> Result<bool, String> {
    let what = request
        .get("what")
        .and_then(|value| value.as_str())
        .unwrap_or("overview")
        .to_string();
    let directory = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
    let answer = git::read(&directory, &what);
    let record = session.record(Fields {
        kind: if answer.ok { "info" } else { "fail" },
        who: "holder",
        what: "the git state was read",
        why: "the client asked what git says",
        how: "the shared git layer was asked, and it only reads",
        inputs: json!({ "what": what, "path": directory.display().to_string() }),
        outputs: json!({ "git": answer.data }),
        result: json!({}),
    });
    session.write(&record);
    answer_client(session, at, &record);
    Ok(true)
}
