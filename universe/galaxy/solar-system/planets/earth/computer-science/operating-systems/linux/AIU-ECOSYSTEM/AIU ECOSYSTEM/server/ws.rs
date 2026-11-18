use std::io::{Read, Write};
use std::net::TcpStream;
use std::sync::{Arc, Mutex};
use std::time::Duration;

static CLIENTS: Mutex<Vec<(u64, TcpStream)>> =
    Mutex::new(Vec::new());
static NEXT: Mutex<u64> = Mutex::new(0);

fn sha1(data: &[u8]) -> [u8; 20] {
    let mut h: [u32; 5] =
        [0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0xC3D2E1F0];
    let mut msg = data.to_vec();
    let bits = (data.len() as u64) * 8;
    msg.push(0x80);
    while msg.len() % 64 != 56 {
        msg.push(0);
    }
    msg.extend_from_slice(&bits.to_be_bytes());
    for chunk in msg.chunks(64) {
        let mut w = [0u32; 80];
        for i in 0..16 {
            let j = 4 * i;
            w[i] = u32::from_be_bytes([
                chunk[j], chunk[j + 1], chunk[j + 2], chunk[j + 3],
            ]);
        }
        for i in 16..80 {
            w[i] = (w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16])
                .rotate_left(1);
        }
        let (mut a, mut b, mut c, mut d, mut e) =
            (h[0], h[1], h[2], h[3], h[4]);
        for i in 0..80 {
            let (f, k) = match i {
                0..=19 => ((b & c) | (!b & d), 0x5A827999u32),
                20..=39 => (b ^ c ^ d, 0x6ED9EBA1u32),
                40..=59 => ((b & c) | (b & d) | (c & d), 0x8F1BBCDCu32),
                _ => (b ^ c ^ d, 0xCA62C1D6u32),
            };
            let t = a
                .rotate_left(5)
                .wrapping_add(f)
                .wrapping_add(e)
                .wrapping_add(k)
                .wrapping_add(w[i]);
            e = d;
            d = c;
            c = b.rotate_left(30);
            b = a;
            a = t;
        }
        h[0] = h[0].wrapping_add(a);
        h[1] = h[1].wrapping_add(b);
        h[2] = h[2].wrapping_add(c);
        h[3] = h[3].wrapping_add(d);
        h[4] = h[4].wrapping_add(e);
    }
    let mut out = [0u8; 20];
    for i in 0..5 {
        out[4 * i..4 * i + 4].copy_from_slice(&h[i].to_be_bytes());
    }
    out
}

fn base64(d: &[u8]) -> String {
    let t = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut s = String::new();
    for c in d.chunks(3) {
        let b1 = if c.len() > 1 { c[1] as u32 } else { 0 };
        let b2 = if c.len() > 2 { c[2] as u32 } else { 0 };
        let n = ((c[0] as u32) << 16) | (b1 << 8) | b2;
        s.push(t[(n >> 18) as usize & 63] as char);
        s.push(t[(n >> 12) as usize & 63] as char);
        if c.len() > 1 {
            s.push(t[(n >> 6) as usize & 63] as char);
        } else {
            s.push_str("=");
        }
        if c.len() > 2 {
            s.push(t[n as usize & 63] as char);
        } else {
            s.push_str("=");
        }
    }
    s
}

fn frame(op: u8, payload: &[u8]) -> Vec<u8> {
    let mut f = vec![0x80 | op];
    let n = payload.len();
    if n < 126 {
        f.push(n as u8);
    } else if n < 65536 {
        f.push(126);
        f.extend_from_slice(&(n as u16).to_be_bytes());
    } else {
        f.push(127);
        f.extend_from_slice(&(n as u64).to_be_bytes());
    }
    f.extend_from_slice(payload);
    f
}

fn send_to(id: u64, op: u8, payload: &[u8]) {
    let data = frame(op, payload);
    let mut list = CLIENTS.lock().unwrap_or_else(|e| e.into_inner());
    if let Some(pos) = list.iter().position(|(i, _)| *i == id) {
        if list[pos].1.write_all(&data).is_err() {
            list.remove(pos);
        }
    }
}

pub fn broadcast(text: &str) {
    let data = frame(1, text.as_bytes());
    let mut list = CLIENTS.lock().unwrap_or_else(|e| e.into_inner());
    list.retain_mut(|(_, s)| s.write_all(&data).is_ok());
}

fn read_frame(r: &mut impl Read) -> Option<(u8, Vec<u8>)> {
    let mut h = [0u8; 2];
    r.read_exact(&mut h).ok()?;
    let op = h[0] & 15;
    let masked = h[1] & 128 != 0;
    let mut n = (h[1] & 127) as u64;
    if n == 126 {
        let mut b = [0u8; 2];
        r.read_exact(&mut b).ok()?;
        n = u16::from_be_bytes(b) as u64;
    } else if n == 127 {
        let mut b = [0u8; 8];
        r.read_exact(&mut b).ok()?;
        n = u64::from_be_bytes(b);
    }
    if n > 1_000_000 {
        return None;
    }
    let mut mask = [0u8; 4];
    if masked {
        r.read_exact(&mut mask).ok()?;
    }
    let mut p = vec![0u8; n as usize];
    r.read_exact(&mut p).ok()?;
    if masked {
        for (i, b) in p.iter_mut().enumerate() {
            *b ^= mask[i % 4];
        }
    }
    Some((op, p))
}

pub fn serve(
    stream: &TcpStream,
    key: &str,
    mut input: impl Read,
    programs: &crate::Programs,
    dev: &Arc<Mutex<crate::DevState>>,
    db: &crate::Db,
    started: u64,
) {
    let mut acc = String::from(key.trim());
    acc.push_str("258EAFA5-E914-47DA-95CA-C5AB0DC85B11");
    let accept = base64(&sha1(acc.as_bytes()));
    let mut head = String::from("HTTP/1.1 101 Switching Protocols\r\n");
    head.push_str("Upgrade: websocket\r\nConnection: Upgrade\r\n");
    head.push_str("Sec-WebSocket-Accept: ");
    head.push_str(&accept);
    head.push_str("\r\n\r\n");
    let mut out = stream;
    if out.write_all(head.as_bytes()).is_err() {
        return;
    }
    let clone = match stream.try_clone() {
        Ok(c) => c,
        Err(_) => return,
    };
    let _ = stream.set_read_timeout(None);
    let _ = stream.set_write_timeout(Some(Duration::from_secs(2)));
    let id = {
        let mut n = NEXT.lock().unwrap_or_else(|e| e.into_inner());
        *n += 1;
        *n
    };
    CLIENTS
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .push((id, clone));
    loop {
        let (op, p) = match read_frame(&mut input) {
            Some(x) => x,
            None => break,
        };
        match op {
            1 => {
                let text = String::from_utf8_lossy(&p).to_string();
                let words: Vec<&str> = text.split_whitespace().collect();
                let answer = if words == ["stop"] {
                    String::from("error stop only from the socket")
                } else {
                    let mut map =
                        programs.lock().unwrap_or_else(|e| e.into_inner());
                    crate::handle_raw(&text, &mut map, started, dev, db).0
                };
                send_to(id, 1, answer.as_bytes());
            }
            8 => {
                send_to(id, 8, &[]);
                break;
            }
            9 => send_to(id, 10, &p),
            _ => {}
        }
    }
    CLIENTS
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .retain(|(i, _)| *i != id);
}
