# Redmi Buds Control

A native macOS menu-bar app that lets you control **Redmi Buds 6 / 6 Pro** (and
other Xiaomi TWS earbuds speaking the "MMA" protocol) directly from your Mac —
battery, ANC, transparency and EQ — without the phone app.

![status](https://img.shields.io/badge/status-working%20on%20Redmi%20Buds%206%20Pro-brightgreen)
![platform](https://img.shields.io/badge/platform-macOS%2014%2B%20(Apple%20Silicon)-lightgrey)
![license](https://img.shields.io/badge/use-personal%20interop-orange)

> Independent project. Not affiliated with or endorsed by Xiaomi / Redmi.
> The Xiaomi authentication library is **not** included — you extract it from the
> official app you already use. See [Legal](#legal).

---

## Features

| | |
|---|---|
| 🔋 **Battery** | Live L / R / case percentages (case shows `—` when the buds are in use). |
| 🎧 **Noise control** | Off / ANC / Transparency — changes pushed to the earbuds and reflected back in real time. |
| 🎚️ **Equalizer** | Original, Vocal, Bass, Treble, Volume presets. |
| 📍 **Menu-bar app** | Lives in the menu bar (`LSUIElement`, no Dock icon). |
| 🔄 **Auto-connect** | Picks the MMA channel automatically (walks past HFP/A2DP services). |
| 🚀 **Launch at Login** | Native toggle via `SMAppService`. |
| 📜 **Packet log** | Every MMA frame is displayed and saved to `~/Documents/RedmiBudsControl/captures/`. |

---

## How it works

These earbuds do **not** use BLE GATT. They use classic Bluetooth **RFCOMM/SPP**
with Xiaomi's proprietary **"MMA"** protocol (`FE DC BA … EF` frames). The app:

1. **IOBluetooth** — SDP-scans the paired buds, finds the MMA service
   (channel 24 on Buds 6 Pro), and opens an RFCOMM channel.
2. **Authenticates** — runs the `SEND_AUTH` / `NOTIFY_AUTH` handshake. The auth
   transform is a custom SPN cipher inside Xiaomi's closed `libxm_bluetooth.so`;
   we compute it with a bundled **Unicorn** ARM emulator (`auth_helper`). The
   emulator is **bit-exact** — validated against a real device
   (`encrypt(00…00) == bca5905bc849392e7bf9fdcdc570ef77`).
3. **Speaks MMA** — `GET/SET_DEVICE_CONFIG` for ANC (`0x000B`) and EQ (`0x0007`),
   `GET_DEVICE_INFO` for battery.

Full protocol reference: [`docs/PROTOCOL.md`](docs/PROTOCOL.md) and
[`docs/AUTH_CIPHER.md`](docs/AUTH_CIPHER.md).

---

## Requirements

- macOS 14+ on **Apple Silicon** (the auth emulator runs arm64 code).
- Xcode Command Line Tools (`xcode-select --install`).
- [libunicorn](https://www.unicorn-engine.org/) — `brew install unicorn`.
- Xiaomi `libxm_bluetooth.so` — extracted from the official app (one-time, see below).
