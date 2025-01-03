//  WiFi Utility -> NetworkManager.swift  -->  12/28/24 Devin Sewell

import CoreBluetooth

// MARK: - NetworkManager
class NetworkManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    static let shared = NetworkManager()
    @Published var bluetoothScanning: Bool = true
    @Published var liveUpdatesEnabled: Bool = true
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
    private var centralManager: CBCentralManager! // CoreBluetooth Central
    private var peripherals: [UUID: CBPeripheral] = [:] // CoreBluetooth peripherals array
    private let characteristicWriteHistoryKey = "CharacteristicHistory" // Key to store write history in NSUserDefaults
    private var reconnectionAttempts: [UUID: Int] = [:] // Store reconnection attempts

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: DispatchQueue.main)
        loadWriteHistory() // Load write history from UserDefaults
    }
    
    // Load Characteristic Write History
    func loadWriteHistory() {
        if let savedData = UserDefaults.standard.dictionary(forKey: characteristicWriteHistoryKey) as? [String: [String]] {
            sentValues = savedData.reduce(into: [:]) { $0[CBUUID(string: $1.key)] = $1.value }
        }
    }

    // Save Characteristic Write History
    func saveWriteHistory() {
        let data = sentValues.reduce(into: [:]) { $0[$1.key.uuidString] = $1.value }
        UserDefaults.standard.set(data, forKey: characteristicWriteHistoryKey)
        UserDefaults.standard.synchronize()
    }

    // Clear Characteristic Write History
    func clearWriteHistory(for uuid: CBUUID) {
        log("""
        Clear Write History for: \(uuid)
        """)
        sentValues[uuid] = []
        saveWriteHistory()
    }

    // Start RSSI Updates
    func startRSSIUpdates(interval: TimeInterval = 2.0) {
        stopRSSIUpdates() // Stop any existing timer
        
        // Start a new RSSI update timer
        rssiTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            for device in self.connectedDevices {
                device.peripheral.readRSSI()
            }
        }
        log("""
        Started [RSSI updates] at \(interval)-second intervals.
        """)
    }

    // Stop RSSI Updates
    func stopRSSIUpdates() {
        if rssiTimer != nil{
            rssiTimer?.invalidate()
            rssiTimer = nil
            log("""
            Stopped [RSSI updates].
            """)
        }
    }
    
    // Start Polling Characteristic Updates
    func startCharacteristicPolling(interval: TimeInterval) {
        stopCharacteristicPolling() // Stop any existing timer
        log("""
        Start Polling [\(selectedDevice?.name ?? "Unknown Device")] Characteristics.
        """)
        characteristicPollingTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.pollCharacteristics()
        }
    }

    // Stop Polling Characteristic Updates
    func stopCharacteristicPolling() {
        log("""
        Stop Polling [\(selectedDevice?.name ?? "Unknown Device")] Characteristics.
        """)
        characteristicPollingTimer?.invalidate()
        characteristicPollingTimer = nil
    }
    
    // Poll Characteristic Updates for selectedDevice
    func pollCharacteristics() {
        for device in connectedDevices {
            guard let services = device.peripheral.services else { continue }
            for service in services {
                guard let characteristics = service.characteristics else { continue }
                for characteristic in characteristics {
                    if characteristic.properties.contains(.read) && selectedDevice?.peripheral == device.peripheral{
                        device.peripheral.readValue(for: characteristic)
                    }
                }
            }
        }
        log("""
        Polled all [\(selectedDevice?.name ?? "Unknown Device")] characteristics.
        """)
    }
    
    // Retrieve Connected Devices
    func retrieveConnectedDevices() {
        // Retrieve all Devices from connectedDevices array and append to Discovrered Devices
        for device in connectedDevices {
            if !discoveredDevices.contains(where: { $0.id == device.id }) {
                discoveredDevices.append(device) // Add to discoveredDevices
            }
        }
        // Retrieve all Devices not in connectedDevices but connected to central
        let connectedPeripherals = centralManager.retrieveConnectedPeripherals(withServices: [])
        print("connectedPeripherals",connectedPeripherals.count)
        for peripheral in connectedPeripherals {
            log("peripheral.name: \(peripheral.name)")
            log(" ")
            let device = BluetoothDevice(peripheral: peripheral, advertisementData:  [:], rssi: 0)
            if !discoveredDevices.contains(where: { $0.id == device.id }) {
                discoveredDevices.append(device) // Add to discoveredDevices
            }
        }
    }
    
    // Start Bluetooth Scan
    func startBluetoothScan() {
        guard centralManager.state == .poweredOn else { return }
        log("""
        Starting Bluetooth scan...
        """)
        retrieveConnectedDevices()
        centralManager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }

    // Stop Bluetooth Scan
    func stopBluetoothScan() {
        log("""
        Stopping Bluetooth scan...
        """)
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
            pendingLogs.append(message)
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
        cancelConnectingDevice(device) // Cancel pending connection
        if let index = discoveredDevices.firstIndex(where: { $0.id == device.id }) {
            log("""
            Connecting:
            \(device.name)
            """)
            discoveredDevices[index].status = .connecting
            updateDeviceField(device.peripheral, keyPath: \.status, value: .connecting)
            let peripheral = device.peripheral
            reconnectionAttempts[device.id] = 0 // Reset reconnection attempts
            DispatchQueue.main.async {
                if self.selectedDevice == nil {
                    self.selectedDevice = device
                }
            }
            centralManager.connect(peripheral, options: nil)
        }
    }
    
    // Cancel Pending Peripheral Connection
    func cancelConnectingDevice(_ device: BluetoothDevice) {
        if let index = discoveredDevices.firstIndex(where: { $0.id == device.id }) {
            let peripheral = discoveredDevices[index].peripheral
            centralManager.cancelPeripheralConnection(peripheral)
            discoveredDevices[index].status = .disconnected
            log("""
            Cancelled connecting: \(device.name)
            """)
        }
    }
    
    // Disconnect Peripheral
    func disconnectDevice(_ device: BluetoothDevice) {
        if let index = connectedDevices.firstIndex(where: { $0.id == device.id }) {
            DispatchQueue.main.async {
                let peripheral = self.connectedDevices[index].peripheral
                if self.selectedDevice == self.connectedDevices[index] {
                    // Stop polling if selected device is being disconnected
                    self.stopCharacteristicPolling()
                }
                // Remove from connectedDevices
                self.connectedDevices.remove(at: index)
                self.centralManager.cancelPeripheralConnection(peripheral) // Request disconnection

                // Synchronize status with discoveredDevices
                if let discoveredIndex = self.discoveredDevices.firstIndex(where: { $0.id == device.id }) {
                    self.discoveredDevices[discoveredIndex].status = .disconnected
                }
            }
            log("""
            Device disconnected: [\(device.name)]
            """)
        } else {
            log("""
            Device not found in connectedDevices: [\(device.name)]
            """)
        }
    }
    
    // MARK: - CoreBluetooth -> Bluetooth State Management
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            log("""
            Bluetooth is powered on.
            """)
            startBluetoothScan()
            startRSSIUpdates()
        default:
            log("""
            Bluetooth is unavailable. Clearing devices.
            """)
            stopBluetoothScan()
            discoveredDevices.removeAll()
            connectedDevices.removeAll()
            stopRSSIUpdates()
        }
    }

    // MARK: - CoreBluetooth -> Device Discovery
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let device = BluetoothDevice(peripheral: peripheral, advertisementData: advertisementData, rssi: RSSI)
        if !discoveredDevices.contains(where: { $0.id == device.id }) {
            discoveredDevices.append(device)
            peripherals[peripheral.identifier] = peripheral
            peripheral.delegate = self
            log("""
            Discovered:
            \(device.name) [RSSI: \(RSSI)]
            """)
        }
    }
    
    // MARK: - CoreBluetooth -> didConnect to Peripheral
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        if let index = discoveredDevices.firstIndex(where: { $0.peripheral == peripheral }) {
            discoveredDevices[index].status = .connected
            updateDeviceField(peripheral, keyPath: \.status, value: discoveredDevices[index].status)
            peripheral.delegate = self
            if !connectedDevices.contains(where: { $0.peripheral == peripheral }) {
                if let connectedDevice = discoveredDevices.first(where: { $0.peripheral == peripheral }) {
                    connectedDevices.append(connectedDevice)
                    log("""
                    Connected:
                    \(connectedDevice.name)
                    """)
                }
            }
            peripheral.discoverServices(nil) // Start discovering services
        }
    }
    
    // MARK: - CoreBluetooth -> didReadRSSI
    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        if let index = connectedDevices.firstIndex(where: { $0.peripheral == peripheral }) {
            DispatchQueue.main.async {
                self.connectedDevices[index].rssi = RSSI
            }
        }
    }
    
    // MARK: - CoreBluetooth -> didWriteValueFor Peripheral Characteristic
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard
            let userDescriptionDescriptor = characteristic.descriptors?.first(where: { $0.uuid == CBUUID(string: "2901") }),
            let userDescription = getDescriptorValue(for: characteristic, descriptor: userDescriptionDescriptor)
        else {
            return // If either the 0x2901 descriptor or the value is nil, return.
        }
        if let error = error {
            log("""
            \(peripheral.name ?? "Unknown Device")
            Error Writing to Device:
            \(userDescription)
            [\(characteristic.uuid)]
            <\(error.localizedDescription)>
            """)
            return
        }
        
        log("""
        \(peripheral.name ?? "Unknown Device")
        Successfully Wrote to Characteristic:
        \(userDescription)
        [\(characteristic.uuid)]
        """)
    }

    // MARK: - CoreBluetooth -> didDiscoverDescriptorsFor Peripheral Characteristic Descriptor
    func peripheral(_ peripheral: CBPeripheral, didDiscoverDescriptorsFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            log("""
            Error discovering descriptors for:
            <\(characteristic.uuid)>
            <\(error.localizedDescription)>
            """)
            return
        }
        guard characteristic.descriptors != nil else {
            log("""
            <No descriptors found for \(characteristic.uuid)>
            """)
            return
        }
        log("""
        Discovered Descriptors for:
        \(characteristic.uuid)
        """)
        guard let descriptors = characteristic.descriptors else { return }
        
        let charKey = "\(String(describing: characteristic.service?.uuid))___\(characteristic.uuid)"
        guard !discoveredDescriptors.contains(charKey) else {
            return // Already discovered -> skip
        }
        discoveredDescriptors.insert(charKey)
        
        for descriptor in descriptors { // Read descriptors
            peripheral.readValue(for: descriptor)
        }
    }
    
    // MARK: - CoreBluetooth -> didUpdateValueFor Peripheral Characteristic Descriptor
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor descriptor: CBDescriptor, error: Error?){
        if let error = error {
            log("""
            Error reading descriptor:
            [\(descriptor.uuid)]
            <\(error.localizedDescription)>
            """)
            return
        }

        guard let c = descriptor.characteristic else {
            return // No characteristic –> skip
        }

        guard descriptor.uuid == CBUUID(string: "2901") else {
            return // It's another descriptor –> skip
        }

        let descriptorKey = "\(c.uuid.uuidString)_\(descriptor.uuid)"
        if descriptorValues[descriptorKey] != nil {
            return // Already cached –> skip
        }

        if let value = descriptor.value as? String {
            descriptorValues[descriptorKey] = value
            log("""
            Descriptor Value Updated:
            [\(c.uuid)]
            [\(descriptor.uuid)]
            Value:
            \(value)
            """)
        }
    }

    // MARK: - CoreBluetooth -> didUpdateValueFor Peripheral Characteristic
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if characteristicPollingTimer == nil {
            return // Disregaurd Characteristic Update if not polling updates
        }
        guard
            let userDescriptionDescriptor = characteristic.descriptors?.first(where: { $0.uuid == CBUUID(string: "2901") }),
            let userDescription = getDescriptorValue(for: characteristic, descriptor: userDescriptionDescriptor)
        else {
            return // If either the 0x2901 descriptor or the value is nil, return.
        }
        if let error = error {
            log("""
            \(peripheral.name ?? "Unknown Device")
            Error reading characteristic:
            \(userDescription)
            [\(characteristic.uuid)]
            <\(error.localizedDescription)>
            """)
            return
        }

        // Make sure there's a value
        guard let newValue = characteristic.value else {
            log("""
            \(peripheral.name ?? "Unknown Device")
            <Characteristic \(characteristic.uuid) has no value.>
            """)
            return
        }
        
        // Compare with the last known value
        let lastValue = lastCharacteristicValues[characteristic.uuid]
        if lastValue == newValue {
            return // The value hasn't changed -> skip
        } else {
            // The value has changed –> update dictionary & log it
            lastCharacteristicValues[characteristic.uuid] = newValue

            let valueString = newValue.map { String(format: "%02X", $0) }.joined(separator: " ")
            
            log("""
            \(peripheral.name ?? "Unknown Device")
            Characteristic Updated:
            \(userDescription)
            [\(characteristic.uuid)]
            Value:
            \(valueString)
            """)
        }
    }

    // MARK: - CoreBluetooth -> didDisconnectPeripheral
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if let index = connectedDevices.firstIndex(where: { $0.peripheral == peripheral }) {
            connectedDevices[index].status = .disconnected
            log("""
            Disconnected:
            [\(connectedDevices[index].name)]
            Retrying connection...
            """)
            
            // Retry logic
            let peripheralID = peripheral.identifier
            let attempts = reconnectionAttempts[peripheralID, default: 0]
            
            if attempts < 3 {
                reconnectionAttempts[peripheralID] = attempts + 1
                centralManager.connect(peripheral, options: nil)
            } else {
                log("""
                Max reconnection attempts reached:
                [\(connectedDevices[index].name) ]
                """)
                reconnectionAttempts[peripheralID] = nil // Clear attempts
            }
        } else {
            log("""
            ----------------------------------------
            Disconnected:
            [\(peripheral.name ?? "Unknown Device")]
            """)
        }
    }

    // MARK: - CoreBluetooth -> didDiscoverServices for Peripheral
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service) // Discover all characteristics for the service
        }
        log("""
        ----------------------------------------
        Discovered Services:
        [\(peripheral.name ?? "Unknown Device")]
        Discovered \(services.count) services
        """)
    }

    // MARK: - CoreBluetooth -> didDiscoverCharacteristicsFor for Peripheral
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            log("""
            Error discovering characteristics:
            \(error.localizedDescription)
            """)
            return
        }
        guard let characteristics = service.characteristics else {
            log("""
            No characteristics found for service:
            \(service.uuid)
            """)
            return
        }
        log("""
        ----------------------------------------
        Discovered Characteristics for Services:
        [\(service.uuid)]
        \(peripheral.name ?? "Unknown Device")
        """)
        for characteristic in characteristics {
            log("""
            ----------------------------------------
            \(peripheral.name ?? "Unknown Device")
            Read Characteristic:
            [\(characteristic.uuid)]
            Properties:
            [\(characteristic.properties)]
            """)
            if characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate) {
                log("""
                \(peripheral.name ?? "Unknown Device")
                Subscribing to notifications for:
                [\(characteristic.uuid)]
                """)
                peripheral.setNotifyValue(true, for: characteristic)
            }
            if characteristic.properties.contains(.read) {
                log("""
                \(peripheral.name ?? "Unknown Device")
                Reading initial value for:
                [\(characteristic.uuid)]
                """)
                peripheral.readValue(for: characteristic)
            }
            if !discoveredDescriptors.contains(characteristic.uuid.uuidString) {
                peripheral.discoverDescriptors(for: characteristic) // Discover descriptors
            }
        }
    }
    
    // MARK: - CoreBluetooth -> Write Data to Peripheral(s)
    func writeDataToBLE(characteristic: CBCharacteristic, data: Data, devices: [BluetoothDevice]) {
        for device in devices {
            device.peripheral.writeValue(data, for: characteristic, type: .withResponse)
            
            // Format the sent data as a readable hex string
            let dataBytes = data.map { String(format: "%02X", $0) }.joined(separator: " ")
            
            // Store the value in the recent list (limit to 10)
            let characteristicUUID = characteristic.uuid
            if sentValues[characteristicUUID] == nil {
                sentValues[characteristicUUID] = []
            }
            sentValues[characteristicUUID]?.append(dataBytes)
            if let count = sentValues[characteristicUUID]?.count, count > 10 {
                sentValues[characteristicUUID]?.removeFirst(count - 10) // Limit to 10 values
            }
            
            // Log the Write action
            log("""
            ----------------------------------------
            Writing data to:
            \(device.name)
            [Characteristic: \(characteristicUUID)]
            Value:
            \(data.map { String(format: "%02X", $0) }.joined(separator: " "))
            """)
        }
        saveWriteHistory() // Add the data to history for the characteristic
    }
}
