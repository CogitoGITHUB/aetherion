// One job: the proof of the read-only watch attach (TODO item 60) — a watcher
// sees the session, its own changes are refused by name, and letting it go
// leaves the session untouched.
//
// The holder here is the real binary: it is started on a scratch directory, and
// the test speaks its wire. The watcher is a connection that attached with
// role "watch", which is what `client --op watch` sends; the refusals are the
// holder's own words, not the test's.

use serde_json::{json, Value};
use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::UnixStream;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};

const EVENT_CONTRACT: &str = "event-log-format/1";
const HOLDER_CONTRACT: &str = "multiplexer-holder/1";

/// a_scratch is a directory of this test's own, emptied first.
fn a_scratch(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("mux-watch-{}-{}", std::process::id(), name));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).expect("the scratch directory is made");
    dir
}

/// a_holder starts the real holder on the scratch directory, and answers it.
fn a_holder(dir: &Path) -> Child {
    Command::new(env!("CARGO_BIN_EXE_holder"))
        .args(["--state-dir", &dir.display().to_string()])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .expect("the holder starts")
}

/// wait_for_socket waits for the holder's socket, and the wait ends on the
/// filesystem event that creates it — the same rule as the client's own wait,
/// so the test adds no timer.
fn wait_for_socket(path: &Path) {
    if path.exists() {
        return;
    }
    let dir = path.parent().expect("the socket has a directory");
    let watcher = unsafe { libc::inotify_init() };
    assert!(watcher >= 0, "the phone can watch the directory");
    let watched = std::ffi::CString::new(dir.as_os_str().as_encoded_bytes())
        .expect("the path holds no nul byte");
    let watch = unsafe {
        libc::inotify_add_watch(watcher, watched.as_ptr(), libc::IN_CREATE | libc::IN_MOVED_TO)
    };
    assert!(watch >= 0, "the directory can be watched");
    let mut buffer = [0u8; 4096];
    while !path.exists() {
        let got = unsafe {
            libc::read(watcher, buffer.as_mut_ptr() as *mut libc::c_void, buffer.len())
        };
        assert!(got > 0, "the holder created its socket");
    }
    unsafe {
        libc::close(watcher);
    }
}

/// connect opens the session's socket.
fn connect(socket: &Path) -> (BufReader<UnixStream>, UnixStream) {
    let stream = UnixStream::connect(socket).expect("the holder takes the connection");
    let writer = stream.try_clone().expect("the socket is copied");
    (BufReader::new(stream), writer)
}

/// send puts one request on the wire.
fn send(writer: &mut UnixStream, request: Value) {
    writer
        .write_all(format!("{}\n", request).as_bytes())
        .expect("the request is sent");
}

/// read_one reads one record.
fn read_one(reader: &mut BufReader<UnixStream>) -> Value {
    let mut line = String::new();
    let got = reader.read_line(&mut line).expect("the holder answers");
    assert!(got > 0, "the holder answers one record");
    serde_json::from_str(line.trim()).expect("the answer is one record")
}

/// ask sends one request and answers the last record of its answer.
fn ask(reader: &mut BufReader<UnixStream>, writer: &mut UnixStream, request: Value) -> Value {
    send(writer, request);
    loop {
        let record = read_one(reader);
        let final_one = record
            .get("result")
            .and_then(|result| result.get("final"))
            .and_then(|flag| flag.as_bool())
            .unwrap_or(false);
        if final_one {
            return record;
        }
    }
}

/// attach connects and attaches with one role, and answers the state record.
fn attach(socket: &Path, role: &str) -> (BufReader<UnixStream>, UnixStream) {
    let (mut reader, mut writer) = connect(socket);
    send(
        &mut writer,
        json!({
            "op": "attach",
            "client": "watch-probe/1",
            "role": role,
            "event-contract": EVENT_CONTRACT,
            "holder-contract": HOLDER_CONTRACT
        }),
    );
    let state = read_one(&mut reader);
    assert_eq!(
        state.get("kind").and_then(|kind| kind.as_str()),
        Some("info"),
        "the attach is answered with the state: {:?}",
        state
    );
    assert!(
        state.get("outputs").and_then(|outputs| outputs.get("panes")).is_some(),
        "the watcher sees the panes: {:?}",
        state
    );
    (reader, writer)
}

#[test]
fn a_watcher_sees_the_session_and_cannot_change_it() {
    let dir = a_scratch("readonly");
    let socket = dir.join("holder.sock");
    let mut holder = a_holder(&dir);
    wait_for_socket(&socket);

    let (mut reader, mut writer) = attach(&socket, "watch");

    // 1. the watcher reads: the journal is free.
    let read = ask(&mut reader, &mut writer, json!({ "op": "read", "since": 0 }));
    assert_eq!(
        read.get("kind").and_then(|kind| kind.as_str()),
        Some("info"),
        "a read is not refused: {:?}",
        read
    );

    // 2. a send is refused by name, and the refusal says which op and why.
    let refused = ask(
        &mut reader,
        &mut writer,
        json!({ "op": "send", "pane": "main", "data": "echo nope\n" }),
    );
    assert_eq!(
        refused.get("kind").and_then(|kind| kind.as_str()),
        Some("fail"),
        "a watcher's send is a refusal: {:?}",
        refused
    );
    assert_eq!(
        refused.get("what").and_then(|what| what.as_str()),
        Some("a watcher's request was refused"),
        "the refusal says what happened: {:?}",
        refused
    );
    let why = refused
        .get("why")
        .and_then(|why| why.as_str())
        .unwrap_or("");
    assert!(why.contains("send"), "the refusal names the op: {:?}", why);

    // 3. a control is refused the same way.
    let controlled = ask(
        &mut reader,
        &mut writer,
        json!({ "op": "control", "id": "c-1", "words": ["tab", "new"] }),
    );
    assert_eq!(
        controlled.get("kind").and_then(|kind| kind.as_str()),
        Some("fail"),
        "a watcher's control is a refusal: {:?}",
        controlled
    );
    let why = controlled
        .get("why")
        .and_then(|why| why.as_str())
        .unwrap_or("");
    assert!(why.contains("control"), "the refusal names the op: {:?}", why);

    // 4. the watcher lets go: the session goes on, and a screen still drives
    //    it. A close and a send from the screen's own connection are taken,
    //    so the refusals above were the role and not the session.
    let goodbye = ask(&mut reader, &mut writer, json!({ "op": "detach" }));
    assert_eq!(
        goodbye.get("kind").and_then(|kind| kind.as_str()),
        Some("info"),
        "the watcher leaves and is answered: {:?}",
        goodbye
    );
    drop(writer);
    drop(reader);

    let (mut driver_reader, mut driver_writer) = attach(&socket, "screen");
    let sent = ask(
        &mut driver_reader,
        &mut driver_writer,
        json!({ "op": "send", "pane": "main", "data": "echo still-here\n" }),
    );
    assert_ne!(
        sent.get("kind").and_then(|kind| kind.as_str()),
        Some("fail"),
        "the screen may still send: {:?}",
        sent
    );

    // 5. the session itself is untouched: its holder still answers the state.
    let state = ask(&mut driver_reader, &mut driver_writer, json!({ "op": "state" }));
    let panes = state
        .get("outputs")
        .and_then(|outputs| outputs.get("panes"))
        .and_then(|panes| panes.as_array())
        .expect("the session still holds its panes");
    assert!(!panes.is_empty(), "the session's panes are still there: {:?}", state);

    let _ = holder.kill();
    let _ = holder.wait();
    let _ = std::fs::remove_dir_all(&dir);
}
