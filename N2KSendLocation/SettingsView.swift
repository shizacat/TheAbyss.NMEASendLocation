import SwiftUI

struct SettingsView: View {
    @AppStorage("udpClientPort") private var tcpClientPort: Int = 4123
    @AppStorage("udpClientHost") private var tcpClientHost: String = "192.168.1.1"
    @AppStorage("showErrorHistory") private var showErrorHistory = false
    @AppStorage("timerEnabled") private var timerEnabled = false
    @AppStorage("timerInterval") private var timerInterval = 3
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(NSLocalizedString("udp_settings_header", comment: "UDP settings section header"))
                    .font(.headline)
                    .textCase(.none)
                ) {
                    HStack(spacing: 16) {
                        Image(systemName: "network")
                            .foregroundColor(.accentColor)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(NSLocalizedString("server_address_label", comment: "Server address label"))
                                .font(.subheadline.bold())
                                .foregroundColor(.primary)
                            TextField(NSLocalizedString("server_address_placeholder", comment: "Server address placeholder"), text: $tcpClientHost)
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.numbersAndPunctuation)
                        }
                    }
                    .padding(.vertical, 8)
                    
                    HStack(spacing: 16) {
                        Image(systemName: "number")
                            .foregroundColor(.accentColor)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(NSLocalizedString("port_number_label", comment: "Port number label"))
                                .font(.subheadline.bold())
                                .foregroundColor(.primary)
                            TextField(NSLocalizedString("port_placeholder", comment: "Port placeholder"), value: $tcpClientPort, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.numberPad)
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                Section(header: Text(NSLocalizedString("settings_error_header", comment: "Error settings section header"))
                    .font(.headline)
                    .textCase(.none)
                ) {
                    
                    Toggle(isOn: $showErrorHistory) {
                        Text(NSLocalizedString("show_error_history_label", comment: "Show error history toggle label"))
                    }
                }
                
                Section(header: Text(NSLocalizedString("timer_settings_header", comment: "Timer settings section header"))
                    .font(.headline)
                    .textCase(.none)
                ) {
                    Toggle(isOn: $timerEnabled) {
                        Text(NSLocalizedString("enable_timer_label", comment: "Enable timer toggle label"))
                    }
                    
                    Picker(selection: $timerInterval, label: Text(NSLocalizedString("timer_interval_label", comment: "Timer interval picker label"))) {
                        Text(NSLocalizedString("timer_interval_1s", comment: "1 second interval")).tag(1)
                        Text(NSLocalizedString("timer_interval_3s", comment: "3 seconds interval")).tag(3)
                        Text(NSLocalizedString("timer_interval_5s", comment: "5 seconds interval")).tag(5)
                        Text(NSLocalizedString("timer_interval_10s", comment: "10 seconds interval")).tag(10)
                    }
                    .disabled(!timerEnabled)
                }
            }
            .navigationTitle(NSLocalizedString("settings_title", comment: "App settings screen title"))
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("done_button", comment: "Done button title")) {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    SettingsView()
}
