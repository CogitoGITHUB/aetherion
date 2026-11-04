use crate::*;

/// ask_once connects to another session's socket, sends one request, and
/// answers the one line that comes back. It is a single exchange: no clock and
/// no retry, so a session that does not answer is a session that was not
/// touched.
pub(crate) fn ask_once(socket: &Path, request: &Value) -> Result<Value, String> {
    let fd = connect(socket)?;
    let mut line = request.to_string();
    line.push('\n');
    write_to(fd, line.as_bytes())?;
    let mut answer = String::new();
    while !answer.contains('\n') {
        let mut buffer = [0u8; 4096];
        let got = facade::read_bytes(fd, &mut buffer)?;
        if got == 0 {
            break;
        }
        answer.push_str(&String::from_utf8_lossy(&buffer[..got]));
    }
    close(fd);
    let first = answer.lines().next().unwrap_or("").to_string();
    serde_json::from_str(&first)
        .map_err(|why| format!("the answer is not a record: {}", why))
}

