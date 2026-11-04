use crate::*;

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

pub(crate) fn answer_client_more(session: &mut Session, at: usize, record: &Value) {
    let fd = session.clients[at].fd;
    if let Err(why) = write_to(fd, record_line(record).as_bytes()) {
        eprintln!("holder: the client on fd {} was not answered: {}", fd, why);
    }
}

pub(crate) fn record_line(record: &Value) -> String {
    let mut text = record.to_string();
    text.push('\n');
    text
}

pub(crate) fn close(fd: c_int) {
    if fd >= 0 {
        unsafe {
            libc::close(fd);
        }
    }
}

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

