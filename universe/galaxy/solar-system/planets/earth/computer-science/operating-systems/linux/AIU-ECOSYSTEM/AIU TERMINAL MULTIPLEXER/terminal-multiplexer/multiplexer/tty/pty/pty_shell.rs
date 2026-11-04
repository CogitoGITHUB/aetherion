
use crate::measure;
use crate::tty;
use libc::c_int;
use std::ffi::CString;

pub struct Pty {
    pub master: c_int,
    pub pid: libc::pid_t,
    pub measured: measure::Measured,
}

pub fn open_shell(program: &str, args: &[String], cols: u16, rows: u16) -> Result<Pty, String> {
    let master = unsafe { libc::posix_openpt(libc::O_RDWR | libc::O_NOCTTY) };
    if master < 0 {
        return Err("posix_openpt refused: this phone has no pty to give".to_string());
    }
    if unsafe { libc::grantpt(master) } != 0 || unsafe { libc::unlockpt(master) } != 0 {
        close(master);
        return Err("grantpt or unlockpt refused on the new pty".to_string());
    }

    let mut name: Vec<u8> = vec![0u8; 256];
    let asked = unsafe {
        libc::ptsname_r(
            master,
            name.as_mut_ptr() as *mut libc::c_char,
            name.len(),
        )
    };
    if asked != 0 {
        close(master);
        return Err("ptsname_r refused on the new pty".to_string());
    }
    let slave_path = String::from_utf8_lossy(&name)
        .trim_end_matches('\0')
        .to_string();
    let slave_name = match CString::new(slave_path.clone()) {
        Ok(value) => value,
        Err(_) => {
            close(master);
            return Err("the pty slave name holds a nul byte".to_string());
        }
    };

    let slave = unsafe { libc::open(slave_name.as_ptr(), libc::O_RDWR | libc::O_NOCTTY) };
    if slave < 0 {
        close(master);
        return Err(format!("the pty slave {} cannot be opened", slave_path));
    }
    if let Err(why) = tty::make_raw(slave) {
        eprintln!("holder: raw mode was refused: {}", why);
    }
    if let Err(why) = tty::set_window_size(slave, cols, rows) {
        eprintln!("holder: the terminal refused its size: {}", why);
    }

    let child = fork_shell(slave_path.clone(), program, args);
    close(slave);
    match child {
        Ok(pid) => {
            let measured = measure::of_terminal(master, (cols, rows), &slave_path);
            Ok(Pty {
                master,
                pid,
                measured,
            })
        }
        Err(why) => {
            close(master);
            Err(why)
        }
    }
}

pub fn read_bytes(fd: c_int, buffer: &mut [u8]) -> Result<usize, String> {
    let got = unsafe { libc::read(fd, buffer.as_mut_ptr() as *mut libc::c_void, buffer.len()) };
    if got >= 0 {
        Ok(got as usize)
    } else {
        Err(format!("read from the terminal failed on fd {}", fd))
    }
}

pub fn write_bytes(fd: c_int, bytes: &[u8]) -> Result<(), String> {
    let mut at = 0;
    while at < bytes.len() {
        let put = unsafe {
            libc::write(
                fd,
                bytes[at..].as_ptr() as *const libc::c_void,
                bytes.len() - at,
            )
        };
        if put <= 0 {
            return Err(format!("write to the terminal failed on fd {}", fd));
        }
        at += put as usize;
    }
    Ok(())
}

pub fn wait_exit(pid: libc::pid_t) -> String {
    let mut status: c_int = 0;
    let got = unsafe { libc::waitpid(pid, &mut status, 0) };
    if got < 0 {
        return "the shell could not be waited for".to_string();
    }
    if libc::WIFEXITED(status) {
        format!("exited with {}", libc::WEXITSTATUS(status))
    } else if libc::WIFSIGNALED(status) {
        format!("killed by signal {}", libc::WTERMSIG(status))
    } else {
        "ended in a way this holder cannot name".to_string()
    }
}

pub fn close(fd: c_int) {
    if fd >= 0 {
        unsafe {
            libc::close(fd);
        }
    }
}

fn fork_shell(slave_path: String, program: &str, args: &[String]) -> Result<libc::pid_t, String> {
    let path = match CString::new(program) {
        Ok(value) => value,
        Err(_) => return Err("the shell path holds a nul byte".to_string()),
    };
    let slave_name = match CString::new(slave_path) {
        Ok(value) => value,
        Err(_) => return Err("the pty slave name holds a nul byte".to_string()),
    };
    let mut argv: Vec<CString> = vec![path.clone()];
    for argument in args {
        match CString::new(argument.as_str()) {
            Ok(value) => argv.push(value),
            Err(_) => return Err("an argument of the program holds a nul byte".to_string()),
        }
    }
    let mut pointers: Vec<*const libc::c_char> = argv.iter().map(|a| a.as_ptr()).collect();
    pointers.push(std::ptr::null());

    let pid = unsafe { libc::fork() };
    if pid < 0 {
        return Err("fork refused: this phone will not start a shell".to_string());
    }
    if pid == 0 {
        unsafe {
            libc::setsid();
            let slave = libc::open(slave_name.as_ptr(), libc::O_RDWR);
            if slave >= 0 {
                libc::ioctl(slave, libc::TIOCSCTTY, 0);
                libc::dup2(slave, 0);
                libc::dup2(slave, 1);
                libc::dup2(slave, 2);
                if slave > 2 {
                    libc::close(slave);
                }
            }
            libc::execv(path.as_ptr(), pointers.as_ptr());
            libc::_exit(127);
        }
    }
    Ok(pid)
}
