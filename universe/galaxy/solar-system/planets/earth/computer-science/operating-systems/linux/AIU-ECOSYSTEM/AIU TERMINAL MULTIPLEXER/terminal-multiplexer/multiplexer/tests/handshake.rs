// One job: the proof of the versioned handshake (TODO item 48) — a client and
// a holder that do not agree on the contracts refuse each other by name, with
// both versions said and with what to do next.
//
// The holder here is the test's own: it answers the two requests a screen makes
// (the state, then the attach) with the refusal an older holder would give.
// Nothing about the client is faked: the real binary runs, and what it says is
// what the owner would see.

use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::UnixListener;
use std::path::PathBuf;
use std::process::{Command, Stdio};

/// a_scratch is a directory of this test's own, emptied first.
fn a_scratch(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("mux-handshake-{}-{}", std::process::id(), name));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).expect("the scratch directory is made");
    dir
}

/// an_old_holder answers what a holder that disagrees says: the client's two
/// contracts, its own two, and the safe path.
fn an_old_holder() -> String {
    let record = serde_json::json!({
        "kind": "fail",
        "who": "holder",
        "seq": 2,
        "what": "the client and the holder do not agree on the contract",
        "why": "the versions exchanged at attach differ",
        "how": "the two versions were compared and the attach was refused by name",
        "inputs": {
            "client-event-contract": "event-log-format/1",
            "client-holder-contract": "multiplexer-holder/1"
        },
        "outputs": {
            "holder-event-contract": "event-log-format/1",
            "holder-holder-contract": "multiplexer-holder/0"
        },
        "result": { "safe-path": "finish the session and restart the holder" }
    });
    format!("{}\n", record)
}

#[test]
fn a_client_and_a_holder_that_disagree_refuse_each_other_by_name() {
    let dir = a_scratch("refuse");
    let sock = dir.join("holder.sock");
    let listener = UnixListener::bind(&sock).expect("the socket is made");
    let at = dir.display().to_string();
    let mut client = Command::new(env!("CARGO_BIN_EXE_client"))
        .args(["--state-dir", &at, "--op", "screen"])
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("the client starts");

    // The screen asks twice before it draws: the state, then the attach. The
    // second one is answered with the old holder's refusal, and the connection
    // closes the way a refused attach does.
    let (stream, _) = listener.accept().expect("the client connects");
    let mut writer = stream.try_clone().expect("the socket is copied");
    let mut reader = BufReader::new(stream);
    let mut line = String::new();
    let mut asked = 0;
    while asked < 2 {
        line.clear();
        if reader.read_line(&mut line).unwrap_or(0) == 0 {
            break;
        }
        if !line.trim().is_empty() {
            asked += 1;
        }
    }
    assert_eq!(asked, 2, "the screen asked for the state and the attach");
    writer.write_all(an_old_holder().as_bytes()).expect("the refusal is sent");
    drop(writer);

    let end = client.wait_with_output().expect("the client ends");
    let said = String::from_utf8_lossy(&end.stderr).to_string();
    let drawn = String::from_utf8_lossy(&end.stdout).to_string();
    assert_eq!(end.status.code(), Some(2), "a refusal ends the client with 2: {:?}", said);
    assert!(said.contains("refused:"), "the line names the refusal: {:?}", said);
    assert!(said.contains("multiplexer-holder/1"), "the client's version: {:?}", said);
    assert!(said.contains("multiplexer-holder/0"), "the holder's version: {:?}", said);
    assert!(said.contains("restart the holder"), "what to do: {:?}", said);
    assert!(said.contains("build "), "the client said which build it is: {:?}", said);
    assert!(!drawn.contains("[main]"), "no picture is drawn for a session it cannot read");
}
