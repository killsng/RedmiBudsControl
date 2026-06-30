# Reversing the auth crypto

The only closed piece of the Xiaomi TWS protocol is the auth challenge-response:
`encrypt(16 bytes) -> 16 bytes`, implemented in the native library
**`libxm_bluetooth.so`** shipped inside the official **"Xiaomi Earbuds"** app
(package `com.mi.earphone`). 16→16 strongly implies **AES-128**, so the macOS
app already wires AES-128-ECB (`Sources/.../Protocol/AuthHandler.swift`) — we
just need the 16-byte key.

## 1. Get the APK (browser — the CDN blocks scripted download)

Download the official **Xiaomi Earbuds** APK/XAPK, e.g. from:
- https://apkpure.com/xiaomi-earbuds/com.mi.earphone  (pick "Download APK")
- or https://www.apkmirror.com/apk/beijing-xiaomi-mobile-software-co-ltd/xiaomi-earbuds/

Save it anywhere, e.g. `~/Downloads/xiaomi_earbuds.apk` (or `.xapk`).

## 2. Run the reverse script

```bash
cd ~/Documents/RedmiBudsControl
./tools/reverse_auth.sh ~/Downloads/xiaomi_earbuds.apk
```

It extracts `lib/arm64-v8a/libxm_bluetooth.so` and prints:
- the JNI symbol for `getEncryptedAuthCheckData` (confirms the native entry),
- whether AES is in use — Rijndael **S-box** / **Te0** table offsets, and the
  count of ARM `aese`/`aesd`/`aesmc`/`aesimc` instructions,
- disassembly context around the AES routine so the key (the bytes loaded by the
  `ldr`/`adr` just before the `aese` loop) can be read off.

## 3. Interpret

- **`aese` present** → hardware AES. The key sits in `.rodata`, referenced by an
  `adrp`/`add` or `ldr` instruction right before the first `aese`. That literal
  pool value is the 16-byte key.
- **S-box present but no `aese`** → software AES (T-table impl.); the key is the
  16 bytes XORed/combined at the start of `expand_key` — follow the S-box
  reference back to the key schedule.
- **Neither** → not AES; paste the routine's disassembly and we re-analyze.

## 4. Drop the key in

```swift
// Sources/RedmiBudsControl/Protocol/AuthHandler.swift
static let authKey: [UInt8] = [0x__, 0x__, ... ]   // 16 bytes
```

Rebuild (`./build.sh`) and auth works end-to-end — ANC/EQ writes unlock.

## Shortcut if you'd rather not RE

If you can briefly run the official app against the buds on *any* Android once,
capture the BLE/HCI traffic (see `docs/PROTOCOL_CAPTURE.md`) — the SEND_AUTH
request/response pairs give you known-plaintext/ciphertext. That doesn't
recover an AES key directly (AES is resistant to that), but it confirms the
cipher block boundaries and lets us validate the key once found.
