use crate::*;

pub(crate) fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match run(&args) {
        Ok(()) => {}
        Err(why) => {
            eprintln!("holder: {}", why);
            std::process::exit(1);
        }
    }
}

/// run holds one session from the first moment to the last.
pub(crate) fn run(args: &[String]) -> Result<(), String> {
    let options = Options::read(args)?;
    // The holder says which build it is: a client that meets it at attach
    // compares the contracts, and the refusal must be able to name both sides.
    eprintln!(
        "holder: build {} — contracts {} and {}",
        env!("CARGO_PKG_VERSION"),
        HOLDER_CONTRACT,
        EVENT_CONTRACT
    );
    // The state directory is the owner's alone (TODO item 51): 0700, and the
    // files the session writes in it are 0600.
    log::private_dir(&options.state_dir)?;

    let log_path = options.state_dir.join("events.log");
    let socket_path = options.state_dir.join("holder.sock");
    let pid_path = options.state_dir.join("holder.pid");

    if socket_path.exists() {
        // A connection is not proof: this phone answers connect() on a socket
        // a dead holder left behind, and then says nothing. The proof is an
        // answer, so the question is asked before the session is called held.
        let stale = match connect(&socket_path) {
            Ok(fd) => {
                let answers = answers_holder(fd);
                close(fd);
                !answers
            }
            Err(_) => true,
        };
        if !stale {
            return Err(format!(
                "a holder already holds the session in {}",
                options.state_dir.display()
            ));
        }
        std::fs::remove_file(&socket_path).map_err(|why| {
            format!(
                "the stale socket {} cannot be removed: {}",
                socket_path.display(),
                why
            )
        })?;
    }

    let log = log::Log::open_with(&log_path, options.log_limit, log::KEEP_RECORDS)?;
    let listen_fd = bind(&socket_path)?;

    // The panes of the session: the layout file names them, or the smallest
    // layout there is holds one pane with one shell.
    let wanted = match &options.layout {
        Some(path) => layout::read(path)?,
        None => layout::one("main", &options.shell, options.cols, options.rows),
    };
    let direction = wanted.direction.clone();
    let mut panes: Vec<Pane> = Vec::new();
    let mut tabs: Vec<String> = Vec::new();
    for pane in wanted.panes {
        let shell = shells::Shell::start(&pane.program, &[], pane.cols, pane.rows)?;
        if !tabs.contains(&pane.tab) {
            tabs.push(pane.tab.clone());
        }
        panes.push(Pane {
            name: pane.name,
            tab: pane.tab,
            weight: pane.weight,
            hidden: false,
            args: Vec::new(),
            typed: String::new(),
            shell,
        });
    }

    let run_id = format!("mux-{}-{}", options.shell.replace('/', "-"), std::process::id());
    let mut session = Session {
        run_id,
        state_dir: options.state_dir.clone(),
        sessions_dir: options.sessions_dir.clone(),
        workspace_dir: options.workspace_dir.clone(),
        workspace: options.workspace.clone(),
        log_path,
        socket_path,
        log,
        panes,
        tabs,
        direction,
        cols: options.cols,
        rows: options.rows,
        area_rows: options.rows,
        layout_path: options.layout.clone(),
        seq: 0,
        started: Instant::now(),
        listen_fd,
        clients: Vec::new(),
        pending: Vec::new(),
    };

    std::fs::write(&pid_path, format!("{}", std::process::id())).map_err(|why| {
        format!(
            "the holder's pid cannot be written to {}: {}",
            pid_path.display(),
            why
        )
    })?;
    log::private_file(&pid_path)?;

    let mut measured: serde_json::Map<String, Value> = serde_json::Map::new();
    for (key, value) in measure::record(&session.panes[0].shell.measured) {
        measured.insert(key.to_string(), value);
    }
    let start = session.record(Fields {
        kind: "start",
        who: "holder",
        what: "the session holds its panes",
        why: "the holder was asked to hold a session",
        how: "a pty was opened for every pane, the shell was started on it, the socket was bound",
        inputs: json!({
            "state-dir": options.state_dir.display().to_string(),
            "layout": match &options.layout {
                Some(path) => path.display().to_string(),
                None => "one pane".to_string(),
            },
            "panes": session.panes.iter().map(|pane| pane.name.clone()).collect::<Vec<String>>()
        }),
        outputs: json!({
            "session": session.run_id.clone(),
            "socket": session.socket_path.display().to_string(),
            "log": session.log_path.display().to_string(),
            "measured": Value::Object(measured)
        }),
        result: json!({}),
    });
    session.write(&start);

    serve(&mut session)
}

