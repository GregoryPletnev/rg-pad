#!/bin/bash
# Build rgpad (Free Pascal) for arm64 inside a Trixie arm64 chroot (qemu-user),
# so the binary links against the same libc/RTL as the device rootfs.
set -euo pipefail
W=${W:-$HOME/rg35xxh-work}
SRC=$(cd "$(dirname "$0")" && pwd)
CH=$W/fpc-arm64

if [ ! -x "$CH/usr/bin/fpc" ]; then
  sudo rm -rf "$CH"
  sudo mmdebstrap --architectures=arm64 --variant=minbase \
    --include=fp-compiler,fp-units-rtl trixie "$CH" \
    "deb http://deb.debian.org/debian trixie main"
fi

sudo mkdir -p "$CH/src"
sudo cp "$SRC/rgpad.pas" "$CH/src/"
sudo chroot "$CH" sh -c 'cd /src && rm -f rgpad rgpad.o && fpc -O2 -Xs -XX -CX -vew rgpad.pas'
mkdir -p "$W/out"
cp "$CH/src/rgpad" "$W/out/rgpad"
file "$W/out/rgpad"
ls -la "$W/out/rgpad"
echo DONE_RGPAD
