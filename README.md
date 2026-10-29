# rgpad

Turn the RG35XXH gamepad into a keyboard and a mouse.

`rgpad` is a small daemon for Linux consoles (no X11, no Wayland needed). It
reads the built-in gamepad of the Anbernic RG35XXH through evdev, grabs it,
and creates two virtual devices with uinput:

- a virtual keyboard, driven by the face buttons, the D-pad, and left-stick
  chords,
- a virtual mouse, driven by the right stick and the stick clicks.

You can then type in the Linux console with the gamepad: for example, log in
over SSH or edit config files on the device itself. Pair it with `gpm` for
mouse text selection and pasting.

## How it works

- Plain buttons map to keys or mouse buttons (`[buttons]` in the config).
- Left stick direction + X/A/B/Y types a character. Eight stick directions
  times four face buttons give 32 characters per layer.
- Layers cycle with the `menu` button: `abc` (lowercase), `ABC` (uppercase),
  `123` (digits and punctuation). The red LED shows the current layer:
  off, on, or blinking.
- The right stick presses keys by default: each of the 8 directions holds
  one key while deflected (shipped map: F1–F8) — handy in the console and
  in Doom-like menus. Set `[right_stick] mode = mouse` to get the pointer
  back (pair it with `gpm`).
- Hold `start` while typing to send Ctrl+character.
- Hold `start` + `menu` to switch between the mapping and raw gamepad
  passthrough, so games still see the original device. A launcher can do
  the same with signals: `SIGUSR1` switches to passthrough, `SIGUSR2` back to
  the mapping (`systemctl kill -s USR1 rgpad`). The virtual keyboard and
  mouse stay in place either way.
- Stick resting positions are taken as centers at startup (auto-calibration).

See [docs/rgpad-layout.pdf](docs/rgpad-layout.pdf) for the full printable
cheat sheet (2 pages, A4).

## Requirements

- Anbernic RG35XXH (or another device with `gpio-keys` buttons and an
  `adc-joystick` — the device names are configurable).
- Linux with uinput (`modprobe uinput`).
- `gpm` in the console if you use `[right_stick] mode = mouse`.

## Build

The binary is plain Free Pascal and only uses `BaseUnix`, `SysUtils`,
`Classes`, and `Math`. Build it natively on the device:

```sh
fpc -O2 rgpad.pas
```

`build-rgpad.sh` cross-builds an arm64 binary on a Debian host inside a
`mmdebstrap` chroot with qemu-user, so the result links against the same libc
and RTL as the device rootfs. It needs `mmdebstrap`, `qemu-user-static`, and
sudo.

## Install

```sh
install -m 755 rgpad /usr/local/bin/rgpad
install -m 644 rgpad.conf /etc/rgpad.conf
install -m 644 rgpad.service /etc/systemd/system/rgpad.service
systemctl daemon-reload
systemctl enable --now rgpad
```

Apply config changes with `systemctl restart rgpad`.

## Configuration

All behavior lives in `rgpad.conf`; the shipped file is fully commented.

| Section | What it controls |
| --- | --- |
| `[devices]` | input device names to grab (gamepad, joystick) |
| `[general]` | toggle combo, status LED, auto-calibration |
| `[buttons]` | button → key, mouse button, or `@layer` action |
| `[left_stick]` | chord direction threshold, axis inversion |
| `[mouse]` | right-stick deadzone, speed, rate, accel curve, inversion |
| `[right_stick]` | stick role: `mouse` or `keys` with a per-direction key table |
| `[layer name]` | chord tables: 8 directions + `center`, 4 tokens each |

A chord token is a single character (typed on the US layout) or a key name
such as `SPACE`, `TAB`, `ENTER`. `rgpad` runs against the console keymap:
it injects left Shift itself for characters that need it.

Check your setup with `-v`:

```sh
rgpad -c /etc/rgpad.conf -v
```

## Layout cheat sheet

`make-layout-pdf.py` renders `docs/rgpad-layout.pdf` straight from the
config, so the sheet always matches your mapping:

```sh
pip install reportlab
python3 make-layout-pdf.py rgpad.conf docs/rgpad-layout.pdf
```

The script reads macOS system fonts by default; edit the font paths at the
top of the file on other systems.

## License

MIT — see [LICENSE](LICENSE).
