# Phase 2 — Capturing the Redmi Buds 6 Pro protocol (Android HCI snoop)

The `btsnoop_hci.log` captured while using the official **Xiaomi Earbuds** app
records *everything* on the Bluetooth link: service discovery, reads,
notifications **and the write commands** the app sends for ANC / EQ / etc.
That single file is enough to implement Phase 3.

## A. Enable Bluetooth HCI snoop (one-time)

1. **Developer options**: *Settings › About phone* → tap **Build number** 7×.
2. *Settings › System › Developer options* → find **Bluetooth HCI snoop log** →
   set to **Always on** (some ROMs label it "Enabled").
3. **Toggle Bluetooth OFF then ON** (or reboot the phone) so logging actually
   starts for the buds.
4. Make sure the buds are **paired to the phone** in Bluetooth settings and
   connect via the official **Xiaomi Earbuds** app once, then close the app.

> If the Developer-option toggle is missing on your ROM, enable via adb instead:
> `adb shell setprop persist.bluetooth.btsnooplog true` then **reboot**.

## B. Record the action script (do this in ONE clean pass)

Open the **Xiaomi Earbuds** app, connect to the Redmi Buds 6 Pro, then perform
each action below. **Wait ~3 seconds between steps** and try to do each exactly
once so we can match writes to actions by timestamp. Keep the case lid open /
buds in your ears so they stay awake.

Fill the **time** column as you go (rough wall-clock is fine):

| # | ~Time | Action |
|---|-------|--------|
| 1 |       | App connected, earbuds awake |
| 2 |       | Noise control → **Off** |
| 3 |       | Noise control → **ANC** (default strength) |
| 4 |       | ANC strength → **Low** (if shown) |
| 5 |       | ANC strength → **High** |
| 6 |       | Noise control → **Transparency** |
| 7 |       | Noise control → **Adaptive** (if shown) |
| 8 |       | EQ → **Original / Default** |
| 9 |       | EQ → **Bass** |
| 10|       | EQ → **Treble** |
| 11|       | EQ → **Vocal** (if present) |
| 12|       | EQ → **Classic** (if present) |
| 13|       | Open case lid (battery push), wait 5s |
| 14|       | Put one bud in the case, wait 5s |

If your app shows a control we didn't list (e.g. spatial audio, in-ear detection
toggle, game mode), do it too and add a row — more is better.

## C. Grab the log

1. *Developer options* → **Bug report** → **Full report** (or Interactive).
2. Wait for the "Bug report captured" notification, then share/save the
   `.zip` to Files or pull it with adb:
   ```bash
   adb bugreport bugreport.zip
   ```
3. Inside the bugreport zip the snoop is at
   `FS/data/misc/bluetooth/logs/btsnoop_hci.log`
   (on some devices just `btsnoop_hci.log` at the archive root).

## D. Hand it over

Copy it into the repo and run the extractor:

```bash
cp /path/to/btsnoop_hci.log ~/Documents/RedmiBudsControl/captures/btsnoop_hci.log
cd ~/Documents/RedmiBudsControl
./tools/extract_commands.sh captures/btsnoop_hci.log
```

`extract_commands.sh` prints every ATT **Write Request/Command** (and
notifications) with handle + hex value + timestamp — that list is exactly what
we turn into the ANC/EQ command frames in Phase 3. The `# ~Time` notes from
section B let us map each write to its action.

## Notes / gotchas

- The official app may **encrypt/authenticate** the channel (challenge-response
  on connect). If writes look random per session, we'll also need the app's
  auth handshake from the same snoop — it's all in the file.
- Only one central connects at a time: keep the **macOS app disconnected**
  during the Android capture. (The macOS app's own capture is just a
  convenience cross-check; the Android snoop is the source of truth.)
