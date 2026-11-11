import CoreBluetooth
import DeskCore
import Foundation
import os

struct DiscoveredDesk: Identifiable, Equatable {
    let id: UUID
    let name: String
    let advertisesLinak: Bool
}

/// Talks to the LINAK control box over Bluetooth LE. All callbacks arrive on the main queue.
@MainActor
final class DeskController: NSObject, ObservableObject {
    enum Status: Equatable {
        case bluetoothOff
        case unauthorized
        case notConfigured
        case connecting
        case connected
        case moving
    }

    @Published private(set) var status: Status = .notConfigured
    @Published private(set) var sample: HeightSpeed?
    @Published private(set) var discovered: [DiscoveredDesk] = []
    @Published private(set) var isScanning = false
    @Published private(set) var lastError: String?

    private static let tickInterval: TimeInterval = 0.3
    private static let reconnectDelay: TimeInterval = 5

    private let log = Logger(subsystem: "local.desknudge", category: "ble")
    private let controlService = CBUUID(string: LinakUUID.controlService)
    private let outputService = CBUUID(string: LinakUUID.referenceOutputService)
    private let inputService = CBUUID(string: LinakUUID.referenceInputService)
    private let commandUUID = CBUUID(string: LinakUUID.command)
    private let heightUUID = CBUUID(string: LinakUUID.heightSpeed)
    private let inputUUID = CBUUID(string: LinakUUID.referenceInput)

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var scanned: [UUID: CBPeripheral] = [:]
    private var commandChar: CBCharacteristic?
    private var heightChar: CBCharacteristic?
    private var inputChar: CBCharacteristic?
    private var deskID: UUID?
    private var userDisconnected = false

    private var tracker: MoveTracker?
    private var moveTimer: Timer?
    private var jogTimer: Timer?
    private static let maxJogDuration: TimeInterval = 30
    private var pendingTarget: UInt16?
    private var moveCompletion: ((Result<UInt16, DeskError>) -> Void)?

