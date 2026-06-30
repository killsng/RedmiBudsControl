import Foundation
import IOBluetooth
import Combine

struct PairedDevice: Identifiable, Hashable {
    let address: String
    let name: String
    let device: IOBluetoothDevice
    var id: String { address }
}

/// Single ObservableObject driving the whole app: lists paired buds, opens the
/// MMA RFCOMM channel, speaks the protocol (battery / ANC / EQ), and exposes
/// state to SwiftUI.
final class EarbudsManager: NSObject, ObservableObject {

    enum LinkState: String { case idle, connecting, connected, authed, failed }

    @Published private(set) var paired: [PairedDevice] = []
    @Published private(set) var selectedAddress: String?
    @Published private(set) var linkState: LinkState = .idle
    @Published private(set) var authRequired = false
    @Published private(set) var authed = false
    @Published var battery = BatteryState()
    @Published var ancMode: ANCMode = .off
    @Published var soundMode: SoundMode = .original

    /// True when we have at least read the current state from the buds.
    @Published private(set) var protocolReady = false
    /// True when cached state (battery/ANC/EQ) is available to show, even if
    /// we've gone idle (transient mode) and the channel is closed.
    @Published private(set) var stateKnown = false
    /// Transient mode: auto-close the MMA channel shortly after each op so the
    /// buds' A2DP/HFP audio profiles come back. Persisted.
    @Published var transientMode: Bool {
        didSet { UserDefaults.standard.set(transientMode, forKey: "transientMode") }
    }

    let logger = CaptureLogger()

    private var transport: RFCOMMTransport?
    private let parser = MMAParser()
    private var pending: [UInt8: (Result<MMARawPacket, Error>) -> Void] = [:]
    private var nextSN: UInt8 = UInt8.random(in: 0...UInt8.max)
    private var pendingOp: (() -> Void)?
    private var idleWork: DispatchWorkItem?

    private let nameKeywords = ["Redmi Buds", "Xiaomi Buds", "Mi Buds", "RedmiBuds", "Buds"]

    override init() {
        self.transientMode = UserDefaults.standard.object(forKey: "transientMode") as? Bool ?? true
        super.init()
    }

    // MARK: - Discovery

    func refreshPaired() {
        let all = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
        let filtered = all.compactMap { d -> PairedDevice? in
            let name = d.nameOrAddress ?? d.name ?? ""
            return nameKeywords.contains { name.localizedCaseInsensitiveContains($0) }
                ? PairedDevice(address: d.addressString ?? UUID().uuidString,
                               name: name,
                               device: d)
                : nil
        }
        paired = filtered.sorted { $0.name < $1.name }
        logger.info("Paired scan: \(paired.count) Xiaomi/Redmi bud device(s)")
        for d in paired { logger.info("  paired: \(d.name) [\(d.address)]") }
    }

    // MARK: - Connect / disconnect

    func connect(_ device: PairedDevice) {
        // Debounce: ignore connect spam while a connection attempt is in flight.
        if linkState == .connecting { return }
        if connectRetries == 0 { disconnect() }  // full reset only on a fresh user attempt
        connectRetries = 0
        startConnect(device)
    }

    private func startConnect(_ device: PairedDevice) {
        selectedAddress = device.address
        linkState = .connecting
        let t = RFCOMMTransport(logger: logger)
        transport = t
        t.onState = { [weak self] state in self?.handle(state) }
        t.onData = { [weak self] data in self?.handle(data) }
        t.connect(to: device.device)
    }

    func disconnect() {
        idleWork?.cancel()
        transport?.disconnect()
        transport = nil
        selectedAddress = nil
        linkState = .idle
        authed = false
        authRequired = false
        protocolReady = false
        stateKnown = false
        pending.removeAll()
        pendingOp = nil
        battery = BatteryState()
    }

    // MARK: - Transport events

    private func handle(_ state: RFCOMMTransport.State) {
        switch state {
        case .open:
            linkState = .connecting
            logger.info("RFCOMM channel open — probing protocol")
            startProtocol()
        case .closed:
            linkState = .idle
            logger.warn("Link closed")
        case .failed(let reason):
            linkState = .failed
            logger.error("Link failed: \(reason)")
        case .querying, .opening, .idle:
            break
        }
    }

    private func handle(_ data: Data) {
        logger.rx("rfcomm (\(data.count)B)", data)
        let packets = parser.feed(Array(data))
        for p in packets { handle(packet: p) }
    }

