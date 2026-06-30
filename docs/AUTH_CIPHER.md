# Auth cipher — reverse-engineering notes (libxm_bluetooth.so)

Status: **structure fully understood; cipher is custom (not AES / no standard
match). A working Unicorn oracle exists (`tools/re/emulate.py`) that reproduces
the transform bit-exactly, so any Swift reimplementation can be validated
without hardware.**

## Where it lives

- `libxm_bluetooth.so` (14 KB, arm64-v8a) from the official **Xiaomi Earbuds**
  APK (`com.mi.earphone`). Extracted to `tools/re/libxm_bluetooth.so`.
- JNI methods registered via `RegisterNatives` in `register_xm_bluetooth`.
  Target: `getEncryptedAuthCheckData([B)[B` → wrapper `function_xiaomi` @0x1770.
- Constants in `.data`:
  - `0x130a8` → ctx/IV seed = `11 22 33 33 22 11` (tiled to 16-byte IV)
  - `0x13098` → key A   = `06 77 5f 87 91 8d d4 23 00 5d f1 d8 cf 0c 14 2b`
- Lookup table in `.rodata` @`0x1ed4` (~783 bytes), used by both key expansion
  and the block primitive. Not the standard AES S-box.

## Functions

| addr | role |
|------|------|
| `0x1770` | `function_xiaomi(ctx, in, key, out)` — entry; calls 0xac0 then 0xed8 |
| `0xed8` | `function_E21` — builds IV (tiled ctx) + plaintext (input[0..14] + input[15]^0x06), drives the 3 passes |
| `0x1068` | key expansion: 16-byte key → 272-byte schedule (17 round keys). XOR-checksum of key bytes + per-byte 3-bit rotate (`ubfx #5,#3` / `bfi #3,#8`) + rodata table |
| `0x12f8` | block primitive: `(block[16], schedule[272], mode)` — custom SPN round function; mode∈{0,1} are two different forward transforms (NOT enc/dec inverses) |

## Construction (per `encrypt(input16)`)

```
1. B = block( expand(A), zeros,  mode=0 )      # derive B from static key A
2. C = block( expand(B), <intermediate>, mode=1 )
3. out = block( expand(input[0..14] + input[15]^6), IV, mode=1 )
```
i.e. the challenge is used as a *key* to transform the fixed IV — a
Davies-Meyer / Merkle-Damgård-style compression, not a plain block encrypt.

## Oracle (ground truth) — `tools/re/emulate.py`

Unicorn emulates `function_xiaomi` with the .so mapped + GOT relocated +
malloc/free/memset hooked. Verified input→output pairs:

| input (16 B) | output (16 B) |
|--------------|---------------|
| `00000000000000000000000000000000` | `bca5905bc849392e7bf9fdcdc570ef77` |
| `ffffffffffffffffffffffffffffffff` | `f26249f9a7bc42731feb945fd9e8d06f` |
| `06775f87918dd423005df1d8cf0c142b` | `4ace3f23e65864590650cd5cf90ea1d2` |
| `11223333221111223333221111223333` | `f7d22dd3e8d3a8f446aa7e7624e835aa` |
| `01000000000000000000000000000000` | `1dd4f8c5e92b166d4139986b663021e4` |

Run: `python3 tools/re/emulate.py`

## To finish auth (port to Swift)

Translate `0x1068` (key expand) and `0x12f8` (block primitive) to Swift using
the disassembly in `tools/re/disasm.txt`, then validate against the oracle
pairs above by feeding the same inputs through the Swift impl. When all five
match, set the result in `AuthHandler.encryptAuthCheckData`.

**But first** — confirm auth is actually required by running the app on real
buds (the web1n flow tries battery *without* auth first; some firmware serves
ANC/EQ without the handshake). If it does, the port is the remaining task.
