//  WiFi Utility -> ContentView.swift  -->  12/28/24 Devin Sewell

import Foundation
import SwiftUI
import CoreBluetooth

// MARK: - ContentView -> App Container with Tablet/Mobile display logic
struct ContentView: View {
    @ObservedObject var networkManager = NetworkManager.shared
    @State private var columnVisibility: NavigationSplitViewVisibility = .doubleColumn

    var body: some View {
        // Use NavigationSplitView for iPad, NavigationStack for iPhone
        Group {
            if UIDevice.current.userInterfaceIdiom == .pad {
                // iPad: Use NavigationSplitView
                NavigationSplitView(columnVisibility: $columnVisibility.animation()) {
                    MainView()
                } detail: {
                    if let selectedDevice = networkManager.selectedDevice {
                        DetailView(device: Binding(get: { selectedDevice }, set: { networkManager.selectedDevice = $0 }))
                    } else {
                        VStack {}
                            .navigationBarHidden(columnVisibility != .detailOnly)
                            .navigationTitle("Bluetooth Utility")
                    }
                    ConsoleLogView(logs: $networkManager.consoleLogs)
                }
                .navigationSplitViewStyle(.balanced)
            } else {
                // iPhone: Use NavigationStack
                NavigationStack {
                    if let selectedDevice = networkManager.selectedDevice {
                        DetailView(device: Binding(
                            get: { selectedDevice },
                            set: { newValue in
                                networkManager.selectedDevice = newValue
                            }
                        ))
                        ConsoleLogView(logs: $networkManager.consoleLogs)
                    } else {
                        MainView()
                    }
                }
            }
        }
    }
}

// MARK: - MainView
struct MainView: View {
    @Environment(\.colorScheme) var colorScheme
    @ObservedObject var networkManager = NetworkManager.shared
    @State private var showAllDevices: Bool = true
    @State private var selectedDistanceFilter: DistanceFilter = .all
    var connectedDevicesRowHeight: CGFloat = 70.0

