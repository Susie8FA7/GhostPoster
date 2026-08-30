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
    private var gifTextDisplayCharacteristic: CBCharacteristic?
    private var shouldBeActive = false
    private var pendingMessage: Guide01StatusMessage?
    private var scrollingTask: Task<Void, Never>?
    private var keepAliveTask: Task<Void, Never>?

    private let serviceUUID = CBUUID(string: Guide01UUIDs.service)
    private let messageUUID = CBUUID(string: Guide01UUIDs.msgNotify)
    private let commandUUID = CBUUID(string: Guide01UUIDs.cmd)
    private let gifTextDisplayUUID = CBUUID(string: Guide01UUIDs.gifTextDisplay)

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
        scrollingTask?.cancel()
        scrollingTask = nil
        keepAliveTask?.cancel()
        keepAliveTask = nil
        central.stopScan()
        pendingMessage = nil
        if let peripheral {
            if gifTextDisplayCharacteristic != nil {
                write(guide01GifTextClosePage(), to: gifTextDisplayCharacteristic)
                Task { @MainActor [weak self, weak peripheral] in
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    guard let self, let peripheral else { return }
                    self.central.cancelPeripheralConnection(peripheral)
                }
            } else {
                central.cancelPeripheralConnection(peripheral)
            }
        } else {
            state = .idle
        }
    }

    func retry() {
        guard shouldBeActive else { return }
        scrollingTask?.cancel()
        scrollingTask = nil
        keepAliveTask?.cancel()
        keepAliveTask = nil
        if let peripheral {
            central.cancelPeripheralConnection(peripheral)
        }
        clearConnection()
        connectIfPossible()
    }

    func display(_ message: Guide01StatusMessage) {
        scrollingTask?.cancel()
        scrollingTask = nil
        keepAliveTask?.cancel()
        keepAliveTask = nil
        displayImmediately(message)
    }

    func displayKeepingAlive(_ message: Guide01StatusMessage) {
        scrollingTask?.cancel()
        scrollingTask = nil
        keepAliveTask?.cancel()
        displayImmediately(message)

        keepAliveTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled, let self else { return }
                self.displayImmediately(message)
            }
        }
    }

    func displayScrolling(
        _ message: Guide01StatusMessage,
        completionMessage: Guide01StatusMessage? = nil
    ) {
        scrollingTask?.cancel()
        keepAliveTask?.cancel()
        keepAliveTask = nil

        let messages = Guide01StatusPresenter.scrollingMessages(for: message)
        displayImmediately(messages[0], usesExplicitLineLayout: true)
        guard messages.count > 1 || completionMessage != nil else {
            scrollingTask = nil
            return
        }

        scrollingTask = Task { @MainActor [weak self] in
            guard let self else { return }

            for message in messages.dropFirst() {
                try? await Task.sleep(for: .milliseconds(2_400))
                guard !Task.isCancelled else { return }
                self.displayImmediately(message, usesExplicitLineLayout: true)
            }
            if let completionMessage {
                try? await Task.sleep(for: .milliseconds(2_400))
                guard !Task.isCancelled else { return }
                self.displayImmediately(completionMessage)
                self.scrollingTask = nil
            } else {
                self.scrollingTask = nil
            }
        }
    }

    private func displayImmediately(
        _ message: Guide01StatusMessage,
        usesExplicitLineLayout: Bool = false
    ) {
        pendingMessage = message
        guard state == .ready else { return }

        if gifTextDisplayCharacteristic != nil {
            let items = usesExplicitLineLayout
                ? explicitLineItems(for: message)
                : [Guide01DisplayItem(
                    layerId: 0,
                    type: Guide01GifText.elementTypeText,
                    x: Guide01GifText.posCenter,
                    y: Guide01GifText.posCenter,
                    fontSize: message.fontSize,
                    text: message.displayText
                )]
            let data = guide01GifTextDisplayElements(
                showStatusBar: message.showsStatusBar,
                items: items
            )
            if !data.isEmpty {
                write(data, to: gifTextDisplayCharacteristic)
                return
            }
        }

        // Read-aloud content must never be sent through the notification area.
        guard !usesExplicitLineLayout else { return }

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

    private func explicitLineItems(
        for message: Guide01StatusMessage
    ) -> [Guide01DisplayItem] {
        let lines = message.displayText
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        let lineHeight = Int(message.fontSize) + 8
        let totalHeight = lines.count * lineHeight
        let firstY = max(0, (Int(Guide01GifText.contentHeight) - totalHeight) / 2)

        return lines.enumerated().map { index, line in
            let isHighlighted = !line.isEmpty
                && message.highlightedTextFragments.contains { fragment in
                    fragment.contains(line)
                }
            return Guide01DisplayItem(
                layerId: UInt8(index),
                type: Guide01GifText.elementTypeText,
                x: Guide01GifText.posCenter,
                y: UInt16(firstY + index * lineHeight),
                fontSize: message.fontSize,
                colorR: 255,
                colorG: isHighlighted ? 210 : 255,
                colorB: isHighlighted ? 0 : 255,
                text: line.isEmpty ? " " : line
            )
        }
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
        if gifTextDisplayCharacteristic != nil {
            if let pendingMessage {
                displayImmediately(pendingMessage)
            }
            return
        }

        let data = guide01NotificationDisplayTime(seconds: 120)
        if !data.isEmpty, commandCharacteristic != nil {
            write(data, to: commandCharacteristic)
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard let self,
                      self.shouldBeActive,
                      self.state == .ready,
                      let pendingMessage = self.pendingMessage else { return }
                self.displayImmediately(pendingMessage)
            }
        } else if let pendingMessage {
            displayImmediately(pendingMessage)
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
        gifTextDisplayCharacteristic = nil
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
                [messageUUID, commandUUID, gifTextDisplayUUID],
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
            case gifTextDisplayUUID:
                gifTextDisplayCharacteristic = characteristic
            default:
                break
            }
        }

        guard gifTextDisplayCharacteristic != nil
                || messageCharacteristic != nil else {
            state = .failed("GUIDE01の表示機能が見つかりません")
            return
        }
        state = .ready
        configureDisplay()
    }
}
