///|
fn check_split(data : Bytes, split : Int32) -> (VideoInfo, Array[Frame]) raise {
  let d = Decoder::new()
  let frames = []
  d.feed(Bytes::makei(split, i => data[i]), f => frames.push(f))
  d.feed(Bytes::makei(data.length() - split, i => data[split + i]), f => {
    frames.push(f)
  })
  let (v, n) = d.finish()
  assert_eq(n, frames.length())
  (v, frames)
}

///|
test "mono fixture: every possible two-chunk split" {
  let data = b"YUV4MPEG2 W2 H2 F25:1 Ip A1:1 Cmono\nFRAME\n\x00\x0a\x80\xffFRAME\n\x07\x07\x07\x07"
  for k in 0..<(data.length() + 1) {
    let (v, frames) = check_split(data, k)
    assert_eq(
      (v.width, v.height, v.chroma, v.fps_num, v.fps_den),
      (2, 2, "mono", 25, 1),
    )
    assert_eq(frames, [
      { index: 0, minimum: 0, maximum: 255, },
      { index: 1, minimum: 7, maximum: 7, },
    ])
  }
}

///|
test "420jpeg chroma bytes must not influence luma" {
  let data = b"YUV4MPEG2 W2 H2 C420jpeg Xvendor\nFRAME Xtag\n\x07\x08\x09\x0a\x00\xff"
  let d = Decoder::new()
  let frames = []
  for b in data {
    d.feed(Bytes::from_array([b]), f => frames.push(f))
  }
  let (_, n) = d.finish()
  assert_eq(n, 1)
  assert_eq(frames, [{ index: 0, minimum: 7, maximum: 10, }])
}

///|
test "incomplete second frame has exact missing byte count" {
  let d = Decoder::new()
  d.feed(b"YUV4MPEG2 W2 H2 Cmono\nFRAME\nabcdFRAME\n123", _ => ())
  let ok = try {
    ignore(d.finish())
    false
  } catch {
    IncompleteFrame(1, 1) => true
    _ => false
  }
  assert_true(ok)
}

///|
test "reject malformed headers then refuse reuse" {
  for
    data in [
      b"", b"YUV4MPEG2 W0 H2\n", b"YUV4MPEG2 W3 H3 C420jpeg\n", b"YUV4MPEG2 W2 W2 H2\n",
      b"YUV4MPEG2 W2147483648 H2\n", b"YUV4MPEG2 W1 H1 Cmono\nFR",
    ] {
    let d = Decoder::new()
    let failed = try {
      d.feed(data, _ => ())
      ignore(d.finish())
      false
    } catch {
      _ => true
    }
    assert_true(failed)
    let closed = try {
      d.feed(b"", _ => ())
      false
    } catch {
      AlreadyFinished => true
      _ => false
    }
    assert_true(closed)
  }
}

///|
test "header cap applies across chunks" {
  let d = Decoder::new()
  d.feed(Bytes::make(8192, b'X'), _ => ())
  let failed = try {
    d.feed(b"X", _ => ())
    false
  } catch {
    BadHeader(_) => true
    _ => false
  }
  assert_true(failed)
}
