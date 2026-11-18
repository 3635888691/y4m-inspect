"""Black-box tests of the built Node CLI. No third-party Python packages."""
from pathlib import Path
import unittest, json, subprocess, sys
ROOT = Path(__file__).resolve().parents[1]
CLI = Path(sys.argv.pop(1)).resolve() if len(sys.argv) > 1 else ROOT / "_build/js/debug/build/cmd/inspect/inspect.js"
def run(*args, data=None):
    return subprocess.run(["node", str(CLI), *args], input=data, cwd=ROOT, capture_output=True, timeout=30)
def rows(stream):
    return [json.loads(line) for line in stream.splitlines()]

class EndToEnd(unittest.TestCase):
    def test_file_and_stdin(self):
        name = "two-frames.y4m"
        expected = json.loads((ROOT/"expected.json").read_bytes())[name]
        direct, piped = run(name), run("-", data=(ROOT/name).read_bytes())
        self.assertEqual((direct.returncode,piped.returncode), (0,0))
        self.assertEqual(direct.stdout,piped.stdout)
        self.assertFalse(direct.stderr)
        *frames, summary = rows(direct.stdout)
        self.assertEqual(summary["frames"],expected["frames"])
        self.assertEqual([f["index"] for f in frames],[0,1])
        self.assertEqual([[f["min"],f["max"]] for f in frames],expected["luma_min_max"])

    def test_truncated(self):
        name = "truncated.y4m"
        r=run(name)
        self.assertEqual(r.returncode,1)
        self.assertEqual([f["type"] for f in rows(r.stdout)], ["frame"])
        self.assertEqual(rows(r.stderr),[{"type":"error",**json.loads((ROOT/"expected.json").read_bytes())[name]}])

    def test_cross_chunk_and_ignore_chroma(self):
        y = bytes([23,203]) * 65536
        chroma = bytes([0,255]) * 32768
        head=b"YUV4MPEG2 W512 H256 C420jpeg F24000:1001\n"
        data=head+(b"FRAME Xtest\n"+y+chroma)*2
        r=run("-",data=data)
        self.assertEqual(r.returncode,0,r.stderr)
        *frames,summary=rows(r.stdout)
        self.assertEqual([(f["min"],f["max"]) for f in frames],[(23,203),(23,203)])
        self.assertEqual(summary,dict(type="summary",width=512,height=256,fps_num=24000,fps_den=1001,chroma="420jpeg",frames=2))

    def test_io_usage(self):
        self.assertEqual(run("--help").returncode,0)
        self.assertEqual(run().returncode,2)
        missing=run("nonexistent-input-do-not-create.y4m")
        self.assertEqual(missing.returncode,2)
        self.assertEqual(rows(missing.stderr)[0]["error"],"IOError")

if __name__ == "__main__":
    unittest.main()
