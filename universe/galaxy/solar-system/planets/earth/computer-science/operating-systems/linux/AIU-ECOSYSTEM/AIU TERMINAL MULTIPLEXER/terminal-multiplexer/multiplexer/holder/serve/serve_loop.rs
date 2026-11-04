use crate::*;

/// serve waits for events and answers them, until every pane has ended.
pub(crate) fn serve(session: &mut Session) -> Result<(), String> {
    loop {
        let mut fds: Vec<libc::pollfd> = Vec::with_capacity(2 + session.panes.len() + session.clients.len());
        for pane in &session.panes {
            fds.push(libc::pollfd {
                fd: pane.shell.master,
                events: libc::POLLIN,
                revents: 0,
            });
        }
        let pane_count = session.panes.len();
        fds.push(libc::pollfd {
            fd: session.listen_fd,
            events: libc::POLLIN,
            revents: 0,
        });
        for client in &session.clients {
            fds.push(libc::pollfd {
                fd: client.fd,
                events: libc::POLLIN,
                revents: 0,
            });
        }
        let ready = unsafe { libc::poll(fds.as_mut_ptr(), fds.len() as libc::nfds_t, -1) };
        if ready < 0 {
            if std::io::Error::last_os_error().raw_os_error() == Some(libc::EINTR) {
                continue;
            }
            return Err("the holder cannot wait for events".to_string());
        }

        let mut ended: Vec<usize> = Vec::new();
        for pane_at in 0..pane_count {
            if fds[pane_at].revents & (libc::POLLIN | libc::POLLHUP) == 0 {
                continue;
            }
            if !read_shell(session, pane_at)? {
                ended.push(pane_at);
            }
        }
        // A pane whose program ended goes on its own: the session and the
        // other panes go on. The session ends when the last pane is gone.
        for pane_at in ended.into_iter().rev() {
            close_pane(session, pane_at);
        }
        if session.panes.is_empty() {
            break;
        }

        if fds[pane_count].revents & libc::POLLIN != 0 {
            let fd = unsafe {
                libc::accept(
                    session.listen_fd,
                    std::ptr::null_mut(),
                    std::ptr::null_mut(),
                )
            };
            if fd >= 0 {
                session.clients.push(Client {
                    fd,
                    pending: String::new(),
                    attached: false,
                    dead: false,
                    role: String::new(),
                });
            }
        }

        let mut finished: Vec<usize> = Vec::new();
        for at in (pane_count + 1)..fds.len() {
            if fds[at].revents & (libc::POLLIN | libc::POLLHUP) == 0 {
                continue;
            }
            let client_at = at - (pane_count + 1);
            if !read_client(session, client_at)? {
                finished.push(client_at);
            }
        }
        for at in finished.into_iter().rev() {
            let client = session.clients.remove(at);
            close(client.fd);
        }
        let mut gone: Vec<usize> = Vec::new();
        for (at, client) in session.clients.iter().enumerate() {
            if client.dead {
                gone.push(at);
            }
        }
        for at in gone.into_iter().rev() {
            let client = session.clients.remove(at);
            close(client.fd);
        }
    }

    let mut statuses: Vec<String> = Vec::new();
    for pane in &session.panes {
        statuses.push(pane.shell.wait());
    }
    let end = session.record(Fields {
        kind: "end",
        who: "holder",
        what: "the panes ended, the session is over",
        why: "the shells closed their terminals",
        how: "the masters read no bytes and every shell was waited for",
        inputs: json!({}),
        outputs: json!({}),
        result: json!({ "status": statuses.join(", ") }),
    });
    session.write(&end);
    close(session.listen_fd);
    let _ = std::fs::remove_file(&session.socket_path);
    Ok(())
}

