use crate::*;

pub(crate) fn request_view_state(session: &mut Session, at: usize, _request: &Value) -> Result<bool, String> {
    let record = session.state("the client asked for the state");
    session.write(&record);
    answer_client(session, at, &record);
    // The client stays: a screen asks for the state and then keeps
    // asking things of the same connection.
    Ok(true)
}
