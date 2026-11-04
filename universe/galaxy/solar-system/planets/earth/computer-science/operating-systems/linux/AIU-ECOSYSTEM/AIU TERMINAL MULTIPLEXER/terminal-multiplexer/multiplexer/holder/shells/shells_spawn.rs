
use crate::facade;
use crate::measure;

pub struct Shell {
    pub pid: libc::pid_t,
    pub master: libc::c_int,
    pub program: String,
    pub measured: measure::Measured,
}

impl Shell {
    pub fn start(program: &str, args: &[String], cols: u16, rows: u16) -> Result<Shell, String> {
        let pty = facade::open_shell(program, args, cols, rows)?;
        Ok(Shell {
            pid: pty.pid,
            master: pty.master,
            program: program.to_string(),
            measured: pty.measured,
        })
    }

    pub fn alive_now(&self) -> bool {
        unsafe { libc::kill(self.pid, 0) == 0 }
    }

    pub fn send(&self, bytes: &[u8]) -> Result<(), String> {
        facade::write_bytes(self.master, bytes)
    }

    pub fn read(&self, buffer: &mut [u8]) -> Result<usize, String> {
        facade::read_bytes(self.master, buffer)
    }

    pub fn wait(&self) -> String {
        facade::wait_exit(self.pid)
    }
}
