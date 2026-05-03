import Foundation
import CoreBluetooth
import Combine

@MainActor
final class OlleeBTManager: NSObject, ObservableObject {
    static let shared = OlleeBTManager()

    @Published var isScanning = false
    @Published var isConnected = false
    @Published var discoveredPeripherals: [(peripheral: CBPeripheral, name: String)] = []
    @Published var lastError: String?
    @Published var lastSentValue: String?

    private var centralManager: CBCentralManager!
    private var targetPeripheral: CBPeripheral?
    private var targetCharacteristic: CBCharacteristic?

    private let savedUUIDKey = "ollee_saved_peripheral_uuid"
    private var pendingValue: String?
    private var reconnectWorkItem: DispatchWorkItem?

    private override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: .main)
    }

    // MARK: - Persistence

    var savedPeripheralUUID: UUID? {
        get {
            guard let uuidString = UserDefaults.standard.string(forKey: savedUUIDKey) else { return nil }
            return UUID(uuidString: uuidString)
        }
        set {
            UserDefaults.standard.set(newValue?.uuidString, forKey: savedUUIDKey)
        }
    }

    func forgetDevice() {
        if let periph = targetPeripheral {
            centralManager.cancelPeripheralConnection(periph)
        }
        savedPeripheralUUID = nil
        targetPeripheral = nil
        targetCharacteristic = nil
        isConnected = false
    }

    // MARK: - Scanning

    func startScan() {
        guard centralManager.state == .poweredOn else {
            lastError = "Bluetooth is not powered on."
            return
        }
        discoveredPeripherals.removeAll()
        isScanning = true

        // If iOS already knows a connected peripheral with the Ollee service,
        // surface it immediately without waiting for a scan advertisement.
        let connected = centralManager.retrieveConnectedPeripherals(withServices: [OlleeProtocol.serviceUUID])
        for periph in connected {
            let name = periph.name ?? "Ollee (Connected)"
            if !discoveredPeripherals.contains(where: { $0.peripheral.identifier == periph.identifier }) {
                discoveredPeripherals.append((periph, name))
            }
        }

        // Ollee uses the Nordic UART service UUID. Scanning for this filters
        // out everything except the watch (and similar UART devices).
        centralManager.scanForPeripherals(
            withServices: [OlleeProtocol.serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            self?.stopScan()
        }
    }

    func stopScan() {
        centralManager.stopScan()
        isScanning = false
    }

    func connect(to peripheral: CBPeripheral) {
        stopScan()
        targetPeripheral = peripheral
        targetPeripheral?.delegate = self
        centralManager.connect(peripheral, options: nil)
    }

    func reconnectToSaved() {
        guard centralManager.state == .poweredOn else { return }
        guard let uuid = savedPeripheralUUID else { return }
        guard targetPeripheral == nil || !isConnected else { return }

        let peripherals = centralManager.retrievePeripherals(withIdentifiers: [uuid])
        if let periph = peripherals.first {
            targetPeripheral = periph
            targetPeripheral?.delegate = self
            centralManager.connect(periph, options: nil)
        }
    }

    // MARK: - Sending

    /// Sends a value to the watch. If not connected, stores it and attempts reconnect.
    func send(value: String) async -> Bool {
        let trimmed = String(value.prefix(6))
        pendingValue = trimmed
        lastSentValue = trimmed

        if isConnected, let char = targetCharacteristic, let periph = targetPeripheral {
            let packet = OlleeProtocol.buildPacket(value: trimmed)
            periph.writeValue(packet, for: char, type: .withResponse)
            pendingValue = nil
            return true
        }

        // Not ready – try to reconnect if we have a saved device
        reconnectToSaved()
        lastError = "Watch not connected. Will retry when connected."
        return false
    }

    private func trySendPending() {
        guard let value = pendingValue else { return }
        guard isConnected, let char = targetCharacteristic, let periph = targetPeripheral else { return }
        let packet = OlleeProtocol.buildPacket(value: value)
        periph.writeValue(packet, for: char, type: .withResponse)
        pendingValue = nil
    }

    // MARK: - Reconnect scheduling

    private func scheduleReconnect() {
        reconnectWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.reconnectToSaved()
        }
        reconnectWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: item)
    }
}

// MARK: - CBCentralManagerDelegate

extension OlleeBTManager: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            if central.state == .poweredOn {
                reconnectToSaved()
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any],
                                    rssi RSSI: NSNumber) {
        Task { @MainActor in
            guard RSSI.intValue > -90 else { return }
            let advName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
            let displayName = peripheral.name ?? advName ?? "Ollee (Unknown Name)"
            // Store if not already present
            if !discoveredPeripherals.contains(where: { $0.peripheral.identifier == peripheral.identifier }) {
                discoveredPeripherals.append((peripheral, displayName))
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            isConnected = true
            lastError = nil
            savedPeripheralUUID = peripheral.identifier
            peripheral.discoverServices([OlleeProtocol.serviceUUID])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didFailToConnect peripheral: CBPeripheral,
                                    error: Error?) {
        Task { @MainActor in
            lastError = error?.localizedDescription ?? "Failed to connect"
            scheduleReconnect()
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didDisconnectPeripheral peripheral: CBPeripheral,
                                    error: Error?) {
        Task { @MainActor in
            isConnected = false
            targetCharacteristic = nil
            if let err = error {
                lastError = "Disconnected: \(err.localizedDescription)"
            }
            scheduleReconnect()
        }
    }
}

// MARK: - CBPeripheralDelegate

extension OlleeBTManager: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            if let err = error {
                lastError = "Service discovery error: \(err.localizedDescription)"
                return
            }
            guard let service = peripheral.services?.first(where: { $0.uuid == OlleeProtocol.serviceUUID }) else {
                lastError = "Ollee service not found on device."
                return
            }
            peripheral.discoverCharacteristics([OlleeProtocol.charUUID], for: service)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didDiscoverCharacteristicsFor service: CBService,
                                error: Error?) {
        Task { @MainActor in
            if let err = error {
                lastError = "Characteristic discovery error: \(err.localizedDescription)"
                return
            }
            guard let char = service.characteristics?.first(where: { $0.uuid == OlleeProtocol.charUUID }) else {
                lastError = "Ollee TX characteristic not found."
                return
            }
            targetCharacteristic = char
            trySendPending()
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didWriteValueFor characteristic: CBCharacteristic,
                                error: Error?) {
        Task { @MainActor in
            if let err = error {
                lastError = "Write error: \(err.localizedDescription)"
            } else {
                lastError = nil
            }
        }
    }
}
