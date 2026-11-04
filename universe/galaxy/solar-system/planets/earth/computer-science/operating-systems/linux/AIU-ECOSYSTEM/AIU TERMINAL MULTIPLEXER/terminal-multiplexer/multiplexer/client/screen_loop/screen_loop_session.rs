use super::*;

/// session is the screen's own life: it attaches to the holder, draws the
/// panes, and answers the keys until the owner leaves.
///
/// The config comes in with the screen: it is applied before the first draw,
/// and it is looked at again before every other draw, so a change to the file
/// is in force without a restart. The check is the loop's, not a watcher's:
/// the loop turns on an event, and that is when the file is read.
pub fn session(
    fd: libc::c_int,
    client_name: &str,
    watch: bool,
    agent_program: String,
    editor_program: String,
    editor_mcp: Vec<String>,
    mut config: ConfigFile,
) -> Result<Ending, String> {
    let saved = tty::save_termios(libc::STDIN_FILENO).ok();
    let _ = tty::make_raw(libc::STDIN_FILENO);
    let mut screen = Screen::empty(agent_program, editor_program, editor_mcp);
    screen.set_level(config.config().level);
    screen.set_tab_bar(config.config().tab_bar);
    screen.set_watch(watch);
    // A config file that is there and was not used says so where the owner
    // reads it, and the screen runs on what the last good one said.
    if let Some(why) = config.problem() {
        screen.message = why.to_string();
    }
    wire::ask(fd, &json!({ "op": "state", "client": client_name }))?;
    wire::ask(
        fd,
        &json!({
            "op": "attach",
            "client": client_name,
            "role": if watch { "watch" } else { "screen" },
            "event-contract": crate::EVENT_CONTRACT,
            "holder-contract": crate::HOLDER_CONTRACT
        }),
    )?;

    let mut pending = String::new();
    let mut out = std::io::stdout();
    let mut leave = false;
    let mut detached = false;
    let mut keys_done = false;
    // A client that leaves must be heard: it detaches and waits for the
    // holder's answer, so a request it asked for is never lost to a
    // connection that closed too early.
    while !leave || !detached {
        // The window: the terminal's size is the session's size, and the
        // holder tells every pane — the shells and the editors alike.
        let size = tty::window_size(libc::STDOUT_FILENO).unwrap_or((80, 24));
        if size.0 != screen.cols || size.1 != screen.rows {
            screen.cols = size.0;
            screen.rows = size.1;
            // A watcher draws at its own size and asks for nothing: the
            // session's size belongs to the screen that types (TODO item 60).
            if !watch {
                // The rows the panes get: the window minus the screen's own
                // furniture. The holder gives every program the size of the
                // place it is drawn in, so the two cannot drift apart.
                let (_, area_rows) = screen.area();
                wire::ask(
                    fd,
                    &json!({
                        "op": "resize",
                        "client": client_name,
                        "cols": size.0,
                        "rows": size.1,
                        "area-rows": area_rows
                    }),
                )?;
            }
        }

        // The keys are only read once the screen knows the panes: a key that
        // arrives before the state would go to a pane the screen has not met.
        let ready = !screen.panes.is_empty() && !keys_done;
        let mut fds = vec![libc::pollfd {
            fd,
            events: libc::POLLIN,
            revents: 0,
        }];
        if ready {
            fds.push(libc::pollfd {
                fd: libc::STDIN_FILENO,
                events: libc::POLLIN,
                revents: 0,
            });
        }
        let ready_poll = unsafe { libc::poll(fds.as_mut_ptr(), fds.len() as libc::nfds_t, -1) };
        if ready_poll < 0 {
            if std::io::Error::last_os_error().raw_os_error() == Some(libc::EINTR) {
                continue;
            }
            break;
        }

        if fds[0].revents & (libc::POLLIN | libc::POLLHUP) != 0 {
            let mut buffer = [0u8; 8192];
            let got = wire::read(fd, &mut buffer)?;
            if got == 0 {
                break;
            }
            pending.push_str(&String::from_utf8_lossy(&buffer[..got]));
            while let Some(at) = pending.find('\n') {
                let line = pending[..at].trim().to_string();
                pending = pending[at + 1..].to_string();
                if line.is_empty() {
                    continue;
                }
                // The agent's request is not a record of the session: it is
                // the agent's words, and the screen runs them the way the
                // owner's own keys run them.
                let asked: Value = match serde_json::from_str(&line) {
                    Ok(found) => found,
                    Err(_) => Value::Null,
                };
                if control::is_request(&asked) {
                    let (id, words) = control::request_of(&asked);
                    let outcome = control::run(&mut screen, &words);
                    if let Some(mut ask) = outcome.ask {
                        ask["client"] = Value::from(client_name);
                        wire::ask(fd, &ask)?;
                    }
                    // The state is asked for, so the answer the agent gets is
                    // the state as it stands and not the state as it was.
                    screen.wait_for_state(id);
                    wire::ask(fd, &json!({ "op": "state", "client": client_name }))?;
                    continue;
                }
                if let Some(why) = take_record(&mut screen, &line) {
                    // The holder refused the contracts: the client says so in
                    // the holder's own words and stops drawing, because a
                    // picture from a session it does not understand is a lie.
                    out.write_all(b"\x1b[?25h\x1b[0m\n").ok();
                    let _ = out.flush();
                    if let Some(settings) = saved.clone() {
                        let _ = tty::restore_termios(libc::STDIN_FILENO, &settings);
                    }
                    return Ok(Ending::Refused(why));
                }
                if let Some(id) = screen.take_pending() {
                    let data = screen.view();
                    wire::ask(fd, &control::answer(&id, &data))?;
                }
                if line_holds(&line, "the client detached") {
                    detached = true;
                }
            }
        }

        // A pipe that is at its end says POLLHUP, not POLLIN: the end of the
        // keys is an event too, and the client must hear it.
        if fds.len() > 1 && fds[1].revents & (libc::POLLIN | libc::POLLHUP) != 0 {
            let mut buffer = [0u8; 1024];
            let got = wire::read(libc::STDIN_FILENO, &mut buffer)?;
            if got == 0 {
                // The keys are over: the client detaches and waits to be
                // answered, and the wait ends on the answer.
                keys_done = true;
                if !leave {
                    leave = true;
                    wire::ask(fd, &json!({ "op": "detach", "client": client_name }))?;
                }
                continue;
            }
            for action in screen.key(&buffer[..got]) {
                // A watcher watches: every key that would change the session
                // is answered with the rule, and only leaving is done
                // (TODO item 60). The holder refuses the same things on its
                // own, so the rule holds even if a request slips past here.
                let action = match screen.watch_filter(action) {
                    Some(one) => one,
                    None => continue,
                };
                match action {
                    Action::Nothing => {}
                    Action::Send(bytes) => {
                        let text = String::from_utf8_lossy(&bytes).to_string();
                        wire::ask(
                            fd,
                            &json!({
                                "op": "send",
                                "client": client_name,
                                "pane": screen.focused_pane(),
                                "data": text
                            }),
                        )?;
                    }
                    Action::Request(request) => {
                        let mut request = request;
                        request["client"] = Value::from(client_name);
                        wire::ask(fd, &request)?;
                    }
                    Action::Switch(name) => {
                        let to = std::path::Path::new(&screen.sessions_dir).join(&name);
                        out.write_all(b"\x1b[?25h\x1b[0m\n").ok();
                        let _ = out.flush();
                        if let Some(settings) = saved.clone() {
                            let _ = tty::restore_termios(libc::STDIN_FILENO, &settings);
                        }
                        return Ok(Ending::Switch(to));
                    }
                    Action::Terminal(bytes) => {
                        // The clipboard's sequence belongs to the owner's
                        // terminal: it is written where the drawing goes,
                        // never into a pane's program.
                        let _ = out.write_all(&bytes);
                        let _ = out.flush();
                    }
                    Action::AskEditor => {
                        // The holder asks the editor, not the client: the
                        // client holds no child process, and the command
                        // that starts the editor's server is only a word
                        // here.
                        let command = screen.editor_mcp.clone();
                        wire::ask(
                            fd,
                            &json!({
                                "op": "editor",
                                "client": client_name,
                                "command": command,
                                "capability": "dashboard"
                            }),
                        )?;
                    }
                    Action::Quit => {
                        leave = true;
                        keys_done = true;
                        wire::ask(fd, &json!({ "op": "detach", "client": client_name }))?;
                    }
                }
            }
        }

        // The config is looked at once per turn of the loop, before the
        // drawing: a file that changed is in force at this draw, and a file
        // that does not parse leaves the values in force and says why in the
        // message line. No timer and no thread: the loop turns on an event.
        match config.reload_if_changed() {
            Reload::Unchanged => {}
            Reload::Changed(now) => {
                screen.set_level(now.level);
                screen.set_tab_bar(now.tab_bar);
                let from = config.path().display();
                screen.message = format!("the config was reloaded from {}", from);
            }
            Reload::Broken(why) => {
                screen.message = format!("the config is not used: {}", why);
            }
        }

        let drawing = screen.draw();
        let _ = out.write_all(drawing.as_bytes());
        let _ = out.flush();
    }

    out.write_all(b"\x1b[?25h\x1b[0m\n").ok();
    let _ = out.flush();
    if let Some(settings) = saved {
        let _ = tty::restore_termios(libc::STDIN_FILENO, &settings);
    }
    Ok(Ending::Left)
}