    // MARK: - Incoming packets

    private func handle(packet: MMARawPacket) {
        if packet.isRequest {
            handleNotify(packet)
            return
        }
        // Response — match pending request by opCodeSN.
        guard let cb = pending.removeValue(forKey: packet.opCodeSN) else {
            logger.warn("Response with no pending request: sn=\(packet.opCodeSN) op=0x\(String(packet.opcode, radix: 16))")
            return
        }
        cb(.success(packet))
    }

    private func handleNotify(_ p: MMARawPacket) {
        switch p.opcode {
        case MMA.Op.notifyDeviceInfo.rawValue:
            for (tag, value) in MMA.parseInfoTLV(p.data) where tag == MMA.notifyTypeBattery {
                if value.count >= 3 {
                    applyBattery(value)
                    let l = battery.leftPct.map { String($0) } ?? "-"
                    let r = battery.rightPct.map { String($0) } ?? "-"
                    let c = battery.casePct.map { String($0) } ?? "-"
                    logger.info("Battery notify: L=\(l) R=\(r) case=\(c)")
                }
            }
            respond(ackTo: p, data: [])
        case MMA.Op.notifyDeviceConfig.rawValue:
            if let entry = MMA.parseConfigEntry(p.data, at: 0) {
                applyConfig(id: entry.id, value: entry.value)
            }
            respond(ackTo: p, data: [])
        case MMA.Op.sendAuth.rawValue:
            // Device-initiated auth challenge: [0x01, challenge(16)].
            if p.data.count == 17 {
                let challenge = Array(p.data.dropFirst())
                let resp = [UInt8(0x01)] + AuthHandler.encryptAuthCheckData(challenge)
                respond(ackTo: p, data: resp)
                logger.info("Answered device auth challenge")
            } else {
                respond(ackTo: p, data: [])
            }
        case MMA.Op.notifyAuth.rawValue:
            respond(ackTo: p, data: [0x01])
        default:
            logger.info("Notify op=0x\(String(p.opcode, radix: 16)) data=\(p.data.map { String(format:"%02x",$0) }.joined())")
            respond(ackTo: p, data: [])
        }
    }

    private func respond(ackTo p: MMARawPacket, data: [UInt8]) {
        let resp = MMARawPacket(direction: .response, needReply: false,
                                opcode: p.opcode, opCodeSN: p.opCodeSN,
                                status: 0x00, data: data)
        sendFrame(MMAEncoder.encode(response: resp))
    }

    // MARK: - Protocol start (battery probe → maybe auth)

