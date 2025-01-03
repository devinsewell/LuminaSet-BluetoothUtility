//  WiFi Utility -> Extensions.swift  -->  12/28/24 Devin Sewell

import CoreBluetooth

// MARK: - Extensions

// Extension for NetworkManager
extension NetworkManager {
    func totalCharacteristicsCount(for device: BluetoothDevice) -> Int {
        guard let services = device.peripheral?.services else { return 0 }
        return services.flatMap { $0.characteristics ?? [] }.count
    }
    /// Updates a field on a `BluetoothDevice` object and notifies the UI.
    /// - Parameters:
    ///   - peripheral: The peripheral associated with the device to update.
    ///   - keyPath: The keyPath of the property to update.
    ///   - value: The new value to assign to the property.
    func updateDeviceField<T>(_ peripheral: CBPeripheral?, keyPath: WritableKeyPath<BluetoothDevice, T>, value: T) {
        guard let peripheral = peripheral else { return }
        if let index = connectedDevices.firstIndex(where: { $0.peripheral == peripheral }) {
            DispatchQueue.main.async {
                self.connectedDevices[index][keyPath: keyPath] = value
            }
        } else if let index = discoveredDevices.firstIndex(where: { $0.peripheral == peripheral }) {
            DispatchQueue.main.async {
                self.discoveredDevices[index][keyPath: keyPath] = value
            }
        }
    }
}

// Extension for BluetoothDevice
extension BluetoothDevice {
    func hasBatteryLevelCharacteristic() -> Bool {
        guard let services = peripheral?.services else { return false }
        for service in services {
            if let characteristics = service.characteristics {
                if characteristics.contains(where: { $0.uuid == CBUUID(string: "2A19") }) {
                    return true
                }
            }
        }
        return false
    }
}

// Extension for CB Characteristic Write Properties
extension CBCharacteristicProperties {
    var description: String {
        var properties: [String] = []
        if contains(.read) { properties.append("Read") }
        if contains(.write) { properties.append("Write") }
        if contains(.notify) { properties.append("Notify") }
        if contains(.indicate) { properties.append("Indicate") }
        if contains(.writeWithoutResponse) { properties.append("Write Without Response") }
        if contains(.authenticatedSignedWrites) { properties.append("Authenticated Signed Writes") }
        if contains(.extendedProperties) { properties.append("Extended Properties") }
        return properties.joined(separator: ", ")
    }
}

// Extension for String -> Hex Chunking
extension String {
    func chunked(by size: Int) -> [String] {
        stride(from: 0, to: count, by: size).map {
            let start = index(startIndex, offsetBy: $0)
            let end = index(start, offsetBy: size, limitedBy: endIndex) ?? endIndex
            return String(self[start..<end])
        }
    }
}
