import Foundation
import IOBluetooth

/// Classic-Bluetooth RFCOMM transport for the Xiaomi MMA channel.
///
/// Walks the device's RFCOMM services until one responds to the manager's
/// battery probe. Channels 1/2 (HFP/HSP) are tried last. A channel that opens
/// then closes before being "confirmed" auto-advances to the next, so a wrong
/// service never causes a reconnect loop.
final class RFCOMMTransport: NSObject {
    enum State { case idle, querying, opening, open, closed, failed(String) }

    var onState: ((State) -> Void)?
    var onData: ((Data) -> Void)?
    private(set) weak var logger: CaptureLogger?

    private weak var device: IOBluetoothDevice?
    private var channel: IOBluetoothRFCOMMChannel?
    private(set) var channelOpen = false
    private var channels: [UInt8] = []
    private var channelIndex = 0
    private var confirmed = false   // set true once the manager says the channel works

    init(logger: CaptureLogger) {
        self.logger = logger
        super.init()
    }

    var isOpen: Bool { channelOpen }

    /// Manager calls this once the battery probe got a reply on this channel.
    func confirmChannel() {
        confirmed = true
        logger?.info("Transport: channel \(channels.indices.contains(channelIndex) ? channels[channelIndex] : 0) confirmed")
    }

    func connect(to device: IOBluetoothDevice) {
        self.device = device
        confirmed = false
        logger?.info("Transport: connecting to \(device.nameOrAddress ?? "?")")
        if !device.isConnected() {
            logger?.info("Transport: base connection down, opening…")
            _ = device.openConnection()
        }
        // Give the buds a moment to bring up audio profiles and register the
        // MMA service in SDP (it appears only on an active connection).
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.querySDP()
        }
    }

    func disconnect() {
        confirmed = true // suppress auto-advance on intentional disconnect
        if let channel, channelOpen {
            logger?.info("Transport: closing RFCOMM channel")
            _ = channel.close()
        }
        channel = nil
        channelOpen = false
        onState?(.closed)
    }

    @discardableResult
    func send(_ data: Data) -> Bool {
        guard let channel else {
            logger?.error("Transport: send with no channel")
            return false
        }
        let result: IOReturn = data.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) -> IOReturn in
            guard let base = ptr.baseAddress else { return kIOReturnError }
            let mutPtr = UnsafeMutableRawPointer(mutating: base)
            return channel.writeSync(mutPtr, length: UInt16(data.count))
        }
        if result != kIOReturnSuccess {
            logger?.error("Transport: writeSync failed 0x\(String(result, radix: 16))")
            return false
        }
        return true
    }

    // MARK: - SDP

    private func querySDP() {
        guard let device else { return }
        onState?(.querying)
        logger?.info("Transport: SDP query…")
        let r = device.performSDPQuery(self)
        if r != kIOReturnSuccess {
            onState?(.failed("SDP query failed 0x\(String(r, radix: 16))"))
        }
    }

    @objc func sdpQueryComplete(_ device: IOBluetoothDevice, status: IOReturn) {
        handleSDPComplete(device: device, status: status)
    }
    @objc func deviceSDPQueryComplete(_ device: IOBluetoothDevice, status: IOReturn) {
        handleSDPComplete(device: device, status: status)
    }

    private func handleSDPComplete(device: IOBluetoothDevice, status: IOReturn) {
        if status != kIOReturnSuccess {
            logger?.error("Transport: SDP complete status 0x\(String(status, radix: 16))")
        }
        guard let services = device.services as? [IOBluetoothSDPServiceRecord] else {
            onState?(.failed("No SDP services")); return
        }
        logger?.info("Transport: \(services.count) SDP service record(s)")

        var found = Set<UInt8>()
        for record in services {
            var channelID: UInt8 = 0
            if record.getRFCOMMChannelID(&channelID) == kIOReturnSuccess {
                found.insert(channelID)
            }
        }
        // Try non-HFP channels first (1 and 2 are almost always HFP/HSP).
        let ordered = found.sorted { a, b in
            let hfpA = (a == 1 || a == 2), hfpB = (b == 1 || b == 2)
            if hfpA != hfpB { return !hfpA }   // non-HFP first
            return a > b                       // higher (likely vendor) first
        }
        for c in ordered { logger?.info("Transport: SDP RFCOMM channel \(c)") }

        // The MMA service is sometimes NOT advertised in SDP (e.g. when the buds
        // hold a stale host session). RFCOMM channels can still be opened by
        // number, so prepend known/dynamic MMA channels to try directly (24 first).
        let fallback = [24, 25, 26, 20, 19, 18].filter { !found.contains($0) }
        for ch in fallback { logger?.info("Transport: + direct MMA channel probe \(ch) (not in SDP)") }
        channels = fallback + ordered
        guard let first = channels.first else {
            onState?(.failed("No RFCOMM channel in SDP")); return
        }
        channelIndex = 0
        openChannel(id: first)
    }

    /// Advance to the next discovered channel. Returns false if none remain.
    func tryNextChannel() -> Bool {
        let nxt = channelIndex + 1
        guard channels.indices.contains(nxt) else { return false }
        channelIndex = nxt
        confirmed = false
        if let channel, channelOpen { _ = channel.close() }
        channel = nil; channelOpen = false
        openChannel(id: channels[nxt])
        return true
    }

    private func openChannel(id: UInt8) {
        guard let device else { return }
        onState?(.opening)
        logger?.info("Transport: opening RFCOMM channel \(id)")
        var newChannel: IOBluetoothRFCOMMChannel?
        let result = device.openRFCOMMChannelAsync(&newChannel, withChannelID: id, delegate: self)
        if result != kIOReturnSuccess {
            logger?.warn("Transport: channel \(id) open rc=0x\(String(result, radix: 16)); next")
            if !tryNextChannel() { onState?(.failed("no channel would open")) }
            return
        }
        channel = newChannel
        // Guard: if the channel doesn't finish opening (dead channel), advance.
        let idx = channelIndex
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self else { return }
            if self.channelIndex == idx && !self.channelOpen {
                self.logger?.warn("Transport: channel \(self.channels[safe: idx] ?? id) open timed out; next")
                _ = self.tryNextChannel()
            }
        }
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

extension RFCOMMTransport: IOBluetoothRFCOMMChannelDelegate {
    func rfcommChannelOpenComplete(_ inRFCOMMChannel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        if error == kIOReturnSuccess {
            channelOpen = true
            confirmed = false
            logger?.info("Transport: RFCOMM channel open")
            onState?(.open)
        } else {
            logger?.warn("Transport: openComplete err 0x\(String(error, radix: 16)); next")
            if !tryNextChannel() { onState?(.failed("channel open 0x\(String(error, radix: 16))")) }
        }
    }

    func rfcommChannelClosed(_ inRFCOMMChannel: IOBluetoothRFCOMMChannel!) {
        channel = nil; channelOpen = false
        if confirmed {
            logger?.warn("Transport: RFCOMM channel closed")
            onState?(.closed)
        } else {
            // Closed before we confirmed it works → wrong service (e.g. HFP).
            logger?.warn("Transport: channel closed before reply; trying next")
            if !tryNextChannel() { onState?(.closed) }
        }
    }

    func rfcommChannelData(_ inRFCOMMChannel: IOBluetoothRFCOMMChannel!,
                           data dataPtr: UnsafeMutableRawPointer!,
                           length dataLength: Int) {
        onData?(Data(bytes: dataPtr, count: dataLength))
    }
}
