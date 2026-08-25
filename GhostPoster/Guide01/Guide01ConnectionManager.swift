@preconcurrency import CoreBluetooth
import Combine
import Foundation
import Guide01SDK

enum Guide01ConnectionState: Equatable {
    case idle
    case bluetoothUnavailable
    case scanning
    case connecting
    case ready
    case failed(String)

    var label: String {
        switch self {
        case .idle: "未接続"
        case .bluetoothUnavailable: "Bluetoothを利用できません"
        case .scanning: "GUIDE01を検索中"
        case .connecting: "GUIDE01へ接続中"
        case .ready: "GUIDE01接続済み"
        case .failed: "GUIDE01へ接続できません"
        }
    }

    var canRetry: Bool {
        switch self {
        case .idle, .failed:
            true
        default:
            false
        }
    }
}

@MainActor
final class Guide01ConnectionManager: NSObject, ObservableObject {
    @Published private(set) var state: Guide01ConnectionState = .idle

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var messageCharacteristic: CBCharacteristic?
    private var commandCharacteristic: CBCharacteristic?
    private var shouldBeActive = false
    private var pendingMessage: Guide01StatusMessage?

    private let serviceUUID = CBUUID(string: Guide01UUIDs.service)
    private let messageUUID = CBUUID(string: Guide01UUIDs.msgNotify)
    private let commandUUID = CBUUID(string: Guide01UUIDs.cmd)

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func start() {
        shouldBeActive = true
        connectIfPossible()
    }

    func stop() {
        shouldBeActive = false
        central.stopScan()
        pendingMessage = nil
        if let peripheral {
            central.cancelPeripheralConnection(peripheral)
        } else {
            state = .idle
        }
    }

    func retry() {
        guard shouldBeActive else { return }
        if let peripheral {
            central.cancelPeripheralConnection(peripheral)
        }
        clearConnection()
        connectIfPossible()
    }

    func display(_ message: Guide01StatusMessage) {
        pendingMessage = message
        guard state == .ready else { return }

        let data = guide01Notification(
            name: "GhostPoster",
            title: message.title,
            content: message.content
        )
        guard !data.isEmpty else {
            state = .failed("表示データを生成できませんでした")
            return
        }
        write(data, to: messageCharacteristic)
    }

    private func connectIfPossible() {
        guard shouldBeActive else { return }
        guard central.state == .poweredOn else {
            if central.state != .unknown && central.state != .resetting {
                state = .bluetoothUnavailable
            }
            return
        }

        if let connected = central.retrieveConnectedPeripherals(
            withServices: [serviceUUID]
        ).first {
            connect(connected)
            return
        }

        state = .scanning
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    private func connect(_ peripheral: CBPeripheral) {
        central.stopScan()
        self.peripheral = peripheral
        peripheral.delegate = self
        state = .connecting
        central.connect(peripheral, options: nil)
    }

    private func configureDisplay() {
        let data = guide01NotificationDisplayTime(seconds: 120)
        if !data.isEmpty, commandCharacteristic != nil {
            write(data, to: commandCharacteristic)
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard let self,
                      self.shouldBeActive,
                      self.state == .ready,
                      let pendingMessage = self.pendingMessage else { return }
                self.display(pendingMessage)
            }
        } else if let pendingMessage {
            display(pendingMessage)
        }
    }

    private func write(_ data: Data, to characteristic: CBCharacteristic?) {
        guard !data.isEmpty,
              let peripheral,
              let characteristic else { return }
        let type: CBCharacteristicWriteType = characteristic.properties
            .contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        peripheral.writeValue(data, for: characteristic, type: type)
    }

    private func clearConnection() {
        peripheral = nil
        messageCharacteristic = nil
        commandCharacteristic = nil
    }
}

extension Guide01ConnectionManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            connectIfPossible()
        } else if central.state != .unknown && central.state != .resetting {
            state = .bluetoothUnavailable
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let filter = guide01GetScanFilter()
        guard let manufacturerData = advertisementData[
            CBAdvertisementDataManufacturerDataKey
        ] as? Data,
              manufacturerData.count >= 2 else { return }

        let companyID = UInt16(manufacturerData[0])
            | (UInt16(manufacturerData[1]) << 8)
        guard companyID == filter.manufacturerId else { return }
        connect(peripheral)
    }

    func centralManager(
        _ central: CBCentralManager,
        didConnect peripheral: CBPeripheral
    ) {
        peripheral.discoverServices([serviceUUID])
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        clearConnection()
        state = .failed(error?.localizedDescription ?? "接続に失敗しました")
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        clearConnection()
        guard shouldBeActive else {
            state = .idle
            return
        }
        state = .failed(error?.localizedDescription ?? "接続が切れました")
        connectIfPossible()
    }
}

extension Guide01ConnectionManager: CBPeripheralDelegate {
    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverServices error: Error?
    ) {
        guard error == nil, let services = peripheral.services else {
            state = .failed(error?.localizedDescription ?? "サービスを取得できません")
            return
        }
        for service in services {
            peripheral.discoverCharacteristics(
                [messageUUID, commandUUID],
                for: service
            )
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard error == nil, let characteristics = service.characteristics else {
            state = .failed(error?.localizedDescription ?? "表示機能を取得できません")
            return
        }

        for characteristic in characteristics {
            switch characteristic.uuid {
            case messageUUID:
                messageCharacteristic = characteristic
            case commandUUID:
                commandCharacteristic = characteristic
            default:
                break
            }
        }

        guard messageCharacteristic != nil else {
            state = .failed("GUIDE01の表示機能が見つかりません")
            return
        }
        state = .ready
        configureDisplay()
    }
}
