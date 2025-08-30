//
//  ContentView.swift
//  N2KSendLocation
//
//  Created by Alexey Matveev on 03.08.2025.
//

import SwiftUI
import CoreLocation
import Network
import Foundation

enum ConnectionStatus: String {
    case disconnected = "Disconnected"
    case connected = "Connected"
    case failed = "Failed"
    case connecting = "Connecting..."
}

class LocationSender: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private var connection: NWConnection?
    private var timer: Timer?
    private var manualSendInProgress = false
    private var lastHeadingUpdate = Date.distantPast
    @AppStorage("udpClientHost") private var host: String = "192.168.1.1"
    @AppStorage("udpClientPort") private var port: Int = 10110
    @AppStorage("showErrorHistory") var showErrorHistory = false
    @AppStorage("timerEnabled") var timerEnabled = false
    @AppStorage("timerInterval") var timerInterval = 1
    @AppStorage("headingEnabled") var headingEnabled = false
    @AppStorage("headingType") var headingType: HeadingType = .true
    @Published var isSending = false
    @Published var lastSentCoordinates = ""
    @Published var lastSentTime: Date?
    @Published var lastSentLatitude: Double?
    @Published var lastSentLongitude: Double?
    @Published var lastSentHeading: Double?
    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var lastErrors: [String] = []
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.activityType = .automotiveNavigation
    }
    
    private let reconnectDelay: TimeInterval = 5

    private func addError(_ error: String) {
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm:ss"
        let timestamp = timeFormatter.string(from: Date())
        lastErrors.append("[\(timestamp)] \(error)")
        if lastErrors.count > 4 {
            lastErrors.removeFirst()
        }
    }

    func toggleSending() {
        if isSending {
            stopSending()
        } else {
            startSending()
        }
    }

    private func startSending() {
        // Reset last sent state
        lastSentCoordinates = ""
        lastSentTime = nil
        lastSentLatitude = nil
        lastSentLongitude = nil
        
        setupConnection()
        locationManager.requestAlwaysAuthorization()
        locationManager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() {
            locationManager.headingFilter = 0.5  // Update every 0.5 degree
            locationManager.startUpdatingHeading()
        }
        
        if timerEnabled {
            startTimer()
        }
    }
    
    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(
            withTimeInterval: TimeInterval(timerInterval),
            repeats: true
        ) { [weak self] _ in
            self?.sendCurrentLocation()
        }
    }
    
    private func sendCurrentLocation() {
        guard isSending, !manualSendInProgress,
              let location = locationManager.location else {
            return
        }
        
        // Prevent duplicate sends by marking in progress
        manualSendInProgress = true
        DispatchQueue.main.asyncAfter(deadline: .now() + TimeInterval(timerInterval) * 1.1) {
            self.manualSendInProgress = false
        }

        // Use existing locationManager(_:didUpdateLocations:) logic
        self.locationManager(self.locationManager, didUpdateLocations: [location])

        // Use existing locationManager(_:didUpdateHeading:) logic
        self.locationManager(self.locationManager, didUpdateHeading: self.locationManager.heading ?? CLHeading())
    }
    
    private func stopSending() {
        locationManager.stopUpdatingLocation()
        locationManager.startUpdatingHeading()

        connection?.cancel()
        isSending = false
        timer?.invalidate()
        timer = nil
    }
    
    private func setupConnection() {
        // Reset errors
        DispatchQueue.main.async { [weak self] in
            self?.lastErrors.removeAll()
        }
        
        connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: UInt16(port))!, using: .udp)
        connection?.stateUpdateHandler = { [weak self] newState in
            DispatchQueue.main.async {
                switch newState {
                case .ready:
                    self?.connectionStatus = .connected
                    self?.isSending = true
                case .failed(let error):
                    self?.connectionStatus = .failed
                    self?.addError("Connection failed: \(error.localizedDescription)")
                    self?.attemptReconnect()
                case .cancelled:
                    self?.connectionStatus = .disconnected
                case .waiting(let error):
                    self?.addError("Connection failed: \(error.localizedDescription)")
                    self?.connectionStatus = .disconnected
                    self?.attemptReconnect()
                default:
                    self?.connectionStatus = .connecting
                }
            }
        }
        connection?.start(queue: .global())
    }
    
    private func attemptReconnect() {
        guard isSending else { return }
        
        addError("Attempting to reconnect...")
        
        DispatchQueue.global().asyncAfter(deadline: .now() + reconnectDelay) { [weak self] in
            self?.setupConnection()
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last, isSending else { return }
        
        if timer != nil {
            // Mark manual send in progress to prevent timer send
            manualSendInProgress = true
            DispatchQueue.main.asyncAfter(deadline: .now() + TimeInterval(timerInterval) * 1.1) {
                self.manualSendInProgress = false
            }
        }
        
        // Process
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "ddMMyy"
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HHmmss.SSS"
        timeFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        
        let date = dateFormatter.string(from: location.timestamp)
        let time = timeFormatter.string(from: location.timestamp)
        
        let latDegrees = Int(location.coordinate.latitude)
        let latMinutes = (location.coordinate.latitude - Double(latDegrees)) * 60
        let latHemisphere = location.coordinate.latitude >= 0 ? "N" : "S"
        
        let lonDegrees = Int(location.coordinate.longitude)
        let lonMinutes = (location.coordinate.longitude - Double(lonDegrees)) * 60
        let lonHemisphere = location.coordinate.longitude >= 0 ? "E" : "W"
        
        let speedKnots = location.speed * 1.94384 // m/s to knots
        let course = location.course
        let altitude = location.altitude
        
        // Generate GPRMC message
        let gprmcMessage = String(format: "GPRMC,%@,A,%02d%06.3f,%@,%03d%06.3f,%@,%.1f,%.1f,%@,,",
                                 time,
                                 abs(latDegrees), abs(latMinutes), latHemisphere,
                                 abs(lonDegrees), abs(lonMinutes), lonHemisphere,
                                 speedKnots, course, date)
        
        // Generate GPGGA message
        let gpsQuality = 1 // 1 = GPS fix
        let numSatellites = 8 // Example value
        let hdop = 1.0 // Example value
        let geoidHeight = 0.0 // Example value
        let gpggaMessage = String(format: "GPGGA,%@,%02d%06.3f,%@,%03d%06.3f,%@,%d,%02d,%.1f,%.1f,M,%.1f,M,,",
                                 time,
                                 abs(latDegrees), abs(latMinutes), latHemisphere,
                                 abs(lonDegrees), abs(lonMinutes), lonHemisphere,
                                 gpsQuality, numSatellites, hdop, altitude, geoidHeight)
        
        // Generate GPVTG message
        let speedKmh = location.speed * 3.6 // m/s to km/h
        let gpvtgMessage = String(format: "GPVTG,%.1f,T,%.1f,M,%.1f,N,%.1f,K,",
                                 course, course, speedKnots, speedKmh)
        
        // Send all messages
        let messages = [gprmcMessage, gpggaMessage, gpvtgMessage]
        for var message in messages {
            let checksum = message.utf8.reduce(0) { $0 ^ UInt8($1) }
            message = "$\(message)*\(String(format: "%02X", checksum))\n"
            connection?.send(content: message.data(using: .utf8), completion: .contentProcessed({ [weak self] error in
                DispatchQueue.main.async {
                    if let error = error {
                        self?.addError("Send error: \(error.localizedDescription)")
                    } else {
                        // Set last state
                        self?.lastSentCoordinates = message.trimmingCharacters(in: .whitespacesAndNewlines)
                        self?.lastSentTime = location.timestamp
                        self?.lastSentLatitude = location.coordinate.latitude
                        self?.lastSentLongitude = location.coordinate.longitude
                    }
                }
            }))
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        var message: String
        var headingValue: Double
        let now = Date()

        // Throttle heading updates to 10 Hz
        guard now.timeIntervalSince(lastHeadingUpdate) >= 1/10 else {return}
        lastHeadingUpdate = now
        
        if headingType == .true {
            // True heading message: $GPHDT,123.456,T*00
            message = String(format: "GPHDT,%.3f,T", newHeading.magneticHeading)
            headingValue = newHeading.magneticHeading
        } else {
            // Magnetic heading message: $GPHDM,123.456,M*00
            message = String(format: "GPHDM,%.3f,M", newHeading.trueHeading)
            headingValue = newHeading.trueHeading
        }
        
        let checksum = message.utf8.reduce(0) { $0 ^ UInt8($1) }
        message = "$\(message)*\(String(format: "%02X", checksum))\n"
        connection?.send(content: message.data(using: .utf8), completion: .contentProcessed({ [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.addError("Send error: \(error.localizedDescription)")
                } else {
                    self?.lastSentHeading = headingValue
                }
            }
        }))
    }
        
}

