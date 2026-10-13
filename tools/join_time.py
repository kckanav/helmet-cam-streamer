#!/usr/bin/env python3
"""Measure WebRTC/RTSP 'join latency' = time from a fresh connect to the first
decoded frame. For a fixed-GOP stream this is dominated by the wait for the next
keyframe (uniform in [0, GOP]), so a shorter GOP lowers the median. Each trial
opens a brand-new RTSP session over UDP and pulls exactly one frame.

Usage: join_time.py <rtsp_url> [trials]
"""
import subprocess, time, sys

url = sys.argv[1]
n = int(sys.argv[2]) if len(sys.argv) > 2 else 6
times = []
for i in range(n):
    t0 = time.time()
    subprocess.run(
        ["ffmpeg", "-rtsp_transport", "udp", "-fflags", "nobuffer",
         "-probesize", "32", "-analyzeduration", "0", "-flags", "low_delay",
         "-i", url, "-frames:v", "1", "-f", "null", "-"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    dt = (time.time() - t0) * 1000
    times.append(dt)
    print(f"  trial {i+1}: {dt:.0f} ms")
    time.sleep(0.6)
times.sort()
med = times[len(times) // 2]
print(f"=> join latency: min {min(times):.0f}  median {med:.0f}  max {max(times):.0f} ms  (n={n})")
