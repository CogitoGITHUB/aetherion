use crate::*;

/// answer_client puts one record on one client's wire and says so when it
/// cannot: a client that gets no answer must hear why.
///
/// The answer is marked as the last one of that request, so a reader knows
/// when the answer is complete without waiting for the connection to close.
pub(crate) fn answer_client(session: &mut Session, at: usize, record: &Value) {
    let fd = session.clients[at].fd;
    let mut answer = record.clone();
    if let Some(result) = answer.get_mut("result").and_then(|value| value.as_object_mut()) {
        result.insert("final".to_string(), Value::Bool(true));
    }
    if let Err(why) = write_to(fd, record_line(&answer).as_bytes()) {
        eprintln!("holder: the client on fd {} was not answered: {}", fd, why);
    }
}

/// answer_client_more puts one record on a client's wire without marking it
/// as the last one: the client stays and watches what comes next.
pub(crate) fn answer_client_more(session: &mut Session, at: usize, record: &Value) {
    let fd = session.clients[at].fd;
    if let Err(why) = write_to(fd, record_line(record).as_bytes()) {
        eprintln!("holder: the client on fd {} was not answered: {}", fd, why);
    }
}

/// record_line answers one record as it goes on the wire: one JSON object,
/// one line. The newline is what makes a line a line for the reader on the
/// other end.
pub(crate) fn record_line(record: &Value) -> String {
    let mut text = record.to_string();
    text.push('\n');
    text
}

/// close closes one descriptor and says nothing.
pub(crate) fn close(fd: c_int) {
    if fd >= 0 {
        unsafe {
            libc::close(fd);
        }
    }
}

/// utc_now answers the wall clock as a person reads it, without a date
/// library: the kernel holds the broken-down time and this formats it.
pub(crate) fn utc_now() -> String {
    let now = unsafe { libc::time(std::ptr::null_mut()) };
    let mut parts: libc::tm = unsafe { std::mem::zeroed() };
    unsafe {
        libc::gmtime_r(&now, &mut parts);
    }
    format!(
        "{:04}-{:02}-{:02}T{:02}:{:02}:{:02}Z",
        parts.tm_year + 1900,
        parts.tm_mon + 1,
        parts.tm_mday,
        parts.tm_hour,
        parts.tm_min,
        parts.tm_sec
    )
}

