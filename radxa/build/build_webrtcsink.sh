#!/bin/bash
# Build gst-plugins-rs webrtcsink + rtpgccbwe on the Radxa Zero 3W (RK3566, arm64),
# GStreamer 1.22.9. The Radxa image has an unresolvable mesa/drm -dev situation, so we
# install the GStreamer dev headers by EXTRACTING the .debs (dpkg-deb -x) rather than via
# apt dependency resolution. We skip cargo-c and build the plugin cdylibs directly.
# Detached + fully logged + checkpointed.
set -u
LOG=/tmp/webrtc_build.log
STATE=/tmp/webrtc_build.state
ARCH=aarch64-linux-gnu
PLUGDIR=/usr/lib/$ARCH/gstreamer-1.0
exec > >(stdbuf -oL tee -a "$LOG") 2>&1
echo "============================================================"
echo "=== BUILD START $(date) ==="
step(){ echo "### STEP: $* @ $(date +%H:%M:%S)"; }
fail(){ echo "FAILED: $1"; echo "$1" > "$STATE"; exit 1; }

# 1. swap (avoid OOM on link)
step swap
swapon --show 2>/dev/null | grep -q /swapfile || {
  sudo fallocate -l 6G /swapfile 2>/dev/null || sudo dd if=/dev/zero of=/swapfile bs=1M count=6144
  sudo chmod 600 /swapfile; sudo mkswap /swapfile; sudo swapon /swapfile; }
free -h

# 2. safe (non-gst) build deps — these resolve cleanly
step "apt safe deps"
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  libssl-dev pkg-config clang nasm git curl ca-certificates build-essential libglib2.0-dev \
  || fail apt_failed

# 3. GStreamer dev headers/.pc via .deb extraction (bypass apt dep hell)
step "gst-dev extraction"
WORK=/tmp/gstdev; rm -rf "$WORK"; mkdir -p "$WORK/root"; cd "$WORK"
apt-get download libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev libgstreamer-plugins-bad1.0-dev \
  || fail gstdev_download_failed
for d in *.deb; do dpkg-deb -x "$d" root; done
# merge root/usr into /usr (tar preserves symlinks + merges dirs correctly)
( cd root && sudo tar cf - usr ) | ( cd / && sudo tar xf - )
sudo ldconfig
# verify every .pc the build needs is now resolvable
for pc in gstreamer-1.0 gstreamer-base-1.0 gstreamer-video-1.0 gstreamer-app-1.0 \
          gstreamer-audio-1.0 gstreamer-rtp-1.0 gstreamer-sdp-1.0 gstreamer-net-1.0 \
          gstreamer-webrtc-1.0 gstreamer-pbutils-1.0 glib-2.0 gobject-2.0; do
  v=$(pkg-config --modversion "$pc" 2>/dev/null) || fail "pc_missing_$pc"
  printf '  %-24s %s\n' "$pc" "$v"
done

# 4. current stable Rust (Debian's 1.63 is too old)
step rustup
[ -x "$HOME/.cargo/bin/rustc" ] || \
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --profile minimal
export PATH="$HOME/.cargo/bin:$PATH"
rustc --version || fail rust_failed

# 5. gst-plugins-rs matched to GStreamer 1.22 (0.11 branch)
step clone
cd "$HOME"
[ -d gst-plugins-rs ] || git clone --depth 1 --branch 0.11 \
  https://gitlab.freedesktop.org/gstreamer/gst-plugins-rs.git || fail clone_failed
cd gst-plugins-rs
echo "  at: $(git describe --tags --always 2>/dev/null) ($(git rev-parse --abbrev-ref HEAD))"

# 6. build the two plugin cdylibs (webrtcsink + rtpgccbwe)
step "cargo build (long)"
export CARGO_BUILD_JOBS=1 CARGO_NET_GIT_FETCH_WITH_CLI=true
cargo build --release -p gst-plugin-webrtc -p gst-plugin-rtp || fail "cargo_build_failed"

# 7. install the plugins + verify
step install+verify
sudo cp -v target/release/libgstrswebrtc.so target/release/libgstrsrtp.so "$PLUGDIR/" || fail copy_failed
sudo ldconfig
if gst-inspect-1.0 webrtcsink >/dev/null 2>&1 && gst-inspect-1.0 rtpgccbwe >/dev/null 2>&1; then
  echo "WEBRTCSINK_OK"
  gst-inspect-1.0 webrtcsink 2>/dev/null | grep -iE 'Long-name|congestion-control|do-fec|do-retransmission' | head -5
  echo done_ok > "$STATE"
  echo "=== BUILD DONE $(date) ==="
else
  gst-inspect-1.0 webrtcsink 2>&1 | head -4
  fail verify_failed
fi
