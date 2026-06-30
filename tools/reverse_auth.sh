#!/usr/bin/env bash
# Reverse the Xiaomi TWS auth crypto.
#
# Input: path to the official "Xiaomi Earbuds" APK / XAPK (com.mi.earphone),
#        OR the extracted libxm_bluetooth.so.
#
# It extracts the arm64-v8a libxm_bluetooth.so and reports:
#   - the JNI symbol for getEncryptedAuthCheckData (confirms the native entry)
#   - whether AES is used (Rijndael S-box / ARM `aese` instructions)
#   - disassembly around the crypto routine (so the key can be read off)
#
# Get the APK from APKPure/APKMirror in a browser:
#   https://apkpure.com/xiaomi-earbuds/com.mi.earphone
set -euo pipefail

IN="${1:-}"
[ -n "$IN" ] || { echo "usage: $0 <xiaomi_earbuds.apk|xapk|libxm_bluetooth.so>"; exit 1; }
[ -f "$IN" ] || { echo "not found: $IN"; exit 1; }

RE="$(mktemp -d)"
trap 'rm -rf "$RE"' EXIT
SO="$RE/libxm_bluetooth.so"

extract_so () {
  local src="$1"
  case "$(file -b "$src")" in
    *ELF*) cp "$src" "$SO"; return;;
  esac
  # APK or XAPK (zip). Find libxm_bluetooth.so under lib/arm64-v8a/.
  unzip -oq "$src" -d "$RE/unzip" 2>/dev/null || true
  local found
  found="$(find "$RE/unzip" -path '*arm64-v8a/libxm_bluetooth.so' | head -1 || true)"
  if [ -z "$found" ]; then
    # XAPK: it bundles APKs; recurse into them.
    for apk in "$RE/unzip"/*.apk; do
      [ -f "$apk" ] || continue
      unzip -oq "$apk" -d "$RE/apkx" 2>/dev/null || true
      found="$(find "$RE/apkx" -path '*arm64-v8a/libxm_bluetooth.so' | head -1 || true)"
      [ -n "$found" ] && break
    done
  fi
  [ -n "$found" ] || { echo "libxm_bluetooth.so not found in $src"; exit 1; }
  cp "$found" "$SO"
}

extract_so "$IN"
echo "==> libxm_bluetooth.so: $(file -b "$SO")  ($(wc -c < "$SO") bytes)"

echo
echo "==> JNI / relevant strings"
strings -n 5 "$SO" | grep -iE 'BluetoothAuth|getEncryptedAuth|getRandomAuth|aivs|xm_bluetooth|authcheck|auth_check' || echo "(none)"

echo
echo "==> AES indicators"
echo "-- crypto mnemonic count (aese/aesd/aesmc/aesimc):"
objdump -d "$SO" 2>/dev/null | grep -cE '\b(aese|aesd|aesmc|aesimc)\b' || true
echo "-- Rijndael S-box / T-table scan:"
python3 - "$SO" <<'PY'
import sys
data = open(sys.argv[1],'rb').read()
sbox = bytes.fromhex('637c777bf26b6fc53001672bfed7ab76')
tbox = bytes.fromhex('a56363c5847c7cf8997777ee8d7b7bf6')  # AES Te0 first 16 bytes
for name,pat in (('S-box',sbox),('Te0 T-table',tbox)):
    i = data.find(pat)
    print(f'   {name:12}: {"NOT FOUND" if i<0 else "found at file offset 0x%x"%i}')
# Any obvious 16/32-byte key candidates near the strings are reported by the
# analyst from the disassembly below — this just confirms the cipher family.
PY

echo
echo "==> Symbols exported (Java_* / auth)"
objdump -T "$SO" 2>/dev/null | grep -iE 'auth|bluetooth|encrypt' | head -30 || echo "(no dynamic symbols / stripped)"

echo
echo "==> AES routine disassembly (first matches + context)"
objdump -d "$SO" 2>/dev/null | grep -E '\b(aese|aesd|aesmc|aesimc)\b' | head -5 || true
echo "    (look just above the aese/aesd loop for the `adr`/`ldr` that loads the key from .rodata)"

echo
echo "==> DONE. Drop the recovered key (hex) into Sources/.../AuthHandler.swift"
echo "    static let authKey: [UInt8] = [0x.., ...]   (16 bytes for AES-128)"
