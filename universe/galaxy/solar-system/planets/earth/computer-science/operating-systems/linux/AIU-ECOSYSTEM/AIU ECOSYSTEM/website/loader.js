(async () => {
  const cv = document.getElementById("c"), g = cv.getContext("2d");
  const dec = new TextDecoder(), enc = new TextEncoder();
  let e, ox = 0, oy = 0, z = 1, pts = [];
  let T = {}, tsig = "", pend = null;
  let ver = 0, lsig = "", wl = null;
  let foc = '', lastS = null, lt = 0;
  let ov = null, st = null, mv = false;
  const mk = (tag, css, txt) => {
    const e = document.createElement(tag);
    if (css) e.style.cssText = css;
    if (txt !== undefined) e.textContent = txt;
    return e;
  };
  const block = (b, top) => {
    const dim = ink("dim"), fg = ink("text"), err = ink("error");
    const bg = T.bg && T.bg !== "none" ? T.bg : "Canvas";
    const rad = T.corner === "square" ? "0" : "12px";
    if (b.n === "contract") return mk("div");
    if (b.n === "answer" && !b.x) return mk("div");
    if (b.n === "title" && top) {
      const h = mk("div", "text-align:center;padding:30px 14px 32px;border:1px solid " + dim + ";border-radius:" + rad);
      h.appendChild(mk("div", "font-size:26px;font-weight:700;letter-spacing:.2em;line-height:1.35;text-transform:uppercase;color:" + fg, b.x));
      b.d.forEach((p) => {
        if (p[0] !== "name") h.appendChild(mk("div", "margin-top:12px;font-size:13px;color:" + dim, p[0] + ": " + p[1]));
      });
      return h;
    }
    const sec = b.n === "chapter" || b.n === "appendix" || b.n === "part";
    let kids = b.c, head = "";
    if (sec && kids.length && kids[0].n === "title") { head = kids[0].x; kids = kids.slice(1); }
    const hot = b.n === "todo" && b.d.some((p) => p[1] === "open");
    const e = mk("div", "position:relative;border:1px " + (b.n === "answer" ? "dashed " : "solid ") + (hot ? err : dim) + ";border-radius:" + rad + ";padding:20px 16px 14px;margin-top:" + (sec ? "28px" : "20px"));
    const lab = (b.l ? b.l + " \u00b7 " : "") + (sec ? (head || b.n) : b.n);
    e.appendChild(mk("span", "position:absolute;top:-10px;left:16px;padding:0 8px;font-size:12px;background:" + bg + ";color:" + (hot ? err : dim), lab));
    if (b.x) {
      const code = b.n === "code", mute = b.n === "comment";
      e.appendChild(mk("div", code ? "font:13px monospace;white-space:pre;overflow-x:auto;color:" + fg : "white-space:pre-wrap;color:" + (mute ? dim + ";font-style:italic" : fg), b.x));
    }
    b.d.forEach((p) => {
      if (p[0] === "name" || p[0] === "for" || p[0] === "asked") return;
      e.appendChild(mk("div", "margin-top:8px;font-size:12px;color:" + (p[1] === "open" ? err : dim), p[0] + ": " + p[1]));
    });
    kids.forEach((k) => e.appendChild(block(k, false)));
    return e;
  };
  const draw = (t) => {
    const root = mk("div", "max-width:760px;margin:0 auto;padding-bottom:40px");
    let j = null;
    try { j = JSON.parse(t); } catch (x) { j = null; }
    if (!Array.isArray(j)) {
      root.appendChild(mk("div", "color:" + ink("error"), t));
      return root;
    }
    j.forEach((b, i) => root.appendChild(block(b, i === 0)));
    return root;
  };
  const closeFile = () => { if (ov) { ov.remove(); ov = null; } };
  const openFile = async (k) => {
    let t;
    try {
      t = await (await fetch("file?k=" + encodeURIComponent(k), { cache: "no-store" })).text();
    } catch (x) { t = "error " + x; }
    closeFile();
    const bg = T.bg && T.bg !== "none" ? T.bg : "Canvas";
    ov = document.createElement("div");
    ov.style.cssText = "position:fixed;inset:0;overflow:auto;box-sizing:border-box;padding:56px 16px 24px;font:15px/1.5 system-ui,sans-serif;touch-action:pan-y;background:" + bg + ";color:" + ink("text");
    ov.appendChild(draw(t));
    const b = document.createElement("div");
    b.textContent = "close  " + k;
    b.style.cssText = "position:fixed;top:0;left:0;right:0;padding:14px 16px;cursor:pointer;background:" + bg + ";color:" + ink("dim");
    b.onclick = closeFile;
    ov.appendChild(b);
    document.body.appendChild(ov);
  };
  let ff = null;
  const isFar = () => { if (ff !== null) return ff; const c = e.style ? e.style(5) : 0; return z < (c > 0 ? c : 0.5); };
  const tap = (x, y) => {
    if (e.set_far) e.set_far(0);
    const ok = isFar() ? 0 : e.pick(Math.round(innerWidth), ox + x / z, oy + y / z);
    if (ok > 0) {
      const k = str(e.pick_ptr(), e.pick_len());
      if (foc === k) openFile(k); else { foc = k; paint(); }
    } else if (foc) { foc = ''; paint(); }
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
    if (T.fill && T.fill !== "none") { g.fillStyle = T.fill; g.fill(); }
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
      if (T.arrow === "none" || T.arrow === "plain") { g.stroke(); return; }
      const t = Math.atan2(b - y, a - x), h = 10;
      g.moveTo(a, b); g.lineTo(a - h * Math.cos(t - 0.4), b - h * Math.sin(t - 0.4));
      g.moveTo(a, b); g.lineTo(a - h * Math.cos(t + 0.4), b - h * Math.sin(t + 0.4));
      g.stroke();
    },
    text: (p, n, x, y) => { g.fillStyle = ink("text"); g.fillText(str(p, n), x, y); },
  } });
  e = w.instance.exports;
  const applyFocus = () => {
    if (!lastS || !wl) return;
    const ks = wl.children, base = lastS.f.length + 1;
    const fi = lastS.c.findIndex((c) => c.k === foc);
    const lit = new Set();
    if (fi >= 0) {
      lit.add(fi);
      lastS.l.forEach((l) => {
        if (l[4] === fi) lit.add(l[5]);
        if (l[5] === fi) lit.add(l[4]);
      });
    }
    lastS.c.forEach((c, i) => {
      const n = ks[base + i];
      if (n) n.style.opacity = (fi < 0 || lit.has(i)) ? '1' : '0.25';
    });
    const ps = wl.querySelectorAll('svg > path');
    lastS.l.forEach((l, i) => {
      if (ps[i]) ps[i].style.opacity = (fi < 0 || l[4] === fi || l[5] === fi) ? '1' : '0.12';
    });
  };
  const render1 = () => {
    if (!e || !e.scene) return;
    const w = Math.round(innerWidth);
    if (!wl) {
      wl = mk("div", "position:fixed;left:0;top:0;transform-origin:0 0;pointer-events:none;font:15px/1.4 system-ui,sans-serif");
      document.body.appendChild(wl);
    }
    const farNow = isFar();
    const zs = farNow ? Math.pow(1.15, Math.round(Math.log(z) / Math.log(1.15))) : 0;
    const sig = ver + "|" + w + "|" + tsig + "|" + zs;
    if (sig !== lsig) {
      lsig = sig;
      wl.textContent = "";
      let s = null;
      try {
        if (e.set_far) e.set_far(zs);
        const n = e.scene(w);
        s = JSON.parse(str(e.scene_ptr(), n));
      } catch (x) { s = null; }
      if (s) {
        const dim = ink("dim"), fg = ink("text");
        const bg = T.bg && T.bg !== "none" ? T.bg : "Canvas";
        const fill = T.fill && T.fill !== "none" ? T.fill : bg;
        const rad = T.corner === "square" ? 0 : 12;
        const sp = (k, d) => { const v = e.style ? e.style(k) : 0; return v > 0 ? v : d; };
        s.f.forEach((f) => {
          const d = mk("div", `position:absolute;box-sizing:border-box;left:${f.x}px;top:${f.y}px;width:${f.w}px;height:${f.h}px;border:1px solid ${dim};border-radius:${rad}px`);
          d.appendChild(mk("span", `position:absolute;top:-10px;left:14px;padding:0 8px;font-size:${sp(4, 13)}px;font-weight:600;background:${bg};color:${fg}`, f.t));
          if (f.d) d.appendChild(mk("div", `position:absolute;left:16px;right:16px;top:14px;font-size:${sp(3, 12)}px;line-height:1.35;color:${dim};display:-webkit-box;-webkit-line-clamp:3;-webkit-box-orient:vertical;overflow:hidden`, f.d));
          wl.appendChild(d);
        });
        const sv = document.createElementNS("http://www.w3.org/2000/svg", "svg");
        sv.setAttribute("style", "position:absolute;left:0;top:0;width:1px;height:1px;overflow:visible");
        const head = T.arrow !== "none" && T.arrow !== "plain";
        const me = head ? " marker-end=\"url(#ah)\"" : "";
        let h = "";
        if (head) h += `<defs><marker id="ah" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="9" markerHeight="9" orient="auto"><path d="M0 0L10 5L0 10z" fill="${dim}"/></marker></defs>`;
        s.l.forEach((l) => {
          const x1 = l[0], y1 = l[1], x2 = l[2], y2 = l[3];
          const kk = e.curve ? e.curve() : 0.5;
          const mx = x1 + (x2 - x1) * kk, my = y1 + (y2 - y1) * kk;
          const d = Math.abs(x2 - x1) >= Math.abs(y2 - y1)
            ? `M${x1} ${y1}C${mx} ${y1} ${mx} ${y2} ${x2} ${y2}`
            : `M${x1} ${y1}C${x1} ${my} ${x2} ${my} ${x2} ${y2}`;
          h += `<path d="${d}" fill="none" stroke="${dim}" stroke-width="1.5"${me}/>`;
        });
        sv.innerHTML = h;
        wl.appendChild(sv);
        lastS = s;
        s.c.forEach((c) => {
          const d = mk("div", `position:absolute;box-sizing:border-box;left:${c.x}px;top:${c.y}px;width:${s.bw}px;height:${c.h || s.bh}px;padding:${sp(0, 10)}px ${sp(1, 12)}px;overflow:visible;overflow-wrap:anywhere;background:${fill};border:1px solid ${dim};border-radius:${rad}px`);
          d.appendChild(mk("div", `font-size:${sp(2, 15)}px;font-weight:600;overflow-wrap:anywhere;color:${fg}`, c.t));
          if (c.d) d.appendChild(mk("div", `margin-top:3px;font-size:${sp(3, 12)}px;line-height:1.35;color:${dim};overflow-wrap:anywhere`, c.d));
          wl.appendChild(d);
        });
      }
    }
    applyFocus();
    if (lastS) {
      const far = isFar(), ks = wl.children;
      for (let i = lastS.f.length; i < ks.length; i++) ks[i].style.display = far ? "none" : "";
      const hd = e.style ? e.style(6) : 20;
      const F = lastS.f;
      F.forEach((f, i) => {
        const n = ks[i], t = n.children[0], dd = n.children[1];
        t.style.whiteSpace = "nowrap"; t.style.transformOrigin = "0 0"; t.style.transform = "";
        t.style.display = "";
        if (dd) { dd.style.transformOrigin = "0 0"; dd.style.transform = ""; dd.style.right = ""; dd.style.width = ""; dd.style.top = ""; dd.style.display = ""; }
        if (!far) return;
        const lw = t.offsetWidth || 1, th = t.offsetHeight || 14;
        const s = Math.min(1 / z, (f.w - 28) / lw);
        if (s * z * th < 8) { t.style.display = "none"; if (dd) dd.style.display = "none"; return; }
        t.style.transform = "scale(" + s + ")";
        if (!dd) return;
        const leaf = !F.some((o, j) => j !== i && o.x >= f.x && o.y >= f.y && o.x + o.w <= f.x + f.w && o.y + o.h <= f.y + f.h);
        if (!leaf) { dd.style.display = "none"; return; }
        dd.style.top = (th * s - 6) + "px"; dd.style.right = "auto";
        dd.style.width = ((f.w - 32) / s) + "px";
        dd.style.transform = "scale(" + s + ")";
        if (th * s - 6 + dd.offsetHeight * s > f.h - 4) dd.style.display = "none";
      });
    }
    wl.style.transform = "scale(" + z + ") translate(" + (-ox) + "px," + (-oy) + "px)";
  };
  const slots = [
    { wl: null, ls: "", s: null, zk: null },
    { wl: null, ls: "", s: null, zk: null },
  ];
  const layer = (sl, far) => {
    const a = wl, b = lsig, c = lastS;
    wl = sl.wl; lsig = sl.ls; lastS = sl.s; ff = far;
    try { render1(); } finally {
      sl.wl = wl; sl.ls = lsig; sl.s = lastS;
      wl = a; lsig = b; lastS = c; ff = null;
    }
  };
  const ghost = (el) => {
    const k = el.cloneNode(true);
    k.style.transition = "opacity 0.3s";
    k.style.pointerEvents = "none";
    document.body.appendChild(k);
    requestAnimationFrame(() => { k.style.opacity = "0"; });
    setTimeout(() => k.remove(), 350);
  };
  const render = () => {
    if (!e || !e.scene) return;
    const c0 = e.style ? e.style(5) : 0, c = c0 > 0 ? c0 : 0.5;
    const bd = e.style && e.style(7) > 0 ? e.style(7) : 0.3; const lo = c * (1 - bd), hi = c * (1 + bd);
    const t = Math.min(1, Math.max(0, (z - lo) / (hi - lo)));
    const N = slots[0], F = slots[1];
    if (t > 0) {
      layer(N, false);
      if (N.wl) {
        N.wl.style.transition = "opacity 0.25s";
        N.wl.style.display = "";
        N.wl.style.opacity = String(t);
      }
    } else if (N.wl) N.wl.style.display = "none";
    if (t < 1) {
      const zk = Math.round(Math.log(z) / Math.log(1.15));
      let re = false;
      if (F.wl && F.zk !== null && F.zk !== zk && F.wl.style.display !== "none") {
        ghost(F.wl); re = true;
      }
      layer(F, true);
      F.zk = zk;
      if (F.wl) {
        if (re) {
          F.wl.style.transition = "none";
          F.wl.style.opacity = "0";
          void F.wl.offsetWidth;
        }
        F.wl.style.transition = "opacity 0.3s";
        F.wl.style.display = "";
        F.wl.style.opacity = String(1 - t);
      }
    } else if (F.wl) F.wl.style.display = "none";
  };
  const paint = () => {
    cv.width = innerWidth; cv.height = innerHeight;
    g.setTransform(1, 0, 0, 1, 0, 0);
    g.clearRect(0, 0, cv.width, cv.height);
    if (T.bg && T.bg !== "none") { g.fillStyle = T.bg; g.fillRect(0, 0, cv.width, cv.height); }
    const s = 48 * z;
    const fx = ((((-ox * z) % s) + s) % s) - s, fy = ((((-oy * z) % s) + s) % s) - s;
    g.globalAlpha = T.grid === "off" ? 0 : 0.25; g.strokeStyle = ink("dim"); g.lineWidth = 1; g.beginPath();
    for (let x = fx; x < cv.width; x += s) { g.moveTo(x, 0); g.lineTo(x, cv.height); }
    for (let y = fy; y < cv.height; y += s) { g.moveTo(0, y); g.lineTo(cv.width, y); }
    g.stroke();
    g.globalAlpha = 1; g.setTransform(z, 0, 0, z, 0, 0);
    g.lineWidth = 1.5 / z; g.font = "600 14px system-ui,sans-serif"; g.textBaseline = "top";
    render();
  };
  let tz = 0, anc = null, raf = 0;
  const tick = () => {
    raf = 0;
    const d = tz - z;
    if (Math.abs(d) < z * 0.002) z = tz; else z += d * (e.style && e.style(8) > 0 ? e.style(8) : 0.16);
    if (anc) { ox = anc.wx - anc.nx / z; oy = anc.wy - anc.ny / z; }
    paint();
    if (z !== tz) raf = requestAnimationFrame(tick);
  };
  const zoomAt = (mx, my, nz, nx, ny) => {
    tz = Math.min(4, Math.max(0.2, nz));
    anc = { wx: ox + mx / z, wy: oy + my / z, nx: nx, ny: ny };
    if (!raf) raf = requestAnimationFrame(tick);
  };
  const load = async () => {
    const d = new Uint8Array(await (await fetch("index.db")).arrayBuffer()), p = put(d);
    e.load_index(p, d.length); e.free_buf(p, d.length); ver++; paint();
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
      if (d0 > 0) zoomAt(m0x, m0y, (tz || z) * Math.pow(d1 / d0, 0.7), m1x, m1y);
    }
    pts = n; paint();
  }, { passive: false });
  addEventListener("touchend", (v) => {
    const t = v.changedTouches[0], s = st;
    pts = grab(v.touches);
    if (!ov && s && !mv && v.touches.length === 0 && t) { lt = Date.now(); tap(t.clientX, t.clientY); }
    if (v.touches.length === 0) st = null;
  });
  addEventListener("wheel", (v) => {
    if (ov) return;
    v.preventDefault();
    zoomAt(v.clientX, v.clientY, (tz || z) * Math.exp(-v.deltaY * (e.style && e.style(9) > 0 ? e.style(9) : 0.0006)), v.clientX, v.clientY);
    paint();
  }, { passive: false });
  let md = null;
  addEventListener("mousedown", (v) => {
    if (ov) return;
    md = [v.clientX, v.clientY]; st = [v.clientX, v.clientY]; mv = false;
  });
  addEventListener("mouseup", (v) => {
    if (!ov && st && !mv && Date.now() - lt > 800) tap(v.clientX, v.clientY);
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
