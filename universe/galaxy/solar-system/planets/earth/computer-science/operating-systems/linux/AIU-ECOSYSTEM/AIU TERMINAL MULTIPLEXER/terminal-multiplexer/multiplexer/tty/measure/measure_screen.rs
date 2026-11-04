
use crate::tty;

pub struct Measured {
    pub pty_open: bool,
    pub raw_mode: bool,
    pub sized: bool,
    pub cols: u16,
    pub rows: u16,
    pub slave: String,
}

pub fn of_terminal(fd: libc::c_int, wanted: (u16, u16), slave: &str) -> Measured {
    let held = tty::window_size(fd);
    let (cols, rows) = held.unwrap_or((0, 0));
    Measured {
        pty_open: fd >= 0 && !slave.is_empty(),
        raw_mode: tty::is_raw(fd),
        sized: cols == wanted.0 && rows == wanted.1,
        cols,
        rows,
        slave: slave.to_string(),
    }
}

pub fn record(measured: &Measured) -> Vec<(&'static str, serde_json::Value)> {
    let mut fields: Vec<(&'static str, serde_json::Value)> = Vec::new();
    fields.push(("pty", serde_json::Value::Bool(measured.pty_open)));
    fields.push(("raw", serde_json::Value::Bool(measured.raw_mode)));
    fields.push(("sized", serde_json::Value::Bool(measured.sized)));
    fields.push(("cols", serde_json::Value::from(measured.cols)));
    fields.push(("rows", serde_json::Value::from(measured.rows)));
    fields.push(("slave", serde_json::Value::from(measured.slave.clone())));
    fields
}
