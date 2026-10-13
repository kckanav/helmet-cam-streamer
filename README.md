# Helmet-Cam Streamer

Low-latency Wi-Fi video streaming from a head-mounted industrial camera to a browser on the
local network, built on a **Radxa Zero 3W** (Rockchip RK3566) with hardware H.264 encoding.
The wearer moves around a plant; the board streams over Wi-Fi to a relay/viewer that can
republish for outside access.

Design priorities, in order: **smallest size → good image quality → minimum latency →
reliable Wi-Fi while moving.**

---

## Architecture

```
IMX219-160 fisheye ──CSI──> Rockchip ISP (rkaiq 3A) ──NV12──> mpph264enc (HW H.264)
                                                                   │
                                                            h264parse
                                                                   │
                                                     rtspclientsink (localhost)
                                                                   ▼
                                                            MediaMTX
                                               ┌───────────────┴───────────────┐
                                         WebRTC :8889                    RTSP :8554
                                        (browser, UDP)                (VLC/ffmpeg)
```

- **Capture + 3A:** Rockchip ISP via the vendor `rkaiq_3A` engine (proper IMX219 IQ tuning).
- **Encode:** hardware H.264 (`mpph264enc`, VideoCore-equivalent RK VPU) — ~0% CPU.
- **Transport:** [MediaMTX](https://github.com/bluenviron/mediamtx) serves WebRTC (UDP, low
  latency) + RTSP on the LAN. Handles NACK/PLI and the browser client out of the box.

### Streaming optimizations (Zoom/Meet-class techniques)

| Technique | Status | How |
|---|---|---|
| UDP / WebRTC end-to-end | ✅ | MediaMTX WebRTC (DTLS-SRTP over UDP) |
| NACK / PLI retransmission | ✅ | MediaMTX WebRTC leg |
| Short-GOP + each-IDR headers | ✅ | `mpph264enc gop=30 header-mode=each-idr`, `h264parse config-interval=-1` |
| Closed-loop adaptive bitrate (GCC) | 🚧 Tier 2 | `webrtcsink` + `rtpgccbwe` from `gst-plugins-rs` (built from source — see `radxa/build/`) |
| Intra-refresh | ⛔ | Not exposed by the Rockchip `mpph264enc` GStreamer element; emulated via short GOP + each-IDR |
| FEC | 🚧 Tier 2 | `webrtcsink do-fec` |

Tier 1 (everything except GCC adaptive bitrate / FEC) is deployed and running. Tier 2 adds
sender-side congestion control so the stream degrades gracefully as the Wi-Fi uplink varies
while the wearer moves — the piece MediaMTX alone cannot do.

---

## Hardware

- **Board:** Radxa Zero 3W (RK3566 quad A55, 2 GB, Wi-Fi 6 / 5 GHz), copper heatsink.
- **Camera:** Waveshare **IMX219-160** (8 MP, 160° fisheye, fixed focus) — uses the `imx219`
  driver (RPi Camera v2 compatible).
- **Power:** 5 V USB-C from a 30 W (9V3A-capable) power bank. **Power is the #1 reliability
  risk** — a weak supply browns out at camera init. Use a short, thick cable.

---

## Repo layout

```
radxa/
  mediamtx.yml                  MediaMTX config (WebRTC :8889 + RTSP :8554, LAN-only ICE)
  helmetcam-stream.sh           capture + HW-encode pipeline -> MediaMTX
  systemd/
    mediamtx.service            the relay server (Restart=always, boot-enabled)
    helmetcam-stream.service    the pipeline (After=mediamtx + rkaiq, Restart=always)
  build/
    build_webrtcsink.sh         builds gst-plugins-rs webrtcsink + rtpgccbwe on-board (Tier 2)
tools/                          Mac-side measurement helpers (fps, glass-to-glass latency)
docs/
```

---

## Deploy (on the board)

Assumes Radxa OS (Debian 12), the IMX219 overlay enabled
(`radxa-zero3-rpi-camera-v2` via `rsetup` / `u-boot-update`), and GStreamer + the Rockchip
plugins installed (`gstreamer1.0-rockchip1`, `librockchip-mpp1`, `librga2`, `gstreamer1.0-rtsp`).

```bash
# MediaMTX (arm64)
sudo install -m755 mediamtx                 /usr/local/bin/mediamtx
sudo install -m644 radxa/mediamtx.yml       /usr/local/etc/mediamtx.yml
# pipeline
sudo install -m755 radxa/helmetcam-stream.sh /usr/local/bin/helmetcam-stream.sh
# services
sudo install -m644 radxa/systemd/*.service  /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now mediamtx helmetcam-stream
```

### View

- Browser (WebRTC): `http://<board-ip>:8889/cam/`
- RTSP: `rtsp://<board-ip>:8554/cam`

---

## Current numbers

- 1280×720, ~20–21 fps (sensor/ISP capped on this image; supersampled from the full sensor,
  full fisheye FoV), H.264 High, CBR ~4 Mbps, GOP 30 (each-IDR).
- Board ~64 °C under encode (console-boot, heatsink on). Throttles ~85 °C.
- Auto-starts on boot; survives reboots (verified).

## Tuning notes / gotchas

- **Headless + thermal:** run `multi-user.target` (console) not `graphical.target` — the
  GNOME desktop idles the SoC hot (~70–80 °C vs ~64 °C).
- **Framerate:** the IMX219+RKISP path caps at ~20 fps here regardless of declared sensor
  mode; true 30 fps needs device-tree/link-frequency work. H.264 and H.265 encode at the same
  rate, so the encoder is not the bottleneck.
- **No `rtspclientsink`?** install `gstreamer1.0-rtsp`.
- **`gst-plugins-rs` build:** the Radxa image has an unresolvable mesa/drm `-dev` situation, so
  `build_webrtcsink.sh` installs the GStreamer dev headers by extracting the `.deb`s directly.

---

## Roadmap

- [x] Tier 1: HW H.264 → MediaMTX → WebRTC/RTSP on LAN, boot-persistent
- [ ] Tier 2: `webrtcsink` + `rtpgccbwe` closed-loop adaptive bitrate + FEC
- [ ] Relay machine that republishes for outside access
- [ ] Fisheye de-warp at the relay; recording (visually lossless) as a later feature
- [ ] Board comparison: Radxa Zero 3W vs Pi Zero 2 W (latency, fps, Wi-Fi, temp)
