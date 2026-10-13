#!/bin/bash
# Helmet-cam capture+encode pipeline -> publishes H.264 to local MediaMTX.
# Rockchip ISP (rkaiq 3A) -> hardware H.264 (mpph264enc) -> RTSP publish.
set -u

CAM_DEV="${CAM_DEV:-/dev/video0}"
WIDTH="${WIDTH:-1280}"
HEIGHT="${HEIGHT:-720}"
BITRATE="${BITRATE:-4000000}"      # bits/s target (CBR)
BITRATE_MAX="${BITRATE_MAX:-6000000}"
GOP="${GOP:-30}"                    # keyframe interval (frames) ~1s; low = fast loss recovery
RTSP_URL="${RTSP_URL:-rtsp://localhost:8554/cam}"

# Wait for the ISP capture node to exist (camera overlay up) before starting.
for i in $(seq 1 30); do
  [ -e "$CAM_DEV" ] && break
  sleep 1
done

exec gst-launch-1.0 -e \
  v4l2src device="$CAM_DEV" io-mode=dmabuf ! \
  video/x-raw,format=NV12,width="$WIDTH",height="$HEIGHT" ! \
  queue leaky=downstream max-size-buffers=3 ! \
  mpph264enc rc-mode=cbr bps="$BITRATE" bps-max="$BITRATE_MAX" \
             gop="$GOP" header-mode=each-idr profile=high level=40 ! \
  h264parse config-interval=-1 ! \
  rtspclientsink location="$RTSP_URL" protocols=tcp latency=0
