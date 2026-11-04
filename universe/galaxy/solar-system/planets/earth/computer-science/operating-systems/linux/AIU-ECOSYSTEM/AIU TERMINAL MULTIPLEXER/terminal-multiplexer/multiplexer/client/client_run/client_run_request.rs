use crate::*;

pub(crate) fn run(args: &[String]) -> Result<i32, String> {
    let options = Options::read(args)?;
    eprintln!(
        "client: build {} — contracts {} and {}",
        BUILD, HOLDER_CONTRACT, EVENT_CONTRACT
    );
    let socket_path = options.state_dir.join("holder.sock");

    eprintln!(
        "client: waiting for the holder's socket at {}",
        socket_path.display()
    );
    wire::wait_for_socket(&socket_path)?;

    let fd = wire::connect(&socket_path)?;

    if options.op == "screen" || options.op == "watch" {
        wire::close(fd);
        return run_screen(&options.state_dir, &options, options.op == "watch");
    }

    wire::ask(fd, &options.request())?;

    let mut refused = false;
    let mut printed = 0u64;
    let mut pending = String::new();
    loop {
        let watching_stdin = options.op == "attach" && options.count.is_none();
        let mut fds = vec![libc::pollfd {
            fd,
            events: libc::POLLIN,
            revents: 0,
        }];
        if watching_stdin {
            fds.push(libc::pollfd {
                fd: libc::STDIN_FILENO,
                events: libc::POLLIN,
                revents: 0,
            });
        }
        let ready = unsafe { libc::poll(fds.as_mut_ptr(), fds.len() as libc::nfds_t, -1) };
        if ready < 0 {
            if std::io::Error::last_os_error().raw_os_error() == Some(libc::EINTR) {
                continue;
            }
            return Err("the client cannot wait for the holder".to_string());
        }

        if fds[0].revents & (libc::POLLIN | libc::POLLHUP) != 0 {
            let mut buffer = [0u8; 4096];
            let got = wire::read(fd, &mut buffer)?;
            if got == 0 {
                break;
            }
            pending.push_str(&String::from_utf8_lossy(&buffer[..got]));
            let mut lines = 0u64;
            let mut done = false;
            while let Some(at) = pending.find('\n') {
                let answer = pending[..at].trim().to_string();
                pending = pending[at + 1..].to_string();
                if answer.is_empty() {
                    continue;
                }
                if is_refusal(&answer) {
                    refused = true;
                }
                println!("{}", answer);
                printed += 1;
                lines += 1;
                if options.op == "attach" {
                    if let Some(wanted) = options.count {
                        if printed >= wanted {
                            done = true;
                            break;
                        }
                    }
                } else if is_final(&answer) {
                    done = true;
                    break;
                }
            }
            if done {
                break;
            }
            if options.op == "attach" {
                if let Some(wanted) = options.count {
                    if printed >= wanted {
                        break;
                    }
                }
            } else if options.op != "read" && lines > 0 {
                break;
            }
            continue;
        }

        if watching_stdin && fds[1].revents & (libc::POLLIN | libc::POLLHUP) != 0 {
            let mut buffer = [0u8; 1024];
            let got = wire::read(libc::STDIN_FILENO, &mut buffer)?;
            if got == 0 {
                break;
            }
            let said = String::from_utf8_lossy(&buffer[..got]).trim().to_string();
            if said == "detach" {
                break;
            }
        }
    }

    if options.op == "attach" {
        let mut detach = json!({ "op": "detach", "client": CLIENT_NAME }).to_string();
        detach.push('\n');
        let _ = wire::write(fd, detach.as_bytes());
        let mut answer = String::new();
        let mut buffer = [0u8; 4096];
        let got = wire::read(fd, &mut buffer)?;
        if got > 0 {
            answer = String::from_utf8_lossy(&buffer[..got]).trim().to_string();
        }
        if !answer.is_empty() {
            println!("{}", answer);
        }
    }

    wire::close(fd);
    Ok(if refused { 1 } else { 0 })
}

