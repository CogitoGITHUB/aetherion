(async () => {
  const cv = document.getElementById("c"), g = cv.getContext("2d");
  const dec = new TextDecoder(), enc = new TextEncoder();
  let e, ox = 0, oy = 0, z = 1, pts = [];
  let T = {}, tsig = "", pend = null;
  let ov = null, st = null, mv = false;
  const closeFile = () => { if (ov) { ov.remove(); ov = null; } };
  const openFile = async (k) => {
    let t;
    try {
      t = await (await fetch("file?k=" + encodeURIComponent(k), { cache: "no-store" })).text();
    } catch (x) { t = "error " + x; }
    closeFile();
    const bg = T.bg && T.bg !== "none" ? T.bg : "Canvas";
    ov = document.createElement("div");
    ov.style.cssText = "position:fixed;inset:0;overflow:auto;box-sizing:border-box;padding:56px 16px 24px;white-space:pre-wrap;word-break:break-word;font:14px monospace;touch-action:pan-y;background:" + bg + ";color:" + ink("text");
    ov.textContent = t;
    const b = document.createElement("div");
    b.textContent = "close  " + k;
    b.style.cssText = "position:fixed;top:0;left:0;right:0;padding:14px 16px;cursor:pointer;background:" + bg + ";color:" + ink("dim");
    b.onclick = closeFile;
    ov.appendChild(b);
    document.body.appendChild(ov);
  };
  const tap = (x, y) => {
    const ok = e.pick(cv.width / z, ox + x / z, oy + y / z);
    if (ok > 0) openFile(str(e.pick_ptr(), e.pick_len()));
  };
  addEventListener("keydown", (v) => { if (v.key === "Escape") closeFile(); });
  const frame = (q, lx, lw) => {
    const r = T.corner === "square" ? 0 : 8;
    const x = q.x, y = q.y, x2 = x + q.a, y2 = y + q.b;
    g.strokeStyle = ink("dim"); g.beginPath();
    g.moveTo(x + r, y);
    g.lineTo(x2 - r, y); g.arcTo(x2, y, x2, y + r, r);
    g.lineTo(x2, y2 - r); g.arcTo(x2, y2, x2 - r, y2, r);
    g.lineTo(x + r, y2); g.arcTo(x, y2, x, y2 - r, r);
    g.lineTo(x, y + r); g.arcTo(x, y, x + r, y, r);
    g.lineTo(x + r, y);
    g.stroke();
  };
  const ink = (r) => (T[r] && T[r] !== "none" ? T[r] : "CanvasText");
  const readTheme = async () => {
    try {
      const t = await (await fetch("theme", { cache: "no-store" })).text();
      if (t === tsig) return false;
      tsig = t;
      const n = {};
      for (const l of t.split("\n")) {
        const i = l.indexOf("=");
        if (i > 0) n[l.slice(0, i)] = l.slice(i + 1);
      }
      T = n;
      document.body.style.background = n.bg === "none" ? "transparent" : n.bg;
      return true;
    } catch (x) { return false; }
  };
  const ws = new WebSocket("ws://" + location.host + "/ws");
  const mem = (p, n) => new Uint8Array(e.memory.buffer, p, n);
  const put = (b) => { const p = e.alloc(b.length); mem(p, b.length).set(b); return p; };
  const str = (p, n) => dec.decode(mem(p, n));
  const w = await WebAssembly.instantiateStreaming(fetch("bridge.wasm"), { env: {
    send: (p, n) => ws.send(str(p, n)),
    rect: (x, y, a, b) => {
      if (T.bg && T.bg !== "none") { g.fillStyle = T.bg; g.fillRect(x, y, a, b); }
      frame({ x: x, y: y, a: a, b: b }, 0, 0);
    },
    line: (x, y, a, b) => {
      g.strokeStyle = ink("dim"); g.beginPath(); g.moveTo(x, y); g.lineTo(a, b);
      const t = Math.atan2(b - y, a - x), h = 10;
      g.moveTo(a, b); g.lineTo(a - h * Math.cos(t - 0.4), b - h * Math.sin(t - 0.4));
      g.moveTo(a, b); g.lineTo(a - h * Math.cos(t + 0.4), b - h * Math.sin(t + 0.4));
      g.stroke();
    },
    text: (p, n, x, y) => { g.fillStyle = ink("text"); g.fillText(str(p, n), x, y); },
  } });
  e = w.instance.exports;
  const paint = () => {
    cv.width = innerWidth; cv.height = innerHeight;
    g.setTransform(1, 0, 0, 1, 0, 0);
    g.clearRect(0, 0, cv.width, cv.height);
    if (T.bg && T.bg !== "none") { g.fillStyle = T.bg; g.fillRect(0, 0, cv.width, cv.height); }
    const s = 48 * z;
    const fx = ((((-ox * z) % s) + s) % s) - s, fy = ((((-oy * z) % s) + s) % s) - s;
    g.globalAlpha = 0.25; g.strokeStyle = ink("dim"); g.lineWidth = 1; g.beginPath();
    for (let x = fx; x < cv.width; x += s) { g.moveTo(x, 0); g.lineTo(x, cv.height); }
    for (let y = fy; y < cv.height; y += s) { g.moveTo(0, y); g.lineTo(cv.width, y); }
    g.stroke();
    g.globalAlpha = 1; g.setTransform(z, 0, 0, z, 0, 0);
    g.lineWidth = 1.5 / z; g.font = "14px monospace"; g.textBaseline = "top";
    e.draw(cv.width / z, cv.height / z, ox, oy);
  };
  const zoomAt = (mx, my, nz, nx, ny) => {
    const k = Math.min(4, Math.max(0.2, nz));
    const wx = ox + mx / z, wy = oy + my / z;
    z = k; ox = wx - nx / z; oy = wy - ny / z;
  };
  const load = async () => {
    const d = new Uint8Array(await (await fetch("index.db")).arrayBuffer()), p = put(d);
    e.load_index(p, d.length); e.free_buf(p, d.length); paint();
  };
  ws.onmessage = (m) => {
    const b = enc.encode(m.data), p = put(b);
    e.on_message(p, b.length); e.free_buf(p, b.length);
    if (m.data === "changed") load();
  };
  const grab = (t) => Array.from(t).map((q) => [q.clientX, q.clientY]);
  addEventListener("touchstart", (v) => {
    pts = grab(v.touches);
    if (ov) return;
    if (v.touches.length === 1) { st = [v.touches[0].clientX, v.touches[0].clientY]; mv = false; } else mv = true;
  }, { passive: false });
  addEventListener("touchmove", (v) => {
    if (ov) return;
    if (st && (v.touches.length > 1 || Math.hypot(v.touches[0].clientX - st[0], v.touches[0].clientY - st[1]) > 10)) mv = true;
    v.preventDefault();
    const n = grab(v.touches);
    if (n.length === 1 && pts.length === 1) {
      ox -= (n[0][0] - pts[0][0]) / z; oy -= (n[0][1] - pts[0][1]) / z;
    } else if (n.length >= 2 && pts.length >= 2) {
      const d0 = Math.hypot(pts[0][0] - pts[1][0], pts[0][1] - pts[1][1]);
      const d1 = Math.hypot(n[0][0] - n[1][0], n[0][1] - n[1][1]);
      const m0x = (pts[0][0] + pts[1][0]) / 2, m0y = (pts[0][1] + pts[1][1]) / 2;
      const m1x = (n[0][0] + n[1][0]) / 2, m1y = (n[0][1] + n[1][1]) / 2;
      if (d0 > 0) zoomAt(m0x, m0y, z * d1 / d0, m1x, m1y);
    }
    pts = n; paint();
  }, { passive: false });
  addEventListener("touchend", (v) => {
    const t = v.changedTouches[0], s = st;
    pts = grab(v.touches);
    if (!ov && s && !mv && v.touches.length === 0 && t) tap(t.clientX, t.clientY);
    if (v.touches.length === 0) st = null;
  });
  addEventListener("wheel", (v) => {
    if (ov) return;
    v.preventDefault();
    zoomAt(v.clientX, v.clientY, z * Math.exp(-v.deltaY * 0.001), v.clientX, v.clientY);
    paint();
  }, { passive: false });
  let md = null;
  addEventListener("mousedown", (v) => {
    if (ov) return;
    md = [v.clientX, v.clientY]; st = [v.clientX, v.clientY]; mv = false;
  });
  addEventListener("mouseup", (v) => {
    if (!ov && st && !mv) tap(v.clientX, v.clientY);
    st = null; md = null;
  });
  addEventListener("mousemove", (v) => {
    if (!md || ov) return;
    if (st && Math.hypot(v.clientX - st[0], v.clientY - st[1]) > 5) mv = true;
    ox -= (v.clientX - md[0]) / z; oy -= (v.clientY - md[1]) / z;
    md = [v.clientX, v.clientY]; paint();
  });
  addEventListener("resize", paint);
  await readTheme();
  await load();
  setInterval(async () => { if (await readTheme()) paint(); }, 1000);
})();
