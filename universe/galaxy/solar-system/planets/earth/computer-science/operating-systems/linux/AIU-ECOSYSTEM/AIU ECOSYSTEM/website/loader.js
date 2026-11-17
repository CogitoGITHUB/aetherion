(async () => {
  const o = document.getElementById("o");
  try {
    const w = await WebAssembly.instantiateStreaming(fetch("bridge.wasm"));
    const e = w.instance.exports;
    const d = new Uint8Array(await (await fetch("index.db")).arrayBuffer());
    const p = e.alloc(d.length);
    new Uint8Array(e.memory.buffer, p, d.length).set(d);
    const n = e.load_index(p, d.length);
    e.free_buf(p, d.length);
    o.textContent = "blocks " + n;
  } catch (x) { o.textContent = "error " + x; }
})();
