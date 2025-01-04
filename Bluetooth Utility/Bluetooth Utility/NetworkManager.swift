//  WiFi Utility -> NetworkManager.swift  -->  12/28/24 Devin Sewell

import CoreBluetooth

// MARK: - NetworkManager
class NetworkManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    static let shared = NetworkManager()
    @Published var bluetoothScanning: Bool = true // is actively scanning nearby bluetooth devices
    @Published var liveUpdatesEnabled: Bool = true // is polling Selected Device Characteristics at interval
    @Published var consoleLogs: [String] = [] // Console output for logs
    @Published var selectedDevice: BluetoothDevice? // Tracks the selected device
    @Published var discoveredDevices: [BluetoothDevice] = []
    @Published var connectedDevices: [BluetoothDevice] = []
    @Published var sentValues: [CBUUID: [String]] = [:] // Recent values sent to each characteristic
    @Published var textInputs: [CBUUID: String] = [:] // Track text inputs for each characteristic
    private var lastCharacteristicValues: [CBUUID: Data] = [:] // Track Characteristic updates, to prevent repeat polling
    private var characteristicPollingTimer: Timer? // Characteristic Polling Timer
    private var rssiTimer: Timer? // RSSI Polling Timer
    private var descriptorValues: [String: String] = [:] // Store Descriptor Values to avoid duplicate reads
    private var discoveredDescriptors = Set<String>()  // Store Discovered Descriptor Values to avoid duplicate reads
    @Published var bluetoothState: CBManagerState = .unknown
    private var centralManager: CBCentralManager! // CoreBluetooth Central
    private var peripherals: [UUID: CBPeripheral] = [:] // CoreBluetooth peripherals array
    private let characteristicWriteHistoryKey = "CharacteristicHistory" // Key to store write history in NSUserDefaults
    private var reconnectionAttempts: [UUID: Int] = [:] // Store reconnection attempts

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: DispatchQueue.main)
    }
    
    // Load Characteristic Write History
    func loadCharacteristicWriteHistory() {
        sentValues = (UserDefaults.standard.dictionary(forKey: characteristicWriteHistoryKey) as? [String: [String]] ?? [:])
            .reduce(into: [:]) { $0[CBUUID(string: $1.key)] = $1.value }
    }

    // Save Characteristic Write History
    func saveWriteHistory() {
        let data = sentValues.reduce(into: [:]) { $0[$1.key.uuidString] = $1.value }
        UserDefaults.standard.set(data, forKey: characteristicWriteHistoryKey)
        UserDefaults.standard.synchronize()
    }

    // Clear Characteristic Write History
    func clearWriteHistory(for uuid: CBUUID) {
        log("Clear Write History for: \(uuid)")
        sentValues[uuid] = []
        saveWriteHistory()
    }

    // Start RSSI Updates
    func startRSSIUpdates(interval: TimeInterval = 2.0) {
        stopRSSIUpdates()
        rssiTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.connectedDevices.forEach { $0.peripheral?.readRSSI() }
        }
        log("Started [RSSI updates]at \(interval)-second intervals.")
    }

    // Stop RSSI Updates
    func stopRSSIUpdates() {
        if rssiTimer != nil{
            rssiTimer?.invalidate()
            rssiTimer = nil
            log("Stopped [RSSI updates]")
        }
    }
    
    // Start Polling Characteristic Updates
    func startCharacteristicPolling(interval: TimeInterval) {
        stopCharacteristicPolling() // Stop any existing timer
        log("\(selectedDevice?.name ?? "Unknown Device") [Start Polling Characteristics]")
        characteristicPollingTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.pollCharacteristics()
        }
    }

    // Stop Polling Characteristic Updates
    func stopCharacteristicPolling() {
        log("\(selectedDevice?.name ?? "Unknown Device")[Stop Polling Characteristics]")
        characteristicPollingTimer?.invalidate()
        characteristicPollingTimer = nil
    }

    // Poll Characteristic Updates for selectedDevice
    func pollCharacteristics() {
        guard let selectedDevice = selectedDevice else { return stopCharacteristicPolling() }
        connectedDevices.forEach { device in
            device.peripheral?.services?.forEach { service in
                service.characteristics?.filter { $0.properties.contains(.read) && device.peripheral == selectedDevice.peripheral }
                    .forEach { device.peripheral?.readValue(for: $0) }
            }
        }
        log("\(selectedDevice.name)[Finished reading characteristics]")
    }
    
    // Retrieve Connected Devices
    func retrieveConnectedDevices() {
        // Retrieve all Devices from connectedDevices array and append to Discovered Devices
        connectedDevices.forEach { device in
            if !discoveredDevices.contains(where: { $0.id == device.id }) {
                discoveredDevices.append(device)
            }
        }
        // Retrieve all Devices not in connectedDevices but connected to central
        centralManager.retrieveConnectedPeripherals(withServices: []).forEach { peripheral in
            let device = BluetoothDevice(peripheral: peripheral, advertisementData: [:], rssi: 0, status: .connected)
            connectedDevices.append(device)
            connectToDevice(device)
        }
    }
    
    // Start Bluetooth Scan
    func startBluetoothScan() {
        guard centralManager.state == .poweredOn else { return }
        log("Starting Bluetooth scan...")
        retrieveConnectedDevices()
        centralManager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }

    // Stop Bluetooth Scan
    func stopBluetoothScan() {
        log("Stopping Bluetooth scan...")
        centralManager.stopScan()
    }
    
    // Console Log -> Flush Pending Logs for better performance
    private func flushPendingLogs() {
        DispatchQueue.main.async {
            self.consoleLogs.append(contentsOf: pendingLogs)
            pendingLogs.removeAll()
            if self.consoleLogs.count > logMessageLimit {
                self.consoleLogs.removeFirst(self.consoleLogs.count - logMessageLimit)
            }
        }
    }
    
    // Console Log -> Add Console Log Item
    func log(_ message: String) {
        logUpdateQueue.async {
            let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
            pendingLogs.append("--------------------------------------\n[\(timestamp)]\n\(message)")
            if pendingLogs.count == 1 {
                DispatchQueue.main.asyncAfter(deadline: .now() + logBatchInterval) {
                    self.flushPendingLogs()
                }
            }
        }
    }
    
    // Check if Characteristic Descriptor is read to prevent redundent polling
    func isDescriptorRead(descriptor: CBDescriptor, characteristic: CBCharacteristic) -> Bool {
        let key = getDescriptorKey(characteristic: characteristic, descriptor: descriptor)
        return descriptorValues[key] != nil
    }
    
    // Retrieve cached Characteristic Descriptor Value if exists
    func getDescriptorValue(for characteristic: CBCharacteristic, descriptor: CBDescriptor) -> String? {
        let key = getDescriptorKey(characteristic: characteristic, descriptor: descriptor)
        if let cachedValue = descriptorValues[key] {
            return cachedValue
        }
        return nil
    }

    // Retrieve Characteristic Descriptor Key
    private func getDescriptorKey(characteristic: CBCharacteristic, descriptor: CBDescriptor) -> String {
        return "\(characteristic.uuid.uuidString)_\(descriptor.uuid)"
    }
    
    // Read Characteristic Descriptor
    func readDescriptorValue(descriptor: CBDescriptor) {
        descriptor.characteristic?.service?.peripheral?.readValue(for: descriptor)
    }
    
    // Retrieve Cached Characteristic Descriptor
    func getCharacteristicValue(_ characteristic: CBCharacteristic) -> String? {
        guard let value = characteristic.value else { return nil }
        return value.map { String(format: "%02x", $0) }.joined()
    }
    
    // Connect to Device
    func connectToDevice(_ device: BluetoothDevice) {
        cancelConnectingDevice(device) // Cancel any pending connection
        if let index = discoveredDevices.firstIndex(where: { $0.id == device.id }) {
            log("Connecting:[\(device.name)]")
            discoveredDevices[index].status = .connecting
            updateDeviceField(device.peripheral, keyPath: \.status, value: .connecting)
            if let peripheral = device.peripheral {
                // Real device connection
                reconnectionAttempts[device.id] = 0 // Reset reconnection attempts
                DispatchQueue.main.async {
                    if self.selectedDevice == nil {
                        self.selectedDevice = device
                    }
                }
                centralManager.connect(peripheral, options: nil)
            }
        }
    }
    
    // Cancel Pending Peripheral Connection
    func cancelConnectingDevice(_ device: BluetoothDevice) {
        if let index = discoveredDevices.firstIndex(where: { $0.id == device.id }) {
            if let peripheral = discoveredDevices[index].peripheral{
                centralManager.cancelPeripheralConnection(peripheral)
            }
            discoveredDevices[index].status = .disconnected
            log("Cancelled connecting: \(device.name)")
        }
    }
    
    // Disconnect Peripheral
    func disconnectDevice(_ device: BluetoothDevice) {
        guard let connectedDevice = connectedDevices.first(where: { $0.id == device.id }) else {
           // log("Device not found in connectedDevices: [\(device.name)]")
            return
        }
        
        DispatchQueue.main.async {
            if let peripheral = connectedDevice.peripheral {
                self.updateDeviceStatus(for: peripheral, status: .disconnected)
                self.centralManager.cancelPeripheralConnection(peripheral)
                self.connectedDevices.removeAll { $0.id == device.id }
            }
            self.log("Device Disconnected:\n[\(device.name)]")
        }
    }
    
    // Synchronize Device Status for discoveredDevices, connectedDevices, and selectedDevice
    func synchronizeDeviceStatus() {
        discoveredDevices.forEach { device in
            device.status = connectedDevices.contains(device) ? .connected : .disconnected
            if device == selectedDevice {
                selectedDevice?.status = device.status
            }
        }
    }
    
    // Update device.status in discoveredDevices and connectedDevices
    func updateDeviceStatus(for peripheral: CBPeripheral, status: ConnectionStatus) {
        [discoveredDevices, connectedDevices].forEach { devices in
            // Update Device status in discoveredDevices and connectedDevices
            devices.firstIndex(where: { $0.peripheral == peripheral }).map { devices[$0].status = status }
        }
        // Add to connectedDevices if .connected, update discoveredDevice status
        if let discoveredDevice = discoveredDevices.first(where: { $0.peripheral == peripheral }),
           !connectedDevices.contains(where: { $0.peripheral == peripheral }) {
            if status == .connected { connectedDevices.append(discoveredDevice) }
            discoveredDevice.status = status

        }
        // Update selectedDevice status
        selectedDevice?.peripheral == peripheral ? (selectedDevice?.status = status) : nil
    }
    
    // MARK: - CoreBluetooth -> Bluetooth State Management
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            log("Bluetooth is powered on.")
            startBluetoothScan()
            startRSSIUpdates()
        default:
            log("Bluetooth is unavailable. Clearing devices.")
            stopBluetoothScan()
            discoveredDevices.removeAll()
            connectedDevices.removeAll()
            stopRSSIUpdates()
        }
    }

    // MARK: - CoreBluetooth -> Device Discovery
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard !discoveredDevices.contains(where: { $0.id == peripheral.identifier }) else { return }
        let device = BluetoothDevice(peripheral: peripheral, advertisementData: advertisementData, rssi: RSSI)
        discoveredDevices.append(device)
        peripherals[peripheral.identifier] = peripheral
        peripheral.delegate = self
        log("Discovered: \(device.name) [RSSI: \(RSSI)]")
    }
    
    // MARK: - CoreBluetooth -> didConnect to Peripheral
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        updateDeviceStatus(for: peripheral, status: .connected)
        peripheral.delegate = self // Set the delegate for the connected peripheral
        connectedDevices.first(where: { $0.peripheral == peripheral }).map { log("Connected:\($0.name)") }
        peripheral.discoverServices(nil) // Start discovering services
    }
    
    // MARK: - CoreBluetooth -> didReadRSSI
    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        guard error == nil, let _ = connectedDevices.firstIndex(where: { $0.peripheral == peripheral }) else { return }
        DispatchQueue.main.async {self.connectedDevices.first(where: { $0.peripheral == peripheral })?.rssi = RSSI}
    }
    
    // MARK: - CoreBluetooth -> didWriteValueFor Peripheral Characteristic
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        let userDescription = characteristic.descriptors?
            .first(where: { $0.uuid == CBUUID(string: "2901") })
            .flatMap { getDescriptorValue(for: characteristic, descriptor: $0) } ?? "Unknown"

        log("""
        \(peripheral.name ?? "Unknown Device")
        \(error != nil ? "Error Writing to Device:" : "Successfully Wrote to Characteristic:")
        \(userDescription)
        [\(characteristic.uuid)]
        \(error?.localizedDescription ?? "")
        """)
    }

    // MARK: - CoreBluetooth -> didDiscoverDescriptorsFor Peripheral Characteristic Descriptor
    func peripheral(_ peripheral: CBPeripheral, didDiscoverDescriptorsFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            log("Error discovering descriptors for: <\(characteristic.uuid)><\(error.localizedDescription)>")
            return
        }

        guard let descriptors = characteristic.descriptors, !descriptors.isEmpty else { return }

        log("Discovered Descriptors for: [\(characteristic.uuid)]")

        // Populate discoveredDescriptors
        descriptors.forEach { descriptor in
            let descriptorKey = "\(characteristic.uuid.uuidString)_\(descriptor.uuid)"
            // Only proceed if it's not already cached
            if discoveredDescriptors.insert(descriptorKey).inserted { peripheral.readValue(for: descriptor) }
        }
    }
    
    // MARK: - CoreBluetooth -> didUpdateValueFor Peripheral Characteristic Descriptor
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor descriptor: CBDescriptor, error: Error?) {
        if let error = error {
            log("Error reading descriptor: [\(descriptor.uuid)]<\(error.localizedDescription)>")
            return
        }

        guard
            let characteristic = descriptor.characteristic,
            descriptor.uuid == CBUUID(string: "2901"),
            descriptorValues["\(characteristic.uuid.uuidString)_\(descriptor.uuid)"] == nil,
            let value = descriptor.value as? String
        else { return }

        descriptorValues["\(characteristic.uuid.uuidString)_\(descriptor.uuid)"] = value
        log("Descriptor Value Updated: [\(characteristic.uuid)][\(descriptor.uuid)]Value:\(value)")
    }

    // MARK: - CoreBluetooth -> didUpdateValueFor Peripheral Characteristic
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristicPollingTimer != nil else { return } // Ignore updates if not polling

        if let error = error {
            let descriptor = characteristic.descriptors?.first(where: { $0.uuid == CBUUID(string: "2901") })
            let userDescription = descriptor.flatMap { getDescriptorValue(for: characteristic, descriptor: $0) } ?? "Unknown"
            log("\(peripheral.name ?? "Unknown Device") Error reading characteristic: \(userDescription) [\(characteristic.uuid)] <\(error.localizedDescription)>")
            return
        }

        guard let descriptor = characteristic.descriptors?.first(where: { $0.uuid == CBUUID(string: "2901") }),
        let userDescription = getDescriptorValue(for: characteristic, descriptor: descriptor),
        let newValue = characteristic.value else { return }

        if lastCharacteristicValues[characteristic.uuid] != newValue {
            lastCharacteristicValues[characteristic.uuid] = newValue
            log("\(peripheral.name ?? "Unknown Device") [Characteristic Updated]\(userDescription)[\(characteristic.uuid)]Value:\(newValue.map { String(format: "%02X", $0) }.joined(separator: " "))")
        }
    }

    // MARK: - CoreBluetooth -> didDisconnectPeripheral
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        updateDeviceStatus(for: peripheral, status: .disconnected)
        log("Disconnected: [\(peripheral.name ?? "Unknown Device")]")
    }

    // MARK: - CoreBluetooth -> didDiscoverServices for Peripheral
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        // Discover all characteristics for the service
        services.forEach { peripheral.discoverCharacteristics(nil, for: $0) }
        log("Discovered Services: [\(peripheral.name ?? "Unknown Device")]\(services.count) services found.")
    }

    // MARK: - CoreBluetooth -> didDiscoverCharacteristicsFor for Peripheral
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error { return log("Error discovering characteristics: \(error.localizedDescription)") }
        guard let characteristics = service.characteristics else { return log("No characteristics found for service: \(service.uuid)") }
        log("Discovered Characteristics for Services: [\(service.uuid)] \(peripheral.name ?? "Unknown Device")")
        characteristics.forEach { characteristic in
            log("\(peripheral.name ?? "Unknown Device") Read Characteristic: [\(characteristic.uuid)]Properties: [\(characteristic.properties)]")
            if characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate) {
                log("\(peripheral.name ?? "Unknown Device") Subscribing to notifications for: [\(characteristic.uuid)]")
                peripheral.setNotifyValue(true, for: characteristic)
            }
            if characteristic.properties.contains(.read) {
                log("\(peripheral.name ?? "Unknown Device") Reading initial value for: [\(characteristic.uuid)]")
                peripheral.readValue(for: characteristic)
            }
            if !discoveredDescriptors.contains(characteristic.uuid.uuidString) {
                peripheral.discoverDescriptors(for: characteristic)
            }
        }
    }

    // MARK: - CoreBluetooth -> Write Data to Peripheral(s)
    func writeDataToBLE(characteristic: CBCharacteristic, data: Data, devices: [BluetoothDevice]) {
        devices.compactMap { $0.peripheral }.forEach { peripheral in
            peripheral.writeValue(data, for: characteristic, type: .withResponse)
            let dataBytes = data.map { String(format: "%02X", $0) }.joined(separator: " ")
            let characteristicUUID = characteristic.uuid
            sentValues[characteristicUUID, default: []].append(dataBytes)
            sentValues[characteristicUUID]?.removeFirst(max(0, sentValues[characteristicUUID]!.count - 10))
            log("Writing data to: \(devices.first { $0.peripheral == peripheral }?.name ?? "Unknown Device") [Characteristic: \(characteristicUUID)]Value:\(dataBytes)")
        }
        saveWriteHistory()
    }
}