    enum DistanceFilter: String, CaseIterable {
        case all = "All"
        case close = "Close Proximity"
        case near = "Near Proximity"
        case far = "Far Proximity"
    }
    // Filter Discovered Devices by RSSI and 'Unknown' Devices
    var filteredDevices: [BluetoothDevice] {
        networkManager.synchronizeDeviceStatus() // Sychronize discoveredDevices, connectedDevices, and selectedDevice
        return networkManager.discoveredDevices.filter { device in
            // Apply "Show All" / "Hide Unknown", and Distance filters
            guard showAllDevices || (device.name != "Unknown Device") else { return false }
            switch selectedDistanceFilter { // Apply distance filter
            case .all:
                return true
            case .close:
                return device.rssi.intValue > -50 // Close Proximity
            case .near:
                return device.rssi.intValue <= -50 && device.rssi.intValue > -70 // Near Proximity
            case .far:
                return device.rssi.intValue <= -70 // Far Proximity
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Nearby Devices Header
            VStack(alignment: .leading) {
                // Pluralize 'Device' for multiple devices discovered
                Text("\(filteredDevices.count) Device\(filteredDevices.count == 1 ? "" : "s") \nNearby")
                    .font(.largeTitle)
                    .bold()
                if selectedDistanceFilter != .all || !showAllDevices {
                    // If Scan mode(s) selected show selected options
                    HStack {
                        Text("Scan Mode:").font(.caption).foregroundColor(.secondary)
                        Text("\(selectedDistanceFilter.rawValue.capitalized)\(showAllDevices ? "" : "'Unknown' Hidden")")
                            .foregroundColor(.secondary)
                            .font(.system(.caption, design: .monospaced))
                            .padding(8)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color(.secondarySystemBackground))
                                    .stroke(Color.blue, lineWidth: 1)
                            )
                    }
                }
                HStack {
                    // Scan Nearby Devices Toggle
                    Image(systemName: "antenna.radiowaves.left.and.right").foregroundColor(.secondary)
                    Text("Scan nearby devices").foregroundColor(.secondary)
                    Spacer()
                    Toggle("Scanning", isOn: $networkManager.bluetoothScanning)
                    .tint(.blue)
                    .labelsHidden() // Hides the label for compact layout
                    .onChange(of: networkManager.bluetoothScanning) { _, newValue in
                        DispatchQueue.main.async { newValue ? networkManager.startBluetoothScan() : networkManager.stopBluetoothScan() }
                    }

                }.padding(.bottom)
            }
            .padding(.horizontal)
            
            // Nearby Devices Grid
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 10) {
                    ForEach(filteredDevices) { device in
                        DiscoveredDeviceTile(device: device) // Discovered / Nearby Device Item
                    }
                }
                .padding(.horizontal)
            }
            .refreshable {
                networkManager.stopBluetoothScan() // Stop any existing scan
                networkManager.discoveredDevices.removeAll() // Clear discovered devices
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { // Add delay to load content after refresh animation
                    networkManager.startBluetoothScan()
                }
            }

            // Connected Devices List
            VStack(alignment: .leading, spacing: 10) {
                VStack {
                    Rectangle().fill(Color.blue).frame(height: 1)
                    HStack {
                        Image(systemName: "link").foregroundColor(.blue)
                        Text("Connected Devices").font(.headline).foregroundColor(.blue)
                        Spacer()
                        Text("\(networkManager.connectedDevices.count)").font(.headline).foregroundColor(.blue)
                    }
                    .padding()
                }
                List {
                    ForEach(networkManager.connectedDevices) { device in
                        ConnectedDeviceCell(device: device) // Connected Device Item
                    }
                    .onDelete { indexSet in
                        indexSet.forEach { networkManager.disconnectDevice(networkManager.connectedDevices[$0]) }
                    }
                }
                .listStyle(PlainListStyle())
                .frame(maxHeight: CGFloat(networkManager.connectedDevices.count) * connectedDevicesRowHeight)
                .animation(.easeInOut, value: CGFloat(networkManager.connectedDevices.count) * connectedDevicesRowHeight)
            }
            .background(colorScheme == .dark ? .black : .white)
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Image("LSLogo") // LuminaSet Logo
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(height: 28)
                    .foregroundColor(.blue)
                    .id(UUID()) // Needed to prevent display issue on redraw
            }
           
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Text("Scan Options:").font(.headline).foregroundColor(.secondary)
                    // Visibility Toggle (Hide Unknowns)
                    Picker("Visibility", selection: $showAllDevices) {
                        Label("Show All", systemImage: showAllDevices ? "checkmark.circle.fill" : "circle").tag(true)
                        Label("Hide Unknown", systemImage: !showAllDevices ? "checkmark.circle.fill" : "circle").tag(false)
                    }
                    .pickerStyle(.inline)
                    Divider()
                    
                    // Distance Filter
                    Picker("Distance", selection: $selectedDistanceFilter) {
                        ForEach(DistanceFilter.allCases, id: \.self) { filter in
                            Label(filter.rawValue, systemImage: selectedDistanceFilter == filter ? "checkmark.circle.fill" : "circle").tag(filter)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                }
            }
        }
        .background(colorScheme == .dark ? Color.gray.opacity(0.1) : Color(.systemGroupedBackground))
    }
}

