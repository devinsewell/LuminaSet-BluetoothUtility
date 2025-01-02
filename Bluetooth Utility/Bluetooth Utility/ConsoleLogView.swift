//  WiFi Utility -> ConsoleLogView.swift  -->  12/28/24 Devin Sewell

import SwiftUI

// MARK: - Console Log

let logMessageLimit = 1000 // Limit maximum console logs
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
    
    var body: some View {
        VStack(spacing: 0) {
            consoleLogHeaderView
            
            // Show log view if expanded or no Device selected
            if isConsoleExpanded || networkManager.selectedDevice == nil {
                logScrollView
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
                Spacer()
                if isConsoleExpanded || networkManager.selectedDevice == nil {
                    Toggle("AutoScroll", isOn: $autoScrollEnabled)
                        .toggleStyle(SwitchToggleStyle(tint: .orange))
                        .labelsHidden()
                }
                if networkManager.selectedDevice != nil {
                    toggleExpandButton
                }
            }
            .padding()
            .contentShape(Rectangle())
            Rectangle().fill(Color.black.opacity(0.03)).frame(height: 1)
        }
    }
    
    // Expand / Collapse Console Log
    private var toggleExpandButton: some View {
        Image(systemName: isConsoleExpanded ? "minus.circle" : "plus.circle")
            .font(.title2)
            .foregroundColor(.orange)
            .padding(.leading, 8)
            .onTapGesture {
                withAnimation { isConsoleExpanded.toggle() }
            }
    }
    
    // Console Log ScrollView
    private var logScrollView: some View {
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
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
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
            ("Disconnected:", .red),               // Matches "Disconnected:"
            ("Max reconnection attempts reached:", .orange),
            ("Connected:", .green),
            ("Bluetooth is powered on.", .cyan),
            ("Bluetooth is unavailable. Clearing devices.", .orange),
            ("Discovered Services:", .green),
            ("Discovered:", .blue),
            ("Retrieved Peripheral:", .blue),
            ("Connecting:", .cyan),
            ("Service:", .cyan),
            ("Descriptor Value Updated:", .blue),
            ("Discovered Descriptors for:", .green),
            ("Error discovering descriptors for:", .red),
            ("Read Characteristic:", .cyan),
            ("Characteristic Updated:", .blue),
            ("Subscribing to notifications for:", .cyan),
            ("Reading initial value for:", .cyan),
            ("Error reading characteristic:", .red),
            ("Starting Bluetooth scan...", .green),
            ("Stopping Bluetooth scan...", .red),
            ("Error Writing to Device:", .red),
            ("Writing data to:", .blue),
            ("Successfully Wrote to Characteristic:", .green),
            ("Value:", .orange),
            ("Properties:", .cyan),
            ("Discovered Characteristics for Services:", .green),
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