struct ContentView: View {
    @StateObject private var sender = LocationSender()
    @State private var showingSettings = false
    @State private var showingInfo = false
    
    var body: some View {
        NavigationStack {
            VStack {
                // Last sent data block
                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString("last_sent_data", comment: ""))
                        .font(.headline)
                    
                    HStack {
                        Text(NSLocalizedString("time_label", comment: ""))
                        Spacer()
                        if let time = sender.lastSentTime {
                            Text(time.formatted(date: .omitted, time: .standard))
                                .font(.system(.body, design: .monospaced))
                        } else {
                            Text(NSLocalizedString("no_time", comment: ""))
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                    
                    HStack {
                        Text(NSLocalizedString("latitude_label", comment: ""))
                        Spacer()
                        if let lat = sender.lastSentLatitude {
                            Text(String(format: "%.6f°", lat))
                                .font(.system(.body, design: .monospaced))
                        } else {
                            Text(NSLocalizedString("no_coordinate", comment: ""))
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                    
                    HStack {
                        Text(NSLocalizedString("longitude_label", comment: ""))
                        Spacer()
                        if let lon = sender.lastSentLongitude {
                            Text(String(format: "%.6f°", lon))
                                .font(.system(.body, design: .monospaced))
                        } else {
                            Text("0.000000°")
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                    
                    HStack {
                        Text(NSLocalizedString("heading_label", comment: ""))
                        Spacer()
                        if let heading = sender.lastSentHeading {
                            Text(String(format: "%.1f°", heading))
                                .font(.system(.body, design: .monospaced))
                        } else {
                            Text("0.0°")
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal)
                
                VStack(alignment: .leading, spacing: 8){
                    HStack{
                        Text(NSLocalizedString("status_label", comment: ""))
                            .foregroundColor(sender.connectionStatus == .connected ? .green : .orange)
                            .padding()
                        Spacer()
                        Text(sender.connectionStatus.rawValue)
                            .foregroundColor(sender.connectionStatus == .connected ? .green : .orange)
                            .padding()
                    }
                }
                .padding(.horizontal)
                
                if sender.showErrorHistory {
                    VStack(alignment: .leading) {
                        Text(NSLocalizedString("send_error", comment: ""))
                            .font(.headline)
                            .foregroundColor(.red)

                        ScrollView {
                            ForEach(sender.lastErrors, id: \.self) { error in
                                Text(error)
                                    .foregroundColor(.red)
                                    .font(.subheadline)
                                    .padding(.vertical, 4)
                            }
                        }
                    }
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
                    .padding(.horizontal)
                }
                
                Spacer()
                
                Button(action: {
                    sender.toggleSending()
                }) {
                    Text(sender.isSending ? NSLocalizedString("stop_sending", comment: "") : NSLocalizedString("start_sending", comment: ""))
                        .padding()
                        .background(sender.isSending ? Color.red : Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }

            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        Button(action: {
                            showingInfo = true
                        }) {
                            Image(systemName: "info.circle")
                        }
                        
                        Button(action: {
                            showingSettings = true
                        }) {
                            Image(systemName: "gearshape")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showingInfo) {
                InfoView()
            }
        }
    }
}

#Preview {
    ContentView()
}
