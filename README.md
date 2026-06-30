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

---

## Build & run

```bash
git clone https://github.com/killsng/RedmiBudsControl && cd RedmiBudsControl

# 1) One-time: extract the auth lib from the official "Xiaomi Earbuds" APK
#    (package com.mi.earphone — from APKPure / APKMirror).
brew install unicorn
./tools/reverse_auth.sh ~/Downloads/xiaomi_earbuds.apk      # extracts libxm_bluetooth.so
cp tools/re/lib/arm64-v8a/libxm_bluetooth.so resources/

# 2) Optional: regenerate the app icon
swift tools/make_icon.swift && \
  iconutil -c icns resources/RedmiBudsControl.iconset -o resources/AppIcon.icns

# 3) Build the .app
./build.sh
open build/RedmiBudsControl.app
```

**First launch:** pair your buds in *System Settings › Bluetooth*, then click the
menu-bar icon → **Refresh** → select your buds → **Connect**. Grant the Bluetooth
permission prompt. Open **Settings** from the menu to enable *Launch at Login*.

---

## Project layout

```
Sources/RedmiBudsControl/
  App/RedmiBudsApp.swift        @main — MenuBarExtra + Packet Log + Settings scenes
  Bluetooth/
    EarbudsManager.swift        state machine; battery/ANC/EQ ops; auth flow
    RFCOMMTransport.swift       IOBluetooth SDP + RFCOMM channel; channel walking
  Protocol/
    MMAProtocol.swift           FE DC BA…EF framing, stream parser, opcodes/config IDs
    AuthHandler.swift           auth handshake (invokes the bundled auth_helper)
  Models/                       ANCMode / SoundMode / BatteryState (wire bytes)
  Logging/                      CaptureLogger + LogEntry (in-app + on-disk)
  Views/                        MenuContent, DevicePicker, DeviceControls, SettingsView, LogView
resources/
  auth_helper.c                 standalone Unicorn emulator of the Xiaomi cipher
  libxm_bluetooth.so            Xiaomi auth lib (NOT in repo — extract from APK)
  AppIcon.icns
tools/
  reverse_auth.sh               extracts libxm_bluetooth.so from the APK
  make_icon.swift               renders AppIcon.icns
docs/                           PROTOCOL.md, AUTH_CIPHER.md, AUTH_REVERSE.md
```

---

## Troubleshooting

- **"My buds don't appear"** — pair them in *System Settings › Bluetooth* first
  and connect them as an audio device, then tap **Refresh**.
- **"Controls are locked / no battery"** — open the **Packet log**. If you see
  `Auth complete`, the channel is good; if you see repeated channel probes with
  no `[RX]`, the auth lib may not match your firmware version.
- **`auth_helper build failed`** — run `brew install unicorn`.
- **"Connection failed"** — make sure the buds aren't actively connected to
  another phone at the same time.

---

## Limitations

- **No Control Center / System Settings integration.** Apple reserves the
  device-picker and accessory panels in Control Center and System Settings for
  MFi/Apple accessories (e.g. AirPods). Third-party apps can only integrate via
  the menu bar (and optionally a Widget).
- **Apple Silicon only.** An Intel build would need the x86 variant of libunicorn.
- **Unsigned local build.** It runs because it was built on your machine; for
  distribution you'd need to sign/notarize.

---

## Legal

This project is for **personal interoperability** with hardware you own. It is
not affiliated with, authorized by, or endorsed by Xiaomi or Redmi.

- `libxm_bluetooth.so` is Xiaomi's proprietary code and is **not** redistributed
  here. The build expects you to extract it from the official app you already
  use, for use with your own device.
- The auth transform is reproduced functionally via software emulation; no
  Xiaomi source code is included.

Use responsibly and in accordance with applicable law and the earbuds' warranty.

---

## Credits

Protocol reverse-engineered from the open-source Android app
[`web1n/android_packages_apps_XiaomiTWS`](https://github.com/web1n/android_packages_apps_XiaomiTWS)
(verified on Redmi Buds 6) and
[`CesurPolat/MiBudsClient`](https://github.com/CesurPolat/MiBudsClient).
Authentication computed with the [Unicorn Engine](https://www.unicorn-engine.org/).
