use crate::*;

/// bind opens the session's socket and listens on it.
pub(crate) fn bind(path: &Path) -> Result<c_int, String> {
    let fd = unsafe { libc::socket(libc::AF_UNIX, libc::SOCK_STREAM, 0) };
    if fd < 0 {
        return Err("this phone cannot make a unix socket".to_string());
    }
    let mut address: libc::sockaddr_un = unsafe { std::mem::zeroed() };
    address.sun_family = libc::AF_UNIX as libc::sa_family_t;
    let bytes = path.as_os_str().as_bytes();
    if bytes.len() >= address.sun_path.len() {
        close(fd);
        return Err(format!(
            "the socket path {} is too long for this phone",
            path.display()
        ));
    }
    for (at, byte) in bytes.iter().enumerate() {
        address.sun_path[at] = *byte as libc::c_char;
    }
    let length =
        (std::mem::size_of::<libc::sa_family_t>() + bytes.len() + 1) as libc::socklen_t;
    let put = unsafe {
        libc::bind(
            fd,
            &address as *const libc::sockaddr_un as *const libc::sockaddr,
            length,
        )
    };
    if put != 0 {
        close(fd);
        return Err(format!("the socket {} cannot be bound", path.display()));
    }
    if unsafe { libc::listen(fd, 8) } != 0 {
        close(fd);
        return Err(format!("the socket {} cannot listen", path.display()));
    }
    Ok(fd)
}

/// answers_holder asks the socket whether a holder is behind it: one state
/// request, and an answer is the proof. A socket a dead holder left behind
/// AT the connection on this phone (proot answers connect and then says
/// nothing), so the question is asked instead of assumed. The read has its own
/// bound: a socket that accepts and never answers is not a holder, and it must
/// not hold the next one up for ever.
pub(crate) fn answers_holder(fd: c_int) -> bool {
    let bound = libc::timeval {
        tv_sec: 2,
        tv_usec: 0,
    };
    unsafe {
        libc::setsockopt(
            fd,
            libc::SOL_SOCKET,
            libc::SO_RCVTIMEO,
            &bound as *const libc::timeval as *const libc::c_void,
            std::mem::size_of::<libc::timeval>() as libc::socklen_t,
        );
    }
    let request = json!({ "op": "state", "client": "multiplexer-holder/1" });
    let mut line = request.to_string();
    line.push('\n');
    if write_to(fd, line.as_bytes()).is_err() {
        return false;
    }
    let mut buffer = [0u8; 4096];
    matches!(read_from(fd, &mut buffer), Ok(got) if got > 0)
}

/// connect opens a connection to a socket that is already there.
pub(crate) fn connect(path: &Path) -> Result<c_int, String> {
    let fd = unsafe { libc::socket(libc::AF_UNIX, libc::SOCK_STREAM, 0) };
    if fd < 0 {
        return Err("this phone cannot make a unix socket".to_string());
    }
    let mut address: libc::sockaddr_un = unsafe { std::mem::zeroed() };
    address.sun_family = libc::AF_UNIX as libc::sa_family_t;
    let bytes = path.as_os_str().as_bytes();
    if bytes.len() >= address.sun_path.len() {
        close(fd);
        return Err(format!("the socket path {} is too long", path.display()));
    }
    for (at, byte) in bytes.iter().enumerate() {
        address.sun_path[at] = *byte as libc::c_char;
    }
    let length =
        (std::mem::size_of::<libc::sa_family_t>() + bytes.len() + 1) as libc::socklen_t;
    let put = unsafe {
        libc::connect(
            fd,
            &address as *const libc::sockaddr_un as *const libc::sockaddr,
            length,
        )
    };
    if put != 0 {
        close(fd);
        return Err(format!("the socket {} refused the connection", path.display()));
    }
    Ok(fd)
}

/// read_from waits for bytes and answers how many came.
pub(crate) fn read_from(fd: c_int, buffer: &mut [u8]) -> Result<usize, String> {
    let got = unsafe { libc::read(fd, buffer.as_mut_ptr() as *mut libc::c_void, buffer.len()) };
    if got >= 0 {
        Ok(got as usize)
    } else {
        Err(format!("read from fd {} failed", fd))
    }
}

/// write_to puts bytes on a descriptor and answers when they are all in.
pub(crate) fn write_to(fd: c_int, bytes: &[u8]) -> Result<(), String> {
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
            return Err(format!("write to fd {} failed", fd));
        }
        at += put as usize;
    }
    Ok(())
}

