#!/usr/bin/env python3
"""Measure delivered fps/stability of an RTSP (or TCP) stream from the Mac.

Usage: measure_fps.py <url> <seconds> [transport]
  transport: tcp (default) or udp  -- only affects RTSP URLs
Prints: delivered fps, frame count, resolution, and inter-frame-gap stats
(a proxy for stutter/freezes).
"""
import sys, time, os

url = sys.argv[1]
dur = float(sys.argv[2]) if len(sys.argv) > 2 else 30.0
transport = sys.argv[3] if len(sys.argv) > 3 else "tcp"

# Low-latency FFmpeg options for OpenCV's backend.
os.environ["OPENCV_FFMPEG_CAPTURE_OPTIONS"] = (
    f"rtsp_transport;{transport}|fflags;nobuffer|flags;low_delay|max_delay;0"
)

import cv2  # noqa: E402

cap = cv2.VideoCapture(url, cv2.CAP_FFMPEG)
if not cap.isOpened():
    print(f"ERROR: could not open {url}")
    sys.exit(1)

w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
print(f"opened {url}  {w}x{h}  transport={transport}")

n = 0
gaps = []
t0 = time.time()
tprev = t0
first = None
while time.time() - t0 < dur:
    ok, frame = cap.read()
    now = time.time()
    if not ok:
        print(f"[{now - t0:5.1f}s] read FAILED (stream drop?)")
        time.sleep(0.05)
        continue
    if first is None:
        first = now
    if n > 0:
        gaps.append(now - tprev)
    tprev = now
    n += 1
cap.release()

elapsed = tprev - (first if first else t0)
fps = (n - 1) / elapsed if elapsed > 0 and n > 1 else 0.0
print(f"\n=== RESULT ({url}) ===")
print(f"frames: {n}   window: {elapsed:5.1f}s   delivered fps: {fps:5.2f}")
if gaps:
    gaps_sorted = sorted(gaps)
    p50 = gaps_sorted[len(gaps_sorted)//2] * 1000
    p99 = gaps_sorted[min(len(gaps_sorted)-1, int(len(gaps_sorted)*0.99))] * 1000
    mx = max(gaps) * 1000
    big = sum(1 for g in gaps if g > 0.15)  # >150ms gap ~ visible stutter at 30fps
    print(f"inter-frame gap ms: p50={p50:.1f}  p99={p99:.1f}  max={mx:.1f}")
    print(f"gaps >150ms (stutter events): {big}")
