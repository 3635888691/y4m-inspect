"""Generate a real Y4M stream; compare every frame to FFmpeg raw decoded Y."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile
from time import perf_counter

ap = argparse.ArgumentParser()
ap.add_argument("--ffmpeg", default="ffmpeg")
ap.add_argument("--cli", default="_build/js/debug/build/cmd/inspect/inspect.js")
args = ap.parse_args()
cli = Path(args.cli).resolve()
def ff(*options):
    return subprocess.run([args.ffmpeg,"-nostdin","-v","error",*options],capture_output=True,check=True).stdout
with tempfile.TemporaryDirectory() as td:
    p=Path(td)/"video.y4m"
    w,h,n=512,256,120
    ff("-f","lavfi","-i",f"testsrc2=size={w}x{h}:rate=25","-frames:v",str(n),"-pix_fmt","yuv420p",
       "-chroma_sample_location","center","-f","yuv4mpegpipe",str(p))
    raw=ff("-i",str(p),"-pix_fmt","yuv420p","-f","rawvideo","pipe:1")
    stride=w*h*3//2
    assert len(raw)==n*stride
    expected=[(min(raw[i*stride:i*stride+w*h]),max(raw[i*stride:i*stride+w*h])) for i in range(n)]
    start=perf_counter()
    run=subprocess.run(["node",str(cli),str(p)],capture_output=True,check=True)
    elapsed=perf_counter()-start
    *frames,summary=map(json.loads,run.stdout.splitlines())
    assert [row["index"] for row in frames]==list(range(n))
    assert [(row["min"],row["max"]) for row in frames]==expected
    assert summary==dict(type="summary",width=w,height=h,fps_num=25,fps_den=1,chroma="420jpeg",frames=n)
    print(json.dumps({"ffmpeg":ff("-version").splitlines()[0].decode(),"frames_verified":n,"input_bytes":p.stat().st_size,
                      "seconds_including_node_startup":round(elapsed,4),"MiB_per_s":round(p.stat().st_size/(1024**2*elapsed),1)}))
