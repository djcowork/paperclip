#!/usr/bin/env bash
# Plan B — bootstrap a fresh paperclip + djcowork2.0 development environment
# inside WSL2 (Ubuntu 24.04+).
#
# This is the operational realisation of
# doc/plans/2026-05-14-wsl2-cross-compile-migration.md
#
# Run this from inside WSL2, after:
#   (Windows) wsl --install -d Ubuntu-24.04
#   (Windows) wsl --update
#   (WSL2)   first user setup
#
# Then:
#   curl -fsSL https://raw.githubusercontent.com/<owner>/paperclip/master/scripts/setup-wsl2-paperclip.sh -o /tmp/setup.sh
#   bash /tmp/setup.sh
# or, if you already have the paperclip repo at /mnt/d/paperclip:
#   bash /mnt/d/paperclip/scripts/setup-wsl2-paperclip.sh
#
# What it does:
#   1. apt update + base build deps (git, curl, pkg-config, build-essential, libssl, etc.)
#   2. install rustup + pin 1.88.0 + add x86_64-pc-windows-gnullvm target
#   3. download LLVM-MinGW 20260224-ucrt to ~/llvm-mingw and PATH it
#   4. install Node 20 + pnpm
#   5. install sccache + cargo-deny
#   6. ensure repos exist under $HOME/work (clone if missing — accepts paths
#      from /mnt/d as initial fetch source to avoid re-download over network)
#   7. write a ~/.cargo/config.toml override for the gnullvm linker
#   8. run a smoke cross-compile of djcowork (cargo check --target gnullvm)
#   9. print next steps for paperclip + plugin install

set -euo pipefail

PAPERCLIP_REMOTE="${PAPERCLIP_REMOTE:-https://github.com/paperclipai/paperclip.git}"
DJCOWORK_REMOTE="${DJCOWORK_REMOTE:-https://github.com/djcowork/djcowork2.0.git}"
WIN_PAPERCLIP="/mnt/d/paperclip"
WIN_DJCOWORK="/mnt/d/code/djcowork2.0"
WORK_DIR="$HOME/work"
LLVM_MINGW_VERSION="20260224"
LLVM_MINGW_URL="https://github.com/mstorsjo/llvm-mingw/releases/download/${LLVM_MINGW_VERSION}/llvm-mingw-${LLVM_MINGW_VERSION}-ucrt-ubuntu-22.04-x86_64.tar.xz"
RUST_VERSION="1.88.0"

log()  { printf "\033[36m==> %s\033[0m\n" "$*"; }
warn() { printf "\033[33m!! %s\033[0m\n" "$*"; }
fail() { printf "\033[31mERR %s\033[0m\n" "$*" >&2; exit 1; }

# ----------------------------------------------------------------------------
# 0. sanity
# ----------------------------------------------------------------------------
if ! grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null; then
  fail "This script is intended to run inside WSL2 (not native Linux, not Windows). /proc/sys/kernel/osrelease must contain 'microsoft'."
fi
if [ "$EUID" -eq 0 ]; then
  fail "Run as your normal WSL user, not as root. Sudo will be used where needed."
fi

# ----------------------------------------------------------------------------
# 1. base packages
# ----------------------------------------------------------------------------
log "[1/9] apt: base build deps"
sudo apt-get update -qq
sudo apt-get install -y --no-install-recommends \
  ca-certificates curl gnupg git build-essential pkg-config \
  libssl-dev libsqlite3-dev libudev-dev libasound2-dev \
  cmake ninja-build clang llvm xz-utils \
  python3 python3-pip jq unzip

# ----------------------------------------------------------------------------
# 2. rustup + 1.88.0 + gnullvm target
# ----------------------------------------------------------------------------
log "[2/9] rustup + Rust ${RUST_VERSION}"
if ! command -v rustup >/dev/null 2>&1; then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path --default-toolchain none
fi
# shellcheck source=/dev/null
source "$HOME/.cargo/env"
rustup install "${RUST_VERSION}" --profile minimal
rustup default "${RUST_VERSION}"
rustup component add clippy rustfmt
rustup target add x86_64-pc-windows-gnullvm

# ----------------------------------------------------------------------------
# 3. LLVM-MinGW (cross-toolchain for windows-gnullvm)
# ----------------------------------------------------------------------------
log "[3/9] LLVM-MinGW ${LLVM_MINGW_VERSION}"
LLVM_DIR="$HOME/llvm-mingw"
if [ ! -d "$LLVM_DIR" ]; then
  curl -sSL -o /tmp/llvm-mingw.tar.xz "$LLVM_MINGW_URL"
  tar -xJf /tmp/llvm-mingw.tar.xz -C "$HOME"
  mv "$HOME/llvm-mingw-${LLVM_MINGW_VERSION}-ucrt-ubuntu-22.04-x86_64" "$LLVM_DIR"
  rm /tmp/llvm-mingw.tar.xz
fi
LLVM_BIN="$LLVM_DIR/bin"
"$LLVM_BIN/x86_64-w64-mingw32-clang" --version >/dev/null

if ! grep -q "llvm-mingw/bin" "$HOME/.bashrc"; then
  echo "export PATH=\"$LLVM_BIN:\$PATH\"" >> "$HOME/.bashrc"
fi
export PATH="$LLVM_BIN:$PATH"