// MARK: - Connected Device List Cell
struct ConnectedDeviceCell: View {
    @ObservedObject var networkManager = NetworkManager.shared
    let device: BluetoothDevice
    var body: some View {
        HStack {
            // Show "control" symbol if Device is selected
            Image(systemName: "slider.horizontal.3").foregroundColor(.orange).opacity(networkManager.selectedDevice == device ? 1 : 0)

            // Show "!" symbol if Device is not .connected
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(device.status == .connecting ? .blue : .secondary).opacity(device.status != .connected ? 1 : 0)

            // Device Type Icon
            Image(systemName: device.determineIcon()).font(.title2).foregroundColor(.blue)

            // Device Info Text
            VStack(alignment: .leading) {
                Text(device.name).font(.body).bold()
                Text(device.manufacturer).font(.caption).foregroundColor(.secondary)
                Text(device.model).font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
            // RSSI value Text
            VStack {
                Text(device.rssi.intValue != 0 ? "\(device.rssi)dB" : "N/A").font(.caption)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { networkManager.selectedDevice = device } // Set selectedDevice on Connected Device List cell tap
    }
}

// MARK: - Nearby / Discovered Device LazyVGrid Item
struct DiscoveredDeviceTile: View {
    @ObservedObject var networkManager = NetworkManager.shared
    let device: BluetoothDevice
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22)
                .fill(device.status == .connected ? Color.blue : Color.clear)
                .stroke(Color.blue, lineWidth: 2)
                .overlay(
                    VStack {
                        Image(systemName: device.determineIcon())
                            .font(.largeTitle)
                            .foregroundColor(device.status == .connected ? .white : .blue)
                            .padding(.top, 8) // UI: Adjusted for visual balance
                        Text(device.name)
                            .font(.caption)
                            .foregroundColor(device.status == .connected ? .white : .blue)
                            .multilineTextAlignment(.center)
                            .padding(.top, 2) // UI: Adjusted for visual balance
                    }
                    .padding()
                )
                .frame(height: 100)
                .onTapGesture {
                    switch device.status {
                    case .connecting:
                        networkManager.cancelConnectingDevice(device)
                    case .disconnected:
                        networkManager.connectToDevice(device)
                        networkManager.selectedDevice = networkManager.selectedDevice ?? device
                    default:
                        networkManager.selectedDevice = device
                    }
                }
                .padding(.top, 1) // UI: prevents clipping of object
            VStack {
                HStack {
                    if device.status == .connecting {
                        // If Connecting show Activity/Progress Indicator
                        ProgressView().progressViewStyle(CircularProgressViewStyle()).scaleEffect(0.7)
                        Spacer()
                    } else {
                        // Display Antenna icon or Control icon if device is selected
                        Image(systemName: networkManager.selectedDevice == device ? "slider.horizontal.3" : "antenna.radiowaves.left.and.right")
                            .foregroundColor(networkManager.selectedDevice == device ? .orange : device.status == .connected ? .white : .blue)
                        Spacer()
                        Text(device.rssi.intValue != 0 ? "\(device.rssi)dB" : "N/A")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(8)
                Spacer()
            }
        }
    }
}

// MARK: - DetailView
struct DetailView: View {
    @Binding var device: BluetoothDevice
    @ObservedObject var networkManager = NetworkManager.shared
    @State private var pollingInterval: String = "5" // Default polling interval (seconds)
    @State private var isAlertPresented: Bool = false // Alert visibile bool
    @State private var alertTitle: String = "" // Alert Title
    @State private var alertMessage: String = "" // Alert Message
    @State private var confirmAction: (() -> Void)? = nil // Alert Confirm Action
    @State private var inputModes: [CBUUID: InputMode] = [:] // Store input mode for each characteristic
    
    // Alert logic (used for Disconnect)
    func showAlert(title: String, message: String, confirmAction: @escaping () -> Void) {
        self.alertTitle = title
        self.alertMessage = message
        self.confirmAction = confirmAction
        self.isAlertPresented = true
    }
    
    var body: some View {
        ScrollView {
            VStack() {
                VStack { // Selected Device Header: Device Type Icon, Name, Manufacturer, Model
                    HStack {
                        Image(systemName: device.determineIcon())
                            .font(.system(size: 64))
                            .foregroundColor(.blue)
                            .padding()
                            .background(Circle().fill(Color.gray.opacity(0.1)))
                        VStack(alignment: .leading) {
                            Text(device.name).font(.largeTitle).bold()
                            Text(device.manufacturer).font(.body).foregroundColor(.secondary)
                            Text(device.model).font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
            }
            VStack(alignment: .center, spacing: 16) {
                HStack { // Live Updates Toggle and Polling Interval
                    Image(systemName: "waveform.path.ecg").foregroundColor(.orange)
                    Toggle("Live Updates", isOn: $networkManager.liveUpdatesEnabled)
                        .onChange(of: networkManager.liveUpdatesEnabled) { _, newValue in
                            handleLiveUpdates(enabled: newValue)
                        }
                        .foregroundColor(.orange)
                    Spacer()
                    HStack {
                        Text("Interval (s):")
                        TextField("Seconds", text: $pollingInterval)
                            .keyboardType(.numberPad)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(width: 60)
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.1)))
                Divider()
                VStack { // Device Advertising Information -> Connection Status, RSSI, Service count, Characteristic count
                    HStack {
                        deviceStat(icon: "antenna.radiowaves.left.and.right", label: "Status", value: device.statusText)
                        deviceStat(icon: "wifi", label: "RSSI", value: "\(device.rssi)dB")
                    }
                    HStack {
                        deviceStat(label: "Services", value: "\(device.peripheral?.services?.count ?? 0)")
                        deviceStat(label: "Characteristics", value: "\(networkManager.totalCharacteristicsCount(for: device))")
                    }
                    .padding(.top)
                }
                .font(.subheadline)
                .foregroundColor(.primary)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.1)))
                Divider()
                
                // DetailView --> GATT Services and Characteristics
                if let peripheral = device.peripheral {
                    if let services = device.peripheral?.services {
                        ForEach(services, id: \.uuid) { service in
                            VStack(alignment: .leading, spacing: 10) {
                                let serviceName = gattServiceNames[service.uuid.uuidString.prefix(4).uppercased()] ?? "Service"
                                HStack {
                                    Text("\(serviceName)").font(.title2).bold()
                                    Spacer()
                                }
                                Text("UUID: \(service.uuid.uuidString)").font(.subheadline).bold()
                                
                                if let characteristics = service.characteristics {
                                    if serviceName == "Device Information" {
                                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                                            ForEach(characteristics, id: \.uuid) { characteristic in
                                                characteristicView(characteristic: characteristic, peripheral: peripheral)
                                            }
                                        }
                                    } else {
                                        ForEach(characteristics, id: \.uuid) { characteristic in
                                            characteristicView(characteristic: characteristic, peripheral: peripheral)
                                        }
                                    }
                                } else {
                                    Text("No Characteristics").font(.body).foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 10)
                        }
                    }
                } else {
                    if device.status != .connected {
                        Text("Disconnected").font(.body).foregroundColor(.secondary)
                    }else {
                        Text("No Services Found").font(.body).foregroundColor(.secondary)
                    }
                }
            }
            .padding()
        }
        .navigationTitle(device.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear{
            // Begin Polling Characteristics on DetailView appear
            handleLiveUpdates(enabled: networkManager.liveUpdatesEnabled)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: {
                    if device.status == .connected {
                        // If Connected use 'Disconnect' logic
                        showAlert(
                            title: "Disconnect",
                            message: "Are you sure you want to disconnect this device?",
                            confirmAction: {
                                networkManager.disconnectDevice(device)
                            }
                        )
                    } else {
                        // If Disconnected use 'Connect' logic
                        networkManager.connectToDevice(device)
                    }
                }) {
                    // Only show if .connected or .disconnected
                    if [.connected, .disconnected].contains(device.status) {
                        Text(device.status == .connected ? "Disconnect" : "Connect")
                            .foregroundColor(device.status == .connected ? .red : .green)
                    }
                }
            }
            // Dismiss selected device detail view button
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Dismiss") {
                    networkManager.stopCharacteristicPolling()
                    networkManager.selectedDevice = nil
                }
            }
        }
        .alert(isPresented: $isAlertPresented) {
            Alert(
                title: Text(alertTitle),
                message: Text(alertMessage),
                primaryButton: .default(Text("Yes")) {
                    confirmAction?()
                },
                secondaryButton: .cancel()
            )
        }.opacity(device.status == .connected ? 1.0 : 0.5)
    }
    
    // Poll selected device Characteristics at interval
    private func handleLiveUpdates(enabled: Bool) {
        guard enabled, let interval = Double(pollingInterval), interval > 0 else {
            enabled ? networkManager.startCharacteristicPolling(interval: 5.0) : networkManager.stopCharacteristicPolling()
            return
        }
        networkManager.pollCharacteristics()
        networkManager.startCharacteristicPolling(interval: interval)
    }
    
    // Handle formatting Characteristic control input
    private func processInput(for characteristic: CBCharacteristic, devices: [BluetoothDevice]) {
        let currentMode = inputModes[characteristic.uuid] ?? .hex // Default to .hex if nil
        guard let rawInput = networkManager.textInputs[characteristic.uuid] else {
            print("No raw input available for this characteristic.")
            return
        }
        if let data = currentMode.formatInput(rawInput) {
            networkManager.writeDataToBLE(characteristic: characteristic, data: data, devices: devices)
        } else {
            print("Invalid input: \(rawInput)")
        }
    }
    
    // Characteristic Detail / Input View
    @ViewBuilder
    private func characteristicView(characteristic: CBCharacteristic, peripheral: CBPeripheral) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let descriptors = characteristic.descriptors, // Retrieve and display Characteristic User Description (CUD)
               let userDescriptionDescriptor = descriptors.first(where: { $0.uuid == CBUUID(string: "2901") }) {
                if let description = networkManager.getDescriptorValue(for: characteristic, descriptor: userDescriptionDescriptor) {
                    // Display Characteristic Descriptor text
                    Text("\(description)").font(.subheadline).foregroundColor(.blue)
                } else {
                    // Display Activity / Progress indicator and 'Reading Description...' while retrieving Characteristic Descriptor
                    HStack {
                        ProgressView().progressViewStyle(CircularProgressViewStyle()).scaleEffect(0.8).padding(.trailing, 4)
                        Text("Reading Description...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .onAppear {
                                guard !networkManager.isDescriptorRead(descriptor: userDescriptionDescriptor, characteristic: characteristic) else { return }
                                networkManager.readDescriptorValue(descriptor: userDescriptionDescriptor)
                            }
                    }
                }
            }else{
                // Display Characteristic name with activity monitor while retrieving Characteristic Descriptor
                let unknownName = "Unknown Characteristic"
                let characteristicName = gattCharacteristicNames[characteristic.uuid.uuidString.prefix(4).uppercased()] ?? unknownName
                Text("\(characteristicName)").font(.subheadline).foregroundColor(.blue)
            }
            // Display Characteristic UUID
            Text("UUID: \(characteristic.uuid.uuidString)").font(.footnote).foregroundColor(.secondary)
            
            // Display Characteristic properties
            let modes = characteristicPropertiesDescription(characteristic)
            Text("Modes: \(modes)").font(.caption).foregroundColor(.secondary)

            // Display Hex, Integer, String picker
            Picker("Input Mode", selection: Binding(
                get: {
                    inputModes[characteristic.uuid] ?? .hex // Default to .hex if not set
                },
                set: { newMode in
                    inputModes[characteristic.uuid] = newMode
                }
            )) {
                Text("Hex").tag(InputMode.hex)
                Text("Integer").tag(InputMode.int)
                Text("String").tag(InputMode.string)
            }
            .pickerStyle(SegmentedPickerStyle())
            
            if let value = networkManager.getCharacteristicValue(characteristic) {
                // Display Characteristic value
                Text("Value: ").font(.caption).foregroundColor(.secondary)
                Text(formattedValue(value, for: inputModes[characteristic.uuid] ?? .hex))
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundColor(.blue)
                    .padding(4)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(5)
                    .onTapGesture {
                        // Set the tapped value into the Characteristic Input TextField
                        networkManager.textInputs[characteristic.uuid] = formattedValue(value, for: inputModes[characteristic.uuid] ?? .hex)
                    }
            } else {
                // Display Characteristic placeholder if needed
                HStack {
                    Text("Value: ").font(.system(.footnote, design: .monospaced)).foregroundColor(.secondary)
                    Text("Not Available")
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundColor(.blue)
                        .padding(4)
                        .background(Color.white.opacity(0.2))
                        .cornerRadius(5)
                }
            }

            // Add write input if Characteristic is writable
            if characteristic.properties.contains(.write) {
                VStack {
                    HStack {
                        TextEditor(text: Binding(
                            get: {
                                if inputModes[characteristic.uuid] == .hex {
                                    let raw = networkManager.textInputs[characteristic.uuid] ?? ""
                                    let cleanedValue = raw.replacingOccurrences(of: " ", with: "") // Remove existing spaces
                                    return cleanedValue.chunked(by: 2).joined(separator: " ") // Format into chunks
                                }
                                return networkManager.textInputs[characteristic.uuid] ?? ""
                            },
                            set: { newValue in
                                let sanitizedValue = inputModes[characteristic.uuid] == .hex
                                    ? newValue.filter { "0123456789ABCDEFabcdef".contains($0) } // Allow only valid hex characters
                                    : newValue // No sanitization for non-hex mode
                                networkManager.textInputs[characteristic.uuid] = sanitizedValue != networkManager.textInputs[characteristic.uuid] ? sanitizedValue : networkManager.textInputs[characteristic.uuid]

                            }
                        ))
                        .lineLimit(nil) // Allow unlimited Characteristic Input lines
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.5), lineWidth: 1)) // Border stroke for input textField
                        .font(.system(.footnote, design: .monospaced))
                        .keyboardType(inputModes[characteristic.uuid] == .hex ? .asciiCapable : .numberPad)
                        .onSubmit {processInput(for: characteristic, devices: [device])}
                        .onAppear {
                            // Set default mode to .hex if not already set
                            inputModes[characteristic.uuid] = inputModes[characteristic.uuid] ?? .hex
                        }
                        .onChange(of: networkManager.textInputs[characteristic.uuid] ?? "") { previousInput, currentInput in
                            guard inputModes[characteristic.uuid] == .hex else { return }
                            let sanitizedInput = currentInput.replacingOccurrences(of: " ", with: "") // Remove spaces
                            let formattedInput = sanitizedInput.chunked(by: 2).joined(separator: " ") // Format into chunks
                            networkManager.textInputs[characteristic.uuid] = (networkManager.textInputs[characteristic.uuid] != formattedInput) ? formattedInput : networkManager.textInputs[characteristic.uuid]

                        }
                        
                        // Clear Characteristic value Input button
                        if !(networkManager.textInputs[characteristic.uuid]?.isEmpty ?? true) {
                            Button(action: {
                                networkManager.textInputs[characteristic.uuid] = ""
                            }) {
                                Image(systemName: "xmark.circle.fill").foregroundColor(.secondary).padding(8)
                            }
                        }
                        Button(action: {
                            // Finalize any pending Characteristic value input
                            UIApplication.shared.sendAction(#selector(UIView.endEditing), to: nil, from: nil, for: nil)
                            processInput(for: characteristic, devices: [device])
                        }) {
                            Image(systemName: "paperplane.fill").foregroundColor(.white)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    // Sent Characteristic Values List aka Write History
                    if let sentValues = networkManager.sentValues[characteristic.uuid], !sentValues.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Write History:").font(.caption).foregroundColor(.secondary)
                                Spacer()
                                   Button(action: { // Clear Write History button
                                       showAlert(
                                           title: "Clear Write History",
                                           message: "Are you sure you want to clear history for this characteristic?",
                                           confirmAction: {
                                               // Clear the input and history
                                               networkManager.textInputs[characteristic.uuid] = ""
                                               networkManager.clearWriteHistory(for: characteristic.uuid)
                                           }
                                       )
                                   }) {
                                       Image(systemName: "trash").foregroundColor(.red).font(.footnote)
                                   }
                                }
                                ForEach(sentValues.reversed().indices, id: \.self) { index in
                                    let value = sentValues.reversed()[index]
                                    HStack {
                                        Image(systemName: "viewfinder").foregroundColor(.primary).font(.footnote)
                                        Text(value)
                                            .font(.system(.footnote, design: .monospaced))
                                            .foregroundColor(index % 2 == 0 ? .blue : .cyan)
                                            .padding(.vertical, 2)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }.onTapGesture {
                                        networkManager.textInputs[characteristic.uuid] = value
                                        processInput(for: characteristic, devices: [device])
                                    }
                                }
                            }
                            .padding(8)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(8)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            Spacer()
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            networkManager.loadCharacteristicWriteHistory() // Load / refresh history
        }
    }

    // Device Advertising Stats Helper
    private func deviceStat(icon: String? = nil, label: String, value: String) -> some View {
        VStack {
            if let icon = icon { Image(systemName: icon).foregroundColor(.blue) }
            Text(label).font(.caption).foregroundColor(.secondary)
            Text(value).font(.subheadline).bold()
        }
        .frame(maxWidth: .infinity, alignment: .center) // Center align horizontally
    }
}

