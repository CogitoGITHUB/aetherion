use crate::*;

/// pane_at answers the pane of that name, or the first pane when the name is
/// empty: the session's panes are addressed by name.
pub(crate) fn pane_at(session: &Session, name: &str) -> Result<usize, String> {
    if name.is_empty() {
        return Ok(0);
    }
    session
        .panes
        .iter()
        .position(|pane| pane.name == name)
        .ok_or_else(|| format!("there is no pane named {}", name))
}

