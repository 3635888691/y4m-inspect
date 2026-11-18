///|
/// Node handles binary I/O; the parser, error classification and report live in MoonBit.
extern "js" fn drive(feed : (Bytes) -> Bool, finish : () -> Bool) -> Unit =
  #|(feed, finish) => {
  #|  const args = process.argv.slice(2);
  #|  if (args.length === 1 && args[0] === "--help") {
  #|    console.log("Usage: y4m-inspect FILE | -   (NDJSON on stdout)");
  #|    return;
  #|  }
  #|  if (args.length !== 1) { console.error("Usage: y4m-inspect FILE | -"); process.exitCode = 2; return; }
  #|  const fs = process.getBuiltinModule("node:fs");
  #|  const owns = args[0] !== "-";
  #|  let fd;
  #|  try {
  #|    fd = owns ? fs.openSync(args[0], "r") : 0;
  #|    const buf = Buffer.alloc(65536);
  #|    while (true) {
  #|      const n = fs.readSync(fd, buf, 0, buf.length, null);
  #|      if (n === 0) break;
  #|      if (!feed(buf.subarray(0,n))) { process.exitCode = 1; return; }
  #|    }
  #|    if (!finish()) process.exitCode = 1;
  #|  } catch(e) {
  #|    console.error(JSON.stringify({type:"error", error:"IOError", code:e.code || "UNKNOWN"}));
  #|    process.exitCode = 2;
  #|  } finally { if (owns && fd !== undefined) fs.closeSync(fd); }
  #|}

///|
/// Use blocking writes for backpressure and handle partial writes to pipes.
extern "js" fn output(fd : Int32, record : String) -> Unit =
  #|(fd, record) => {
  #| const fs = process.getBuiltinModule("node:fs");
  #| const b = Buffer.from(record + "\n");
  #| for (let p=0; p<b.length;) p += fs.writeSync(fd, b, p, b.length-p);
  #|}

///|
fn report(err : @y4m.DecodeError) -> Bool {
  let record : Json = match err {
    @y4m.IncompleteFrame(index, missing) =>
      {
        "type": "error",
        "error": "TruncatedFrame",
        "frame_index_zero_based": index,
        "missing_bytes": missing,
      }
    @y4m.IncompleteHeader => { "type": "error", "error": "IncompleteHeader" }
    @y4m.BadHeader(detail) =>
      { "type": "error", "error": "BadHeader", "detail": detail }
    @y4m.AlreadyFinished => { "type": "error", "error": "AlreadyFinished" }
  }
  output(2, record.stringify())
  false
}

///|
fn main {
  let decoder = @y4m.Decoder::new()
  drive(
    chunk => {
      try {
        decoder.feed(chunk, f => {
          let row : Json = {
            "type": "frame",
            "index": f.index,
            "min": f.minimum,
            "max": f.maximum,
          }
          output(1, row.stringify())
        })
        true
      } catch {
        e => report(e)
      }
    },
    () => {
      try {
        let (v, n) = decoder.finish()
        let row : Json = {
          "type": "summary",
          "width": v.width,
          "height": v.height,
          "fps_num": v.fps_num,
          "fps_den": v.fps_den,
          "chroma": v.chroma,
          "frames": n,
        }
        output(1, row.stringify())
        true
      } catch {
        e => report(e)
      }
    },
  )
}