// Helper Function for Formatting Characteristic value
private func formattedValue(_ value: String, for mode: InputMode) -> String {
    switch mode {
    case .hex: // Space every 2 characters
        return value.chunked(by: 2).joined(separator: " ")
    case .int: // Convert hex to integer if valid
        return Int(value, radix: 16).map(String.init) ?? "N/A"
    case .string: // Decode hex string into a human-readable string
        let hexBytes = value.chunked(by: 2).compactMap { UInt8($0, radix: 16) }
        return String(bytes: hexBytes, encoding: .utf8) ?? "Invalid String"
    }
}

// Helper Function for Formatting Characteristic Properties
private func characteristicPropertiesDescription(_ characteristic: CBCharacteristic) -> String {
    [
        characteristic.properties.contains(.read) ? "Read" : nil,
        characteristic.properties.contains(.write) ? "Write" : nil,
        characteristic.properties.contains(.notify) ? "Notify" : nil,
        characteristic.properties.contains(.indicate) ? "Indicate" : nil,
        characteristic.properties.contains(.broadcast) ? "Broadcast" : nil
    ]
    .compactMap { $0 }
    .joined(separator: ", ")
}

// Helper Functions for Formatting Characteristic Input
enum InputMode: String {
    case hex
    case int
    case string

    // Format the Input based on selected input mode: .hex, .int, or .string
    func formatInput(_ input: String) -> Data? {
        switch self {
        case .hex:
            let sanitized = input.filter { "0123456789ABCDEFabcdef".contains($0) }
            guard sanitized.count % 2 == 0 else { return nil }
            var data = Data()
            var index = sanitized.startIndex
            while index < sanitized.endIndex {
                let nextIndex = sanitized.index(index, offsetBy: 2, limitedBy: sanitized.endIndex) ?? sanitized.endIndex
                let byteString = String(sanitized[index..<nextIndex])
                guard let byte = UInt8(byteString, radix: 16) else { return nil }; data.append(byte)
                index = nextIndex
            }
            return data
        case .int:
            guard let value = Int(input) else { return nil }
            return withUnsafeBytes(of: value.bigEndian) { Data($0) }
        case .string:
            return input.data(using: .utf8)
        }
    }
}