    private func startProtocol() {
        // Probe with a battery read. If the bud answers, great (no auth).
        // If silent, the channel likely still needs auth (we know SEND_AUTH
        // gets a reply on the MMA channel) → run the handshake.
        request(opcode: MMA.Op.getDeviceInfo.rawValue, data: [MMA.infoMaskBattery]) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let resp) where self.hasBattery(in: resp):
                self.transport?.confirmChannel()
                self.consumeBatteryResponse(resp)
                self.markReady()
            case .success:
                self.transport?.confirmChannel()
                self.logger.warn("Channel replied without battery — running auth")
                self.runAuth()
            case .failure:
                // Silent on battery: try auth handshake; if this channel is
                // wrong (no reply to SEND_AUTH either) runAuth advances.
                self.runAuth()
            }
        }
    }

    private func hasBattery(in resp: MMARawPacket) -> Bool {
        MMA.parseInfoTLV(resp.data).contains {
            $0.tag == MMA.notifyTypeBattery && $0.value.count >= 3
        }
    }

    private func consumeBatteryResponse(_ resp: MMARawPacket) {
        for (tag, value) in MMA.parseInfoTLV(resp.data) where tag == MMA.notifyTypeBattery {
            if value.count >= 3 { applyBattery(value) }
        }
    }

    /// 0xFF means "not present / unknown" (e.g. case closed or buds in ears).
    private func applyBattery(_ v: [UInt8]) {
        battery.leftPct = v[0] == 0xFF ? nil : Int(v[0])
        battery.rightPct = v[1] == 0xFF ? nil : Int(v[1])
        battery.casePct = v[2] == 0xFF ? nil : Int(v[2])
    }

    private func markReady() {
        transport?.confirmChannel()
        connectRetries = 0
        protocolReady = true
        stateKnown = true
        authed = true
        linkState = .authed
        logger.info("Protocol ready (no auth needed)")
        onAuthed()
    }

    // MARK: - Auth handshake

    private func runAuth() {
        authRequired = true
        let r1 = AuthHandler.randomAuthCheckData()
        let e1 = AuthHandler.encryptAuthCheckData(r1)
        let req = [UInt8(0x01)] + r1
        request(opcode: MMA.Op.sendAuth.rawValue, data: req) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let resp):
                self.transport?.confirmChannel()
                let expected = [UInt8(0x01)] + e1
                if resp.data == expected {
                    self.logger.info("Auth step 1 OK — bud accepted our crypto")
                    self.sendAuthStatus()
                } else {
                    self.logger.error("Auth step 1 mismatch (crypto wrong?). expected=\(expected.hex) got=\(resp.data.hex)")
                    self.linkState = .failed
                }
            case .failure(let e):
                // No reply to SEND_AUTH on this channel → wrong service; advance.
                self.logger.warn("No reply to auth-init on this channel (\(e)); next")
                if self.transport?.tryNextChannel() != true { self.retryConnectOrGiveUp() }
            }
        }
    }

    /// All channels exhausted without a reply — the MMA service may not be in
    /// SDP yet (buds not in an active connection). Retry a fresh connect a few
    /// times before giving up.
    private var connectRetries = 0
    private func retryConnectOrGiveUp() {
        guard connectRetries < 2, let addr = selectedAddress,
              let dev = paired.first(where: { $0.address == addr }) else {
            logger.error("No channel answered after retries. Ensure buds are the active audio output and not connected to a phone.")
            linkState = .failed
            return
        }
        connectRetries += 1
        logger.warn("No MMA channel yet — fresh SDP retry \(connectRetries)/2 in 3s…")
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.startConnect(dev)
        }
    }

    private func sendAuthStatus() {
        request(opcode: MMA.Op.notifyAuth.rawValue, data: [0x01, 0x00]) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let resp) where resp.data == [0x01]:
                self.authed = true
                self.protocolReady = true
                self.stateKnown = true
                self.linkState = .authed
                self.logger.info("Auth complete")
                self.onAuthed()
            default:
                self.logger.error("Auth status unexpected")
                self.linkState = .failed
            }
        }
    }

    // MARK: - Transient mode (audio coexistence)

    /// Called right after the channel is authenticated and usable. Runs any op
    /// that was queued while (re)connecting, refreshes state, and (in transient
    /// mode) schedules closing the channel so the buds' audio profiles return.
    private func onAuthed() {
        refreshAll()
        let op = pendingOp
        pendingOp = nil
        op?()
        armIdle()
    }

    /// Ensure we are connected+authed, run `op`, then (transient) go idle.
    private func transact(_ op: @escaping () -> Void) {
        if protocolReady {                 // already connected
            op()
            armIdle()
        } else if let addr = selectedAddress,
                  let dev = paired.first(where: { $0.address == addr }) {
            pendingOp = op                 // run once authed (onAuthed)
            startConnect(dev)
        }
    }

    private func armIdle() {
        idleWork?.cancel()
        guard transientMode else { return }
        let w = DispatchWorkItem { [weak self] in self?.goIdle() }
        idleWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: w)
    }

    /// Close the MMA channel but keep cached state + stateKnown, so the buds
    /// re-register their A2DP/HFP audio profiles with macOS.
    private func goIdle() {
        guard transport != nil else { return }
        logger.info("Idle → closing MMA channel so audio can resume")
        idleWork?.cancel()
        transport?.disconnect()
        transport = nil
        protocolReady = false
        authed = false
        linkState = .idle
        pending.removeAll()
    }

    // MARK: - High-level ops

    func refreshAll() {
        getBattery()
        getANC()
        getEQ()
    }

    /// UI "Refresh": (re)connect transiently, read fresh state, go idle.
    func refresh() {
        transact { self.refreshAll() }
    }

    func getBattery() {
        request(opcode: MMA.Op.getDeviceInfo.rawValue, data: [MMA.infoMaskBattery]) { [weak self] resp in
            if case .success(let r) = resp { self?.consumeBatteryResponse(r) }
        }
    }

    func getANC() {
        request(opcode: MMA.Op.getDeviceConfig.rawValue,
                data: MMA.packGetConfig(MMA.Config.noiseCancellationMode.rawValue)) { [weak self] resp in
            guard let self, case .success(let r) = resp,
                  let entry = MMA.parseConfigEntry(r.data, at: 0) else { return }
            self.applyConfig(id: entry.id, value: entry.value)
        }
    }

    func setANC(_ mode: ANCMode) {
        ancMode = mode // optimistic; the bud's notify corrects it
        transact { self.sendSetANC(mode) }
    }

    private func sendSetANC(_ mode: ANCMode) {
        let value: [UInt8] = [mode.wireByte, 0x00]
        request(opcode: MMA.Op.setDeviceConfig.rawValue,
                data: MMA.packSetConfig(MMA.Config.noiseCancellationMode.rawValue, value: value)) { [weak self] resp in
            guard let self else { return }
            if case .success(let r) = resp, r.status == 0 {
                self.logger.info("ANC set -> \(mode.label)")
            } else {
                self.logger.error("ANC set failed (auth required?)")
            }
        }
    }

    func getEQ() {
        request(opcode: MMA.Op.getDeviceConfig.rawValue,
                data: MMA.packGetConfig(MMA.Config.equalizerMode.rawValue)) { [weak self] resp in
            guard let self, case .success(let r) = resp,
                  let entry = MMA.parseConfigEntry(r.data, at: 0) else { return }
            self.applyConfig(id: entry.id, value: entry.value)
        }
    }

    func setEQ(_ mode: SoundMode) {
        soundMode = mode // optimistic
        transact { self.sendSetEQ(mode) }
    }

    private func sendSetEQ(_ mode: SoundMode) {
        let value: [UInt8] = [mode.wireByte, 0x00]
        request(opcode: MMA.Op.setDeviceConfig.rawValue,
                data: MMA.packSetConfig(MMA.Config.equalizerMode.rawValue, value: value)) { [weak self] resp in
            guard let self else { return }
            if case .success(let r) = resp, r.status == 0 {
                self.logger.info("EQ set -> \(mode.label)")
            } else {
                self.logger.error("EQ set failed (auth required?)")
            }
        }
    }

    private func applyConfig(id: UInt16, value: [UInt8]) {
        guard let cfg = MMA.Config(rawValue: id) else {
            logger.info("config 0x\(String(id, radix: 16)) = \(value.hex)")
            return
        }
        switch cfg {
        case .noiseCancellationMode where value.first != nil:
            ancMode = ANCMode(rawValue: value[0]) ?? .off
            logger.info("ANC = \(ancMode.label) (raw \(value.hex))")
        case .equalizerMode where value.first != nil:
            soundMode = SoundMode(rawValue: value[0]) ?? .original
            logger.info("EQ = \(soundMode.label) (raw \(value.hex))")
        default:
            logger.info("config \(cfg) = \(value.hex)")
        }
    }

    // MARK: - Request engine

    private func request(opcode: UInt8, data: [UInt8],
                         needReply: Bool = true,
                         completion: @escaping (Result<MMARawPacket, Error>) -> Void) {
        guard let transport, transport.isOpen else {
            completion(.failure(Err.notConnected)); return
        }
        let sn = nextSN &+ 1
        nextSN = sn
        let req = MMARawPacket(direction: .request, needReply: needReply,
                               opcode: opcode, opCodeSN: sn, status: 0, data: data)
        let frame = MMAEncoder.encode(request: req)
        logger.tx("op=0x\(String(opcode, radix: 16)) sn=\(sn)", Data(frame))
        if needReply { pending[sn] = completion }

        let sent = transport.send(Data(frame))
        if !sent {
            pending.removeValue(forKey: sn)
            completion(.failure(Err.writeFailed)); return
        }
        if needReply {
            let key = sn
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                if let cb = self?.pending.removeValue(forKey: key) {
                    cb(.failure(Err.timeout))
                }
            }
        } else {
            completion(.success(req))
        }
    }

    private func sendFrame(_ bytes: [UInt8]) {
        _ = transport?.send(Data(bytes))
    }

    private enum Err: Error, CustomStringConvertible {
        case notConnected, writeFailed, timeout
        var description: String {
            switch self {
            case .notConnected: return "not connected"
            case .writeFailed: return "write failed"
            case .timeout: return "timeout"
            }
        }
    }
}

private extension Array where Element == UInt8 {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}
