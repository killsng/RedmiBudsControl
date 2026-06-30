# Redmi / Xiaomi Buds — MMA protocol reference

Reverse-engineered from the open-source Android app
[`web1n/android_packages_apps_XiaomiTWS`](https://github.com/web1n/android_packages_apps_XiaomiTWS)
(verified compatible with **REDMI Buds 6**, same family as Buds 6 Pro) and
[`CesurPolat/MiBudsClient`](https://github.com/CesurPolat/MiBudsClient) (Redmi
Buds 6 Play). Credit to those authors.

## TL;DR for the macOS port

- Transport = **classic Bluetooth SPP (RFCOMM)**, NOT BLE GATT. The macOS app
  must use **`IOBluetooth`**, not `CoreBluetooth`.
- Packet framing = `FE DC BA … EF` ("MMA" / Mi-Mobile-Accessory).
- Commands for battery / ANC / EQ are fully known (below).
- One open item: a **challenge–response auth handshake** whose crypto
  (`com.xiaomi.aivsbluetoothsdk.BluetoothAuth`) is in a closed binary. See
  "Auth" below.

## Transport / connection

Open an **insecure RFCOMM socket** to one of these service UUIDs (try in order):

| UUID | name |
|------|------|
| `0000FD2D-0000-1000-8000-00805f9b34fb` | Xiaomi Fast Connect |
| `00001101-0000-1000-8000-008584d01810` | XiaoAI |

On macOS: `IOBluetoothDevice` → SDP query → `IOBluetoothRFCOMMChannel` open.

## Packet framing (on the RFCOMM stream)

```
FE DC BA                       header (3 bytes)
T0                             type|flags : bit7=Request(1)/Response(0), bit6=needReply
OP                             opcode (1 byte)
LL HH                          length (big-endian)
[ SN ]                         Request: opCodeSN (1 byte)
[ ST SN ]                      Response: status(1), opCodeSN(1)
DATA...                        payload
EF                             footer (1 byte)
```

- `length` (Request) = `data.count + 1`  (counts opCodeSN)
- `length` (Response) = `data.count + 2` (counts status + opCodeSN)
- `needReply` flag (0x40) set on requests that expect a response.

## Opcodes

| Opcode | Meaning |
|--------|---------|
| `0x02` | GET_DEVICE_INFO |
| `0x08` | SET_DEVICE_INFO |
| `0xF2` | SET_DEVICE_CONFIG |
| `0xF3` | GET_DEVICE_CONFIG |
| `0x0E` | NOTIFY_DEVICE_INFO (bud → phone) |
| `0xF4` | NOTIFY_DEVICE_CONFIG (bud → phone) |
| `0x50` | SEND_AUTH |
| `0x51` | NOTIFY_AUTH |

GET_DEVICE_INFO data = bitmask of desired fields; `0x07` returns battery
(TLV type `0x00` = battery: `[L, R, case]` percent).

## Config IDs (2-byte, used with SET/GET_DEVICE_CONFIG 0xF2/0xF3)

| ID | Feature |
|----|---------|
| `0x0007` | Equalizer mode |
| `0x000A` | Noise-cancellation list (which modes the buds support) |
| `0x000B` | Noise-cancellation mode (current) |
| `0x0002` | Button / gesture mode |
| `0x0004` | Multi-point connect |
| `0x0009` | Find earbuds |
| `0x000C` | In-ear detection |
| `0x0027` | Serial number |

### ANC mode values (config 0x000B)

| Value | Mode |
|-------|------|
| `0x00` | Off |
| `0x01` | Noise cancellation (ANC) |
| `0x02` | Transparency |

(Adaptive ANC, if present on the 6 Pro, is negotiated via the
`0x000A` list / a separate sub-value — to confirm on-device.)

### Equalizer presets (config 0x0007)

| Value | Preset |
|-------|--------|
| `0x00` | Default / Original |
| `0x01` | Vocal enhance |
| `0x05` | Bass boost |
| `0x06` | Treble boost |
| `0x07` | Volume boost |
| `0x14` | Harman |
| `0x15` | Harman Master |

## Connection / auth sequence

1. Buds connected to host (paired, HFP/A2DP up). Open RFCOMM SPP socket to a
   Xiaomi UUID above.
2. Send `GET_DEVICE_INFO` (0x02, mask `0x07`) for battery.
   - If a valid response comes back → **already authenticated**, done.
3. If it fails / no reply → auth handshake:
   - Phone → bud: `SEND_AUTH` (0x50), data `[0x01, <16 random bytes>]`.
   - Bud → phone: `SEND_AUTH` response with `[0x01, <16 bytes>]`; must equal
     `getEncryptedAuthCheckData(random)`.
   - Bud → phone: `SEND_AUTH` request with 17 bytes (`0x01` + 16 challenge).
     Phone answers with `getEncryptedAuthCheckData(challenge)` (16 bytes).
   - Phone → bud: `NOTIFY_AUTH` (0x51) `[0x01, 0x00]`; bud replies `[0x01]`.
4. Now `Connected`; config reads/writes (ANC, EQ) are allowed.

## Auth (the one closed piece)

`com.xiaomi.aivsbluetoothsdk.impl.BluetoothAuth`:
- `getRandomAuthCheckData()` → 16 random bytes
- `getEncryptedAuthCheckData(16 bytes)` → 16 bytes

16→16 strongly implies **AES-128 (ECB/CBC) with an embedded key**, but the
implementation ships only as a prebuilt binary (see `fetch_libs.py` in the
xiaomi-sdk repo). To finish the macOS port we either:

- **Reverse the key** out of the SDK `.so` / dex (Ghidra/JADX), or
- **Capture one auth exchange** (any Android running the official app or
  web1n's app against the buds) and derive the key from known plaintext, or
- Try the device **without auth** first — some firmware serves battery/config
  reads before auth; writes may or may not require it. Test empirically.

## References (file → purpose in web1n's repo)

- `mma/MMADevice.kt` — RFCOMM socket + `FE DC BA…EF` serialization
- `mma/MMAManager.kt` — request/response + auth state machine
- `mma/AuthRequest.kt` — auth handshake (calls the closed SDK)
- `mma/configs/*` — ANC/EQ/gesture config encoders
- `headset/ATCommand.kt` — the `FF 01 02 01 … FF` AT frame (alternate path)
- `EarbudsConstants.kt` — all UUIDs / opcodes / config IDs / values
