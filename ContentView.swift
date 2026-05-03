import SwiftUI

struct ContentView: View {
    @StateObject private var bt = OlleeBTManager.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                statusSection

                if bt.savedPeripheralUUID == nil {
                    noDeviceView
                } else {
                    connectedDeviceView
                }

                if let error = bt.lastError {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Ollee Splash")
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(bt.isConnected ? Color.green : Color.red)
                .frame(width: 10, height: 10)
            Text(bt.isConnected ? "Connected" : "Disconnected")
                .font(.headline)
        }

        if let last = bt.lastSentValue {
            Text("Last sent: '\(last)'")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var noDeviceView: some View {
        Text("No watch paired")
            .font(.title2)
        Text("Tap below to scan. The app looks for the Ollee watch by its Bluetooth service signature. If your watch is nearby and broadcasting, it should appear even without a name.")
            .font(.caption)
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)

        Button("Scan for Watches") {
            bt.startScan()
        }
        .buttonStyle(.borderedProminent)
        .disabled(bt.isScanning)

        if bt.isScanning {
            ProgressView()
        }

        List(bt.discoveredPeripherals, id: \.peripheral.identifier) { item in
            Button {
                bt.connect(to: item.peripheral)
            } label: {
                HStack {
                    VStack(alignment: .leading) {
                        Text(item.name)
                            .font(.headline)
                        Text(item.peripheral.identifier.uuidString)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if bt.savedPeripheralUUID == item.peripheral.identifier {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.blue)
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private var connectedDeviceView: some View {
        if let uuid = bt.savedPeripheralUUID {
            VStack(spacing: 8) {
                Text("Saved Watch")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(uuid.uuidString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }

        Button("Forget Watch") {
            bt.forgetDevice()
        }
        .buttonStyle(.bordered)
        .tint(.red)

        Text("You can now use the 'Send Splash to Ollee' action in Shortcuts.")
            .font(.caption)
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .padding(.top)
    }
}
