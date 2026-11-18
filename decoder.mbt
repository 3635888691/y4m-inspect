///|
/// Errors are terminal: discard the decoder after an error.
#derive(Debug)
pub suberror DecodeError {
  BadHeader(String)
  IncompleteHeader
  IncompleteFrame(Int32, Int32)
  AlreadyFinished
}

///|
#derive(Debug, Eq)
pub(all) struct VideoInfo {
  width : Int32
  height : Int32
  chroma : String
  fps_num : Int32
  fps_den : Int32
}

///|
#derive(Debug, Eq)
pub(all) struct Frame {
  index : Int32
  minimum : Int32
  maximum : Int32
}

///|
pub struct Decoder {
  mut video : VideoInfo?
  line : StringBuilder
  mut length : Int32
  mut remaining : Int32
  mut luma_left : Int32
  mut frame_count : Int32
  mut lo : Int32
  mut hi : Int32
  mut done : Bool
}

///|
pub fn Decoder::new() -> Decoder {
  {
    video: None,
    line: StringBuilder(),
    length: 0,
    remaining: 0,
    luma_left: 0,
    frame_count: 0,
    lo: 255,
    hi: 0,
    done: false,
  }
}

///|
fn positive(s : StringView) -> Int32 raise DecodeError {
  let mut n = 0
  for c in s {
    if c < '0' || c > '9' {
      raise BadHeader("expected decimal digits")
    }
    let digit = c.to_int() - 48
    if n > (2147483647 - digit) / 10 {
      raise BadHeader("decimal overflow")
    }
    n = n * 10 + digit
  }
  if n == 0 {
    raise BadHeader("expected positive integer")
  }
  n
}

///|
fn read_header(line : String) -> VideoInfo raise DecodeError {
  let parts = line.split(" ")
  if parts.next() != Some("YUV4MPEG2") {
    raise BadHeader("file signature")
  }
  let mut w = 0
  let mut h = 0
  let mut chroma = ""
  let mut f = (0, 0)
  for part in parts {
    if part.is_empty() {
      continue
    }
    if part.has_prefix("W") {
      if w != 0 {
        raise BadHeader("duplicate width")
      }
      w = positive(part[1:])
    } else if part.has_prefix("H") {
      if h != 0 {
        raise BadHeader("duplicate height")
      }
      h = positive(part[1:])
    } else if part.has_prefix("C") {
      if chroma != "" {
        raise BadHeader("duplicate colorspace")
      }
      let value = part[1:].to_owned()
      if value != "mono" && value != "420jpeg" {
        raise BadHeader("unsupported colorspace")
      }
      chroma = value
    } else if part.has_prefix("F") {
      if f.0 != 0 {
        raise BadHeader("duplicate frame rate")
      }
      match part[1:].split_once(":") {
        Some((a, b)) => f = (positive(a), positive(b))
        None => raise BadHeader("frame rate")
      }
    } else if !part.has_prefix("A") &&
      !part.has_prefix("I") &&
      !part.has_prefix("X") {
      raise BadHeader("unsupported header tag")
    }
  }
  if w == 0 || h == 0 || w > 67108864 / h {
    raise BadHeader("dimensions outside limit")
  }
  if chroma == "" {
    chroma = "420jpeg"
  }
  if chroma == "420jpeg" && (w % 2 != 0 || h % 2 != 0) {
    raise BadHeader("420 requires even dimensions")
  }
  { width: w, height: h, chroma, fps_num: f.0, fps_den: f.1, }
}

///|
pub fn Decoder::feed(
  self : Decoder,
  bytes : Bytes,
  emit : (Frame) -> Unit,
) -> Unit raise DecodeError {
  if self.done {
    raise AlreadyFinished
  }
  // Keep terminal state if any operation throws.
  self.done = true
  for byte in bytes {
    if self.remaining > 0 {
      if self.luma_left > 0 {
        self.lo = Int32::min(self.lo, byte.to_int())
        self.hi = Int32::max(self.hi, byte.to_int())
        self.luma_left -= 1
      }
      self.remaining -= 1
      if self.remaining == 0 {
        emit({ index: self.frame_count, minimum: self.lo, maximum: self.hi, })
        self.frame_count += 1
      }
    } else if byte == b'\n' {
      let s = self.line.to_string()
      self.line.reset()
      self.length = 0
      match self.video {
        None => self.video = Some(read_header(s))
        Some(v) => {
          if s != "FRAME" && !s.has_prefix("FRAME ") {
            raise BadHeader("frame marker")
          }
          if self.frame_count == 2147483647 {
            raise BadHeader("frame count overflow")
          }
          let y = v.width * v.height
          self.luma_left = y
          self.remaining = if v.chroma == "mono" { y } else { y + y / 2 }
          self.lo = 255
          self.hi = 0
        }
      }
    } else {
      if byte.to_int() < 32 || byte.to_int() > 126 || self.length >= 8192 {
        raise BadHeader("illegal or oversized header")
      }
      self.line.write_char(byte.to_char())
      self.length += 1
    }
  }
  self.done = false
}

///|
pub fn Decoder::finish(self : Decoder) -> (VideoInfo, Int32) raise DecodeError {
  if self.done {
    raise AlreadyFinished
  }
  self.done = true
  if self.remaining != 0 {
    raise IncompleteFrame(self.frame_count, self.remaining)
  }
  if self.length != 0 {
    raise IncompleteHeader
  }
  match self.video {
    Some(v) => (v, self.frame_count)
    None => raise IncompleteHeader
  }
}
