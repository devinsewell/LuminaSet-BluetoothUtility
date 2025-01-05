//  WiFi Utility -> ConsoleLogView.swift  -->  12/28/24 Devin Sewell

import SwiftUI

// MARK: - Console Log

let logMessageLimit = 200_000 // Limit maximum console logs
let logUpdateQueue = DispatchQueue(label: "logUpdateQueue", qos: .userInitiated)
let logBatchInterval: TimeInterval = 0.5 // Throttle Console Log propegation
var pendingLogs: [String] = [] // Buffer to store pending Console Logs

// Console Log Item
struct ConsoleLogItem: Hashable {
    let text: String
    let color: Color
}

// Console Log View
struct ConsoleLogView: View {
    @Environment(\.colorScheme) var colorScheme
    @ObservedObject var networkManager = NetworkManager.shared
    @Binding var logs: [String]
    @State private var isConsoleExpanded = true
    @State private var autoScrollEnabled = true
    
    @State private var isAlertPresented: Bool = false // Alert visibile bool
    @State private var alertTitle: String = "" // Alert Title
    @State private var alertMessage: String = "" // Alert Message
    @State private var confirmAction: (() -> Void)? = nil // Alert Confirm Action
    
    var body: some View {
        VStack(spacing: 0) {
            // Console Log header
            consoleLogHeaderView
            // Show Console Log if is expanded or if no Device is selected
            if isConsoleExpanded || networkManager.selectedDevice == nil {
                // Console Log ScrollView
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(logs.indices, id: \.self) { index in
                                formatLog(logs[index]).padding(.horizontal).frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(.top, 10)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .onAppear {
                            scrollToLast(proxy)
                        }
                        .onChange(of: logs) { _, _ in
                            if autoScrollEnabled && isConsoleExpanded {
                                withAnimation { scrollToLast(proxy) }
                            }
                        }
                    }
                    .alert(isPresented: $isAlertPresented) {
                        Alert( // Used to confirm clear console log
                            title: Text(alertTitle),
                            message: Text(alertMessage),
                            primaryButton: .default(Text("Yes")) {
                                confirmAction?()
                            },
                            secondaryButton: .cancel()
                        )
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .background(Color.gray.opacity(0.2))
        .animation(.easeInOut, value: isConsoleExpanded)
    }
    
    // Console Log Header, title, autoScrollEnabled Toggle, and collapse/expand button
    private var consoleLogHeaderView: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.orange).frame(height: 1)
            HStack {
                Image(systemName: "text.justifyleft")
                Text("Console Log").font(.headline)
                
                if isConsoleExpanded || networkManager.selectedDevice == nil {
                    // Share Button
                    Button(action: shareLogs) {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundColor(.green)
                    }
                    Spacer()
                    Button(action: { // Clear Console Log button
                        showAlert(
                            title: "Clear Console Log ",
                            message: "Are you sure you want to erase the console log?",
                            confirmAction: {
                                networkManager.consoleLogs = []
                            }
                        )
                    }) {
                        Image(systemName: "trash").foregroundColor(.red)
                    }
                    .padding(.leading, 8)
                    Text("Autoscroll").foregroundColor(Color(UIColor.tertiaryLabel))
                    Toggle("AutoScroll", isOn: $autoScrollEnabled)
                        .toggleStyle(SwitchToggleStyle(tint: .orange))
                        .labelsHidden()
                }else{
                    Spacer()
                }
                // Only show Expand/Collapse button if selectedDevice is nil
                if networkManager.selectedDevice != nil{
                    Image(systemName: isConsoleExpanded ? "minus.circle" : "plus.circle")
                        .font(.title2)
                        .foregroundColor(.orange)
                        .padding(.leading, 8)
                        .onTapGesture {
                            withAnimation { isConsoleExpanded.toggle() }
                        }
                }
            }
            .padding()
            .contentShape(Rectangle())
            Rectangle().fill(Color.black.opacity(0.03)).frame(height: 1)
        }
    }
    
