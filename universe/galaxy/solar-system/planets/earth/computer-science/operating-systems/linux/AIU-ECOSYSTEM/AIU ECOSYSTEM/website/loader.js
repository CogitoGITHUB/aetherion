(async () => {
  const cv = document.getElementById("c"), g = cv.getContext("2d");
  const dec = new TextDecoder(), enc = new TextEncoder();
  let e, ox = 0, oy = 0, z = 1, pts = [];
  const ws = new WebSocket("ws://" + location.host + "/ws");
  const mem = (p, n) => new Uint8Array(e.memory.buffer, p, n);
  const put = (b) => { const p = e.alloc(b.length); mem(p, b.length).set(b); return p; };
  const str = (p, n) => dec.decode(mem(p, n));
  const w = await WebAssembly.instantiateStreaming(fetch("bridge.wasm"), { env: {
    send: (p, n) => ws.send(str(p, n)),
    rect: (x, y, a, b) => {
      g.fillStyle = "#1d2733"; g.fillRect(x, y, a, b);
      g.strokeStyle = "#5b8fc7"; g.strokeRect(x, y, a, b);
    },
    line: (x, y, a, b) => {
      g.strokeStyle = "#8a9bb0"; g.beginPath(); g.moveTo(x, y); g.lineTo(a, b);
      const t = Math.atan2(b - y, a - x), h = 10;
      g.moveTo(a, b); g.lineTo(a - h * Math.cos(t - 0.4), b - h * Math.sin(t - 0.4));
      g.moveTo(a, b); g.lineTo(a - h * Math.cos(t + 0.4), b - h * Math.sin(t + 0.4));
      g.stroke();
    },
    text: (p, n, x, y) => { g.fillStyle = "#e6e6e6"; g.fillText(str(p, n), x, y); },
  } });
  e = w.instance.exports;
  const paint = () => {
    cv.width = innerWidth; cv.height = innerHeight;
    g.setTransform(1, 0, 0, 1, 0, 0);
    g.fillStyle = "#12161c"; g.fillRect(0, 0, cv.width, cv.height);
    const s = 48 * z;
    const fx = ((((-ox * z) % s) + s) % s) - s, fy = ((((-oy * z) % s) + s) % s) - s;
    g.strokeStyle = "#1e252e"; g.lineWidth = 1; g.beginPath();
    for (let x = fx; x < cv.width; x += s) { g.moveTo(x, 0); g.lineTo(x, cv.height); }
    for (let y = fy; y < cv.height; y += s) { g.moveTo(0, y); g.lineTo(cv.width, y); }
    g.stroke();
    g.setTransform(z, 0, 0, z, 0, 0);
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
  addEventListener("touchstart", (v) => { pts = grab(v.touches); }, { passive: false });
  addEventListener("touchmove", (v) => {
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
  addEventListener("touchend", (v) => { pts = grab(v.touches); });
  addEventListener("wheel", (v) => {
    v.preventDefault();
    zoomAt(v.clientX, v.clientY, z * Math.exp(-v.deltaY * 0.001), v.clientX, v.clientY);
    paint();
  }, { passive: false });
  let md = null;
  addEventListener("mousedown", (v) => { md = [v.clientX, v.clientY]; });
  addEventListener("mouseup", () => { md = null; });
  addEventListener("mousemove", (v) => {
    if (!md) return;
    ox -= (v.clientX - md[0]) / z; oy -= (v.clientY - md[1]) / z;
    md = [v.clientX, v.clientY]; paint();
  });
  addEventListener("resize", paint);
  await load();
})();