# ----------------------------------------------------------------------------
# 4. Node 20 + pnpm (for paperclip)
# ----------------------------------------------------------------------------
log "[4/9] Node 20 + pnpm"
if ! command -v node >/dev/null || [ "$(node -p 'process.versions.node.split(".")[0]')" != "20" ]; then
  curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
  sudo apt-get install -y nodejs
fi
if ! command -v pnpm >/dev/null; then
  sudo npm install -g pnpm@latest-9
fi

# ----------------------------------------------------------------------------
# 5. cargo helper binaries
# ----------------------------------------------------------------------------
log "[5/9] sccache + cargo-deny"
command -v sccache >/dev/null || cargo install sccache --locked
command -v cargo-deny >/dev/null || cargo install cargo-deny --locked

# ----------------------------------------------------------------------------
# 6. repos on ext4
# ----------------------------------------------------------------------------
log "[6/9] clone paperclip + djcowork2.0 to ${WORK_DIR}"
mkdir -p "$WORK_DIR"

clone_repo() {
  local name="$1" win_mirror="$2" remote="$3" dest="$WORK_DIR/$1"
  if [ -d "$dest/.git" ]; then
    echo "    $name already present at $dest — fetching"
    git -C "$dest" fetch --all --prune
    return
  fi
  if [ -d "$win_mirror/.git" ]; then
    echo "    $name: cloning from local Windows mirror $win_mirror (fast)"
    git clone --no-hardlinks "$win_mirror" "$dest"
    git -C "$dest" remote set-url origin "$remote"
    git -C "$dest" fetch --all --prune
  else
    echo "    $name: cloning from $remote"
    git clone "$remote" "$dest"
  fi
}

clone_repo paperclip      "$WIN_PAPERCLIP"     "$PAPERCLIP_REMOTE"
clone_repo djcowork2.0    "$WIN_DJCOWORK"      "$DJCOWORK_REMOTE"

# ----------------------------------------------------------------------------
# 7. ~/.cargo/config.toml override for gnullvm linker
# ----------------------------------------------------------------------------
log "[7/9] ~/.cargo/config.toml gnullvm linker override"
mkdir -p "$HOME/.cargo"
CARGO_OVERRIDE="$HOME/.cargo/config.toml"
if [ ! -f "$CARGO_OVERRIDE" ] || ! grep -q "x86_64-pc-windows-gnullvm" "$CARGO_OVERRIDE"; then
  cat >> "$CARGO_OVERRIDE" <<EOF

# paperclip/wsl2: cross-compile djcowork to Windows from Linux
[target.x86_64-pc-windows-gnullvm]
linker = "$LLVM_BIN/x86_64-w64-mingw32-clang"
rustflags = ["-C", "link-arg=-lwinpthread"]

[build]
rustc-wrapper = "sccache"
EOF
  echo "    wrote gnullvm linker into $CARGO_OVERRIDE"
else
  echo "    $CARGO_OVERRIDE already has gnullvm config; leaving untouched"
fi

# ----------------------------------------------------------------------------
# 8. cross-compile smoke
# ----------------------------------------------------------------------------
log "[8/9] cross-compile smoke (cargo check --target x86_64-pc-windows-gnullvm)"
DJCOWORK="$WORK_DIR/djcowork2.0"
pushd "$DJCOWORK" >/dev/null
if [ ! -f rust-toolchain.toml ]; then
  warn "djcowork2.0 has no rust-toolchain.toml; proceeding with active toolchain"
fi
# cargo check only — full build would take ~10-20 min the first time.
if cargo check --target x86_64-pc-windows-gnullvm -p djcowork --quiet 2>&1 | tail -20; then
  echo "    cross-compile smoke OK"
else
  warn "cross-compile smoke failed — review the error above. WSL2 setup is still usable; only the gnullvm target is broken."
fi
popd >/dev/null

# ----------------------------------------------------------------------------
# 9. install paperclip deps + print next steps
# ----------------------------------------------------------------------------
log "[9/9] paperclip pnpm install + summary"
pushd "$WORK_DIR/paperclip" >/dev/null
pnpm install --frozen-lockfile || pnpm install
popd >/dev/null

cat <<EOF

============================================================
SETUP DONE.
============================================================

You now have, all on the WSL2 ext4 filesystem:

  $WORK_DIR/paperclip/        (Node + TS paperclip server)
  $WORK_DIR/djcowork2.0/      (Rust + gpui desktop)
  $LLVM_DIR/                  (LLVM-MinGW cross toolchain)
  ~/.cargo/config.toml        (gnullvm linker + sccache wrapper)

Daily commands:

  # native Linux dev loop (fast)
  cd ~/work/djcowork2.0
  cargo +${RUST_VERSION} check --workspace

  # build a Windows .exe for the host to actually run
  cargo +${RUST_VERSION} build --target x86_64-pc-windows-gnullvm -p djcowork --release
  cp target/x86_64-pc-windows-gnullvm/release/djcowork.exe /mnt/d/dist/

  # start paperclip
  cd ~/work/paperclip
  pnpm paperclipai run --instance default

Then, in another shell, copy your existing GitHub App creds into the new
instance (the three secrets the agent needs):

  scp -r /mnt/d/paperclip/tmp/github-app-credentials ~/paperclip-app-creds
  # …then create the three paperclip secrets pointing at this directory.

When ready, re-run the smoke heartbeat:

  bash $WORK_DIR/paperclip/scripts/smoke-heartbeat.sh

If 'cargo check --target gnullvm' failed: see
  doc/plans/2026-05-14-wsl2-cross-compile-migration.md
for the manual fallback steps.

EOF