    init(deskID: UUID?) {
        self.deskID = deskID
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    // MARK: - Public API

    var isReady: Bool { status == .connected || status == .moving }

    func startScan() {
        guard central.state == .poweredOn else { return }
        discovered = []
        scanned = [:]
        isScanning = true
        central.scanForPeripherals(withServices: nil, options: nil)
    }

    func stopScan() {
        central.stopScan()
        isScanning = false
    }

    func use(desk: DiscoveredDesk) {
        stopScan()
        disconnect()
        deskID = desk.id
        userDisconnected = false
        connectToSavedDesk()
    }

    /// Drives to `target` (0.1 mm above lowest position). Connects first if needed.
    func move(to target: UInt16, completion: ((Result<UInt16, DeskError>) -> Void)? = nil) {
        endJog()
        finishMove(with: .failure(.cancelled))
        moveCompletion = completion
        lastError = nil
        guard isReady, let commandChar, let inputChar, let peripheral else {
            pendingTarget = target
            connectToSavedDesk()
            return
        }
        peripheral.writeValue(LinakCommand.wakeUp, for: commandChar, type: writeType(commandChar))
        peripheral.writeValue(LinakCommand.stop, for: commandChar, type: writeType(commandChar))
        tracker = MoveTracker(target: target, startedAt: Date())
        status = .moving
        writeTarget(target, to: inputChar, on: peripheral)
        moveTimer = Timer.scheduledTimer(withTimeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func stop() {
        endJog()
        finishMove(with: .failure(.cancelled))
    }

    enum JogDirection { case up, down }

    /// Hold-to-move: the desk moves only while this is active and stops on `endJog()`.
    func startJog(_ direction: JogDirection) {
        finishMove(with: .failure(.cancelled))
        endJog()
        guard isReady, let peripheral, let commandChar else {
            lastError = DeskError.notConnected.localizedDescription
            return
        }
        let command = direction == .up ? LinakCommand.up : LinakCommand.down
        let startedAt = Date()
        status = .moving
        peripheral.writeValue(command, for: commandChar, type: writeType(commandChar))
        jogTimer = Timer.scheduledTimer(withTimeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard Date().timeIntervalSince(startedAt) < Self.maxJogDuration else {
                    self.endJog()
                    return
                }
                guard let peripheral = self.peripheral, let commandChar = self.commandChar else {
                    self.endJog()
                    return
                }
                peripheral.writeValue(command, for: commandChar, type: self.writeType(commandChar))
            }
        }
    }

    func endJog() {
        guard let jogTimer else { return }
        jogTimer.invalidate()
        self.jogTimer = nil
        if let peripheral, let commandChar {
            peripheral.writeValue(LinakCommand.stop, for: commandChar, type: writeType(commandChar))
        }
        if status == .moving { status = .connected }
    }

    // MARK: - Movement

    private func tick() {
        guard let tracker, let peripheral, let inputChar else {
            finishMove(with: .failure(.notConnected))
            return
        }
        switch tracker.evaluate(now: Date(), sample: sample) {
        case .keepGoing:
            writeTarget(tracker.target, to: inputChar, on: peripheral)
            peripheral.readValue(for: heightChar ?? inputChar)
        case .reached:
            finishMove(with: .success(sample?.position ?? tracker.target))
        case .stoppedShort(let position):
            finishMove(with: .failure(.stoppedShort(position)))
        case .timedOut:
            finishMove(with: .failure(.timedOut))
        }
    }

    private func writeTarget(_ target: UInt16, to characteristic: CBCharacteristic, on peripheral: CBPeripheral) {
        peripheral.writeValue(LinakCodec.encodeTarget(target), for: characteristic, type: writeType(characteristic))
    }

    private func finishMove(with result: Result<UInt16, DeskError>) {
        guard tracker != nil || moveCompletion != nil || pendingTarget != nil else { return }
        moveTimer?.invalidate()
        moveTimer = nil
        let wasMoving = tracker != nil
        tracker = nil
        pendingTarget = nil
        if wasMoving, let peripheral, let commandChar {
            peripheral.writeValue(LinakCommand.stop, for: commandChar, type: writeType(commandChar))
        }
        if status == .moving { status = .connected }
        if case .failure(let error) = result, error != .cancelled {
            lastError = error.localizedDescription
            log.error("move failed: \(error.localizedDescription, privacy: .public)")
        }
        let completion = moveCompletion
        moveCompletion = nil
        completion?(result)
    }

    private func writeType(_ characteristic: CBCharacteristic) -> CBCharacteristicWriteType {
        characteristic.properties.contains(.write) ? .withResponse : .withoutResponse
    }

    // MARK: - Connection

    private func connectToSavedDesk() {
        guard central.state == .poweredOn else { return }
        guard let deskID else {
            status = .notConfigured
            return
        }
        let target = central.retrievePeripherals(withIdentifiers: [deskID]).first ?? scanned[deskID]
        guard let target else {
            lastError = DeskError.notFound.localizedDescription
            status = .notConfigured
            return
        }
        peripheral = target
        target.delegate = self
        status = .connecting
        // Pending connects never time out: CoreBluetooth connects as soon as the desk is reachable.
        central.connect(target, options: nil)
    }

    private func disconnect() {
        finishMove(with: .failure(.cancelled))
        guard let peripheral else { return }
        userDisconnected = true
        central.cancelPeripheralConnection(peripheral)
        self.peripheral = nil
        resetCharacteristics()
    }

    private func resetCharacteristics() {
        commandChar = nil
        heightChar = nil
        inputChar = nil
    }

    private func becameReady() {
        guard commandChar != nil, heightChar != nil, inputChar != nil else { return }
        status = .connected
        lastError = nil
        if let pendingTarget {
            let completion = moveCompletion
            self.pendingTarget = nil
            moveCompletion = nil
            move(to: pendingTarget, completion: completion)
        }
    }
}

enum DeskError: Error, Equatable, LocalizedError {
    case notConnected
    case notFound
    case stoppedShort(UInt16)
    case timedOut
    case cancelled

    var errorDescription: String? {
        switch self {
        case .notConnected: return "Tisch ist nicht verbunden."
        case .notFound: return "Tisch nicht gefunden. In den Einstellungen neu suchen."
        case .stoppedShort: return "Tisch hat vor dem Ziel angehalten (Hindernis oder Handschalter?)."
        case .timedOut: return "Fahrt hat zu lange gedauert und wurde gestoppt."
        case .cancelled: return "Fahrt abgebrochen."
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension DeskController: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated {
            switch central.state {
            case .poweredOn:
                connectToSavedDesk()
            case .unauthorized:
                status = .unauthorized
            default:
                status = .bluetoothOff
                isScanning = false
            }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let advertised = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
        let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        MainActor.assumeIsolated {
            guard let name = localName ?? peripheral.name, !name.isEmpty else { return }
            scanned[peripheral.identifier] = peripheral
            let desk = DiscoveredDesk(
                id: peripheral.identifier,
                name: name,
                advertisesLinak: advertised.contains(controlService) || name.lowercased().contains("desk")
            )
            guard !discovered.contains(where: { $0.id == desk.id }) else { return }
            discovered = (discovered + [desk]).sorted { lhs, rhs in
                lhs.advertisesLinak != rhs.advertisesLinak ? lhs.advertisesLinak : lhs.name < rhs.name
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated {
            userDisconnected = false
            peripheral.discoverServices([controlService, outputService, inputService])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        let message = error?.localizedDescription ?? "unbekannt"
        MainActor.assumeIsolated {
            lastError = "Verbindung fehlgeschlagen: \(message)"
            scheduleReconnect()
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated {
            jogTimer?.invalidate()
            jogTimer = nil
            finishMove(with: .failure(.notConnected))
            resetCharacteristics()
            sample = nil
            if userDisconnected {
                status = deskID == nil ? .notConfigured : .connecting
            } else {
                scheduleReconnect()
            }
        }
    }

    private func scheduleReconnect() {
        status = .connecting
        Timer.scheduledTimer(withTimeInterval: Self.reconnectDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.userDisconnected, !self.isReady else { return }
                self.connectToSavedDesk()
            }
        }
    }
}

// MARK: - CBPeripheralDelegate

extension DeskController: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        MainActor.assumeIsolated {
            if let error {
                lastError = "Dienste nicht lesbar: \(error.localizedDescription)"
                return
            }
            for service in peripheral.services ?? [] {
                peripheral.discoverCharacteristics([commandUUID, heightUUID, inputUUID], for: service)
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        MainActor.assumeIsolated {
            for characteristic in service.characteristics ?? [] {
                switch characteristic.uuid {
                case commandUUID:
                    commandChar = characteristic
                case heightUUID:
                    heightChar = characteristic
                    peripheral.setNotifyValue(true, for: characteristic)
                    peripheral.readValue(for: characteristic)
                case inputUUID:
                    inputChar = characteristic
                default:
                    break
                }
            }
            becameReady()
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        let value = characteristic.value
        let uuid = characteristic.uuid
        MainActor.assumeIsolated {
            guard error == nil, uuid == heightUUID, let value, let decoded = LinakCodec.decodeHeightSpeed(value) else { return }
            sample = decoded
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let error else { return }
        let message = error.localizedDescription
        MainActor.assumeIsolated {
            log.error("write failed: \(message, privacy: .public)")
            lastError = "Schreiben fehlgeschlagen: \(message)"
        }
    }
}
