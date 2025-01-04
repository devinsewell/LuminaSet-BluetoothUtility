//  WiFi Utility -> BluetoothDevice.swift  -->  12/28/24 Devin Sewell

import CoreBluetooth

// GATT Service Name Table
let gattServiceNames: [String: String] = [
    "180A": "Device Information",
    "180F": "Battery Service",
    "180D": "Heart Rate",
    "1802": "Immediate Alert",
    "1810": "Blood Pressure",
    "181C": "User Data"
]

// GATT Characteristic Name Table
let gattCharacteristicNames: [String: String] = [
    "2A19": "Battery Level",
    "2A29": "Manufacturer Name String",
    "2A24": "Model Number String",
    "2A25": "Serial Number String",
    "2A26": "Firmware Revision String",
    "2A27": "Hardware Revision String"
]

// BluetoothDevice Connection Status
enum ConnectionStatus {
    case disconnected
    case connecting
    case connected
}

// MARK: - BluetoothDevice
class BluetoothDevice: ObservableObject, Identifiable, Equatable {
    let peripheral: CBPeripheral?
    let advertisementData: [String: Any]
    @Published var rssi: NSNumber
    @Published var status: ConnectionStatus
    @Published var batteryLevel: Int?

    // Computed property for Identifiable protocol
    var id: UUID {
        return peripheral?.identifier ?? UUID(uuidString: "00000000-DDDD-EEEE-3333-000000000000")!
    }

    // Initializer
    init(peripheral: CBPeripheral? = nil, advertisementData: [String: Any], rssi: NSNumber, status: ConnectionStatus = .disconnected) {
        self.peripheral = peripheral
        self.advertisementData = advertisementData
        self.rssi = rssi
        self.status = status
        self.batteryLevel = nil // Initialize as nil
    }
    
    // Default device instance
    static let defaultDevice = BluetoothDevice(
        peripheral: nil,
        advertisementData: ["CBAdvertisementDataLocalNameKey": "LuminaSet Demo"],
        rssi: 0,
        status: .connected
    )

    // Equatable protocol
    static func == (lhs: BluetoothDevice, rhs: BluetoothDevice) -> Bool {
        return lhs.id == rhs.id
    }
    
    // Device name with fallback to "Unknown Device"
    var name: String {
        peripheral?.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "Unknown Device"
    }
    
    // Extract model name from advertisement data
    var model: String {
        let rawModel = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "Unknown Model"
        // Filter to allow only alphanumeric characters and spaces
        return rawModel.filter { $0.isLetter || $0.isNumber || $0.isWhitespace }
    }
    
    // Manufacturer name extracted from advertisement data
    var manufacturer: String {
        if let data = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
           let manufacturerString = String(data: data, encoding: .utf8) {
            return manufacturerString
        }
        return "Unknown Manufacturer"
    }

    // Determine if is apple device
    var isAppleDevice: Bool { // Detect if the device is an Apple device
        name.lowercased().contains("iphone") ||
        name.lowercased().contains("ipad") ||
        name.lowercased().contains("mac")
    }
    
    // Format Battery Level Text
    var batteryLevelText: String {
        if let battery = batteryLevel {
            return "\(battery)%"
        } else {
            return "N/A"
        }
    }

    // Determines the icon for the device based on its characteristics (TODO: Refine)
    func determineIcon() -> String {
        let lowercasedName = name.lowercased()
        let lowercasedManufacturer = manufacturer.lowercased()

        if isAppleDevice {
            switch true {
            case lowercasedName.contains("macbook"): return "laptopcomputer"
            case lowercasedName.contains("mac"): return "desktopcomputer"
            case lowercasedName.contains("ipad"): return "ipad"
            case lowercasedName.contains("iphone"): return "iphone"
            case lowercasedName.contains("airpods"), lowercasedName.contains("headphone"): return "headphones"
            case lowercasedName.contains("watch"): return "applewatch"
            default: return "applelogo"
            }
        }

        if lowercasedName.contains("tv") { return "tv" }

        let laptopBrands = ["surface", "thinkpad", "lenovo", "hp"]
        if laptopBrands.contains(where: { lowercasedName.contains($0) }) { return "laptopcomputer" }

        let phoneBrands = ["samsung", "pixel", "oneplus", "xiaomi", "huawei", "oppo", "vivo"]
        if phoneBrands.contains(where: { lowercasedName.contains($0) }) { return "candybarphone" }

        switch true {
        case lowercasedName.contains("bose"): return "wave.3.right"
        case lowercasedName.contains("headphone"): return "headphones"
        case lowercasedName.contains("airpod"), lowercasedName.contains("earbud"): return "airpods"
        case lowercasedName.contains("speaker") || lowercasedName.contains("jbl"): return "speaker"
        case lowercasedName.contains("keyboard"): return "keyboard"
        case lowercasedName.contains("mouse"): return "computermouse"
        case lowercasedName.contains("tablet"): return "ipad"
        case lowercasedName.contains("laptop"): return "laptopcomputer"
        case lowercasedName.contains("camera"): return "camera"
        case lowercasedName.contains("unknown"): return "questionmark.circle"
        case lowercasedManufacturer.contains("nordic"): return "antenna.radiowaves.left.and.right"
        case lowercasedManufacturer.contains("bose") || lowercasedName.contains("bose"): return "wave.3.forward"
        case lowercasedManufacturer.contains("sony") || lowercasedName.contains("sony"): return "music.note"
        default: break
        }

        if let batteryLevel = batteryLevel {
            switch batteryLevel {
            case ...10: return "battery.0"
            case 11...50: return "battery.25"
            case 51...75: return "battery.50"
            case 76...: return "battery.100"
            default: break
            }
        }

        return "cpu"
    }
    
    // Determine Device / Peripheral Status String
    var statusText: String {
       switch status {
           case .disconnected: return "Disconnected"
           case .connecting: return "Connecting"
           case .connected: return "Connected"
       }
   }
}