    // Export and Share Console Log
    private func shareLogs() {
        guard !networkManager.consoleLogs.isEmpty else { return print("No logs available to share.") }

        // Combine logs into a single string
        let logsText = "LuminaSet -> Console Log Output:\n ------------------------------- \n\n" + networkManager.consoleLogs.joined(separator: "\n\n")
        // Add date and time to the filename -> Example: 20240102_142530
        let dateFormatter: DateFormatter = { let df = DateFormatter(); df.dateFormat = "yyyyMMdd_HHmmss"; return df }()
        let timestamp = dateFormatter.string(from: Date())
        let tempFileURL = FileManager.default.temporaryDirectory.appendingPathComponent("LuminaSetBLE_\(timestamp).txt")

        do {
            // Write logs to a temporary file
            try logsText.write(to: tempFileURL, atomically: true, encoding: .utf8)
            
            // Create and configure the share sheet
            let activityVC = UIActivityViewController(activityItems: [tempFileURL], applicationActivities: nil)
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootVC = scene.keyWindow?.rootViewController {
                // Ensure iPad compatibility with popover
                if let popoverController = activityVC.popoverPresentationController {
                    popoverController.sourceView = rootVC.view
                    popoverController.sourceRect = CGRect(x: rootVC.view.bounds.midX, y: rootVC.view.bounds.midY, width: 0, height: 0
                    )
                    popoverController.permittedArrowDirections = []
                }
                rootVC.present(activityVC, animated: true)
            }
        } catch {
            print("Error writing logs: \(error.localizedDescription)")
        }
    }
    
    // Alert (Clear Console Log)
    func showAlert(title: String, message: String, confirmAction: @escaping () -> Void) {
        self.alertTitle = title
        self.alertMessage = message
        self.confirmAction = confirmAction
        self.isAlertPresented = true
    }
    
    // Scroll to latest Console Log Item if autoScrollEnabled == true
    private func scrollToLast(_ proxy: ScrollViewProxy) {
        if let lastIndex = logs.indices.last {
            proxy.scrollTo(lastIndex, anchor: .bottom)
        }
    }
    
    // Logic to color format Console Log Items
    @ViewBuilder
    private func formatLog(_ log: String) -> some View {
        let parts = processLog(log)
        VStack(alignment: .leading, spacing: 4) {
            ForEach(parts, id: \.self) { part in
                Text(part.text)
                    .foregroundColor(part.color)
                    .font(.system(.caption, design: .monospaced))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 2) // Add spacing between parts
            }
        }
    }
    
    // Process Console Log Item
    private func processLog(_ log: String) -> [ConsoleLogItem] {
        var parts: [ConsoleLogItem] = []

        // Split log into lines by line breaks
        let lines = log.split(separator: "\n", omittingEmptySubsequences: false)
        
        for line in lines {
            let lineParts = processLine(String(line)) // Process each line
            parts.append(contentsOf: lineParts)
        }
        parts.append(ConsoleLogItem(text: "", color: .primary))

        return parts
    }

    // Process each line of Console Log Item
    private func processLine(_ line: String) -> [ConsoleLogItem] {
        var lineParts: [ConsoleLogItem] = []
        
        // Define rules for matching and coloring console log
        let highlightColorBrackets: Color = colorScheme == .light ? .purple : .orange
        let colorRules: [(pattern: String, color: Color)] = [
            ("\\[.*?\\]", highlightColorBrackets),   // Matches content in square brackets []
            ("\\(.*?\\)", .green),                  // Matches content in parentheses ()
            ("\\{.*?\\}", .cyan),                   // Matches content in curly braces {}
            ("\\<.*?\\>", .red),                    // Matches content in angle brackets <>
            ("^[-]+$", .orange),                    // Matches standalone lines of "-"
            ("^[_]+$", .cyan),                    // Matches standalone lines of "_"
            ("Device Disconnected:", .red),               // Matches "Disconnected:"
            ("Connected:", .green),
            ("Successfully Wrote to Characteristic:", .green),
            ("Bluetooth is powered on.", .cyan),
            ("Starting Bluetooth scan...", .green),
            ("Stopping Bluetooth scan...", .red),
        ]
        
        // Reassemble formatted Console Log Item
        var remainingLine = line
        while !remainingLine.isEmpty {
            var matched = false
            for (pattern, color) in colorRules {
                if let range = remainingLine.range(of: pattern, options: .regularExpression) {
                    let before = String(remainingLine[..<range.lowerBound])
                    if !before.isEmpty {
                        lineParts.append(ConsoleLogItem(text: before, color: .primary))
                    }
                    let match = String(remainingLine[range])
                    lineParts.append(ConsoleLogItem(text: match, color: color))

                    remainingLine = String(remainingLine[range.upperBound...])
                    matched = true
                    break
                }
            }
            if !matched {
                lineParts.append(ConsoleLogItem(text: remainingLine, color: .primary))
                break
            }
        }
        return lineParts
    }
}
