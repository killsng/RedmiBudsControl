#!/usr/bin/env bash
# Extracts BLE ATT writes + notifications from a btsnoop_hci.log using tshark
# (install Wireshark:  brew install --cask wireshark  — provides tshark).
#
# Usage:  ./tools/extract_commands.sh captures/btsnoop_hci.log
set -euo pipefail

LOG="${1:-captures/btsnoop_hci.log}"
[ -f "$LOG" ] || { echo "log not found: $LOG"; exit 1; }

command -v tshark >/dev/null || {
  echo "tshark not found. Install Wireshark:  brew install --cask wireshark"
  exit 1
}

OUTDIR="captures/extracted"
mkdir -p "$OUTDIR"
BASE="$OUTDIR/$(basename "${LOG%.log}")"

echo "==> ATT writes (commands the app sent) -> ${BASE}_writes.tsv"
# 0x12 = Write Request, 0x52 = Write Command
tshark -r "$LOG" \
  -Y "btatt.opcode == 0x12 || btatt.opcode == 0x52" \
  -T fields -E header=y -E separator=$'\t' \
  -e frame.number -e frame.time_relative \
  -e bthci.src.bd_addr -e btatt.handle -e btatt.value \
  | tee "${BASE}_writes.tsv"

echo
echo "==> ATT notifications (bud -> app) -> ${BASE}_notify.tsv"
# Handle Value Notification (0x1B) and Indication (0x1D)
tshark -r "$LOG" \
  -Y "btatt.opcode == 0x1b || btatt.opcode == 0x1d" \
  -T fields -E header=y -E separator=$'\t' \
  -e frame.number -e frame.time_relative \
  -e btatt.handle -e btatt.value \
  | tee "${BASE}_notify.tsv"

echo
echo "==> Services / characteristic handles -> ${BASE}_gatt.txt"
tshark -r "$LOG" \
  -Y "btatt.opcode == 0x02 || btatt.opcode == 0x03 || btatt.opcode == 0x09 || btatt.opcode == 0x11" \
  -V 2>/dev/null | grep -iE "uuid|handle|attribute|read by|find by|properties" \
  | tee "${BASE}_gatt.txt" >/dev/null || true

echo
echo "Done. Inspect the TSVs — each row is one command. Cross-reference with"
echo "the # ~Time notes from docs/PROTOCOL_CAPTURE.md section B."
