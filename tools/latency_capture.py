#!/usr/bin/env python3
"""Glass-to-glass latency capture.

Reads the live RTSP stream, stays current (low-latency flags + drain), then
saves a frame with the exact RECEIVE wall-clock time burned into it. Compare
that burned-in time to the clock digits the camera sees (latency_clock.html):
    latency_ms = (burned-in receive time) - (clock value shown in the frame)
Both come from the same Mac clock, so there is no clock-sync error.

Usage: latency_capture.py <rtsp_url> <out.jpg> [transport]
"""
import sys, os, time

url = sys.argv[1]
out = sys.argv[2] if len(sys.argv) > 2 else "latency_frame.jpg"
transport = sys.argv[3] if len(sys.argv) > 3 else "udp"

os.environ["OPENCV_FFMPEG_CAPTURE_OPTIONS"] = (
    f"rtsp_transport;{transport}|fflags;nobuffer|flags;low_delay|max_delay;0"
)
import cv2

cap = cv2.VideoCapture(url, cv2.CAP_FFMPEG)
try:
    cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)
except Exception:
    pass
if not cap.isOpened():
    print("ERROR: cannot open", url); sys.exit(1)

# Warm up + continuously drain so the next read is the freshest frame.
t_end = time.time() + 3.0
frame = None
while time.time() < t_end:
    ok, f = cap.read()
    if ok:
        frame = f
# One final read, timestamped as close as possible to receipt.
ok, f = cap.read()
t_recv = time.time()
if ok:
    frame = f
cap.release()
if frame is None:
    print("ERROR: no frame"); sys.exit(1)

# Burn the receive wall-clock time (sec.ms within the minute) onto the frame.
s = int(t_recv) % 60
m = int((t_recv - int(t_recv)) * 1000)
label = f"RECV {s:02d}.{m:03d}"
cv2.rectangle(frame, (0, 0), (frame.shape[1], 60), (0, 0, 0), -1)
cv2.putText(frame, label, (10, 45), cv2.FONT_HERSHEY_SIMPLEX, 1.4,
            (0, 255, 255), 3, cv2.LINE_AA)
cv2.imwrite(out, frame)
print(f"saved {out}   receive_time={label}  ({frame.shape[1]}x{frame.shape[0]})")
print("latency_ms = RECV - (clock digits visible in the frame)")
