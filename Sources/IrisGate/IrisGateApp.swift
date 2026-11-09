import SwiftUI

@main struct IrisGateApp: App {
    @StateObject private var state = AppState()
    var body: some Scene {
        WindowGroup("IrisGate") {
            Dashboard().environmentObject(state).frame(minWidth: 860, minHeight: 620)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1040, height: 740)
        .commands {
            CommandMenu("IrisGate") {
                Button("Lock IrisGate") { state.lock() }.keyboardShortcut("l", modifiers: [.command, .shift])
                Button("Stop Camera") { state.stopCamera() }
            }
        }
        MenuBarExtra("IrisGate", systemImage: "viewfinder") {
            Text(state.unlocked ? "IrisGate unlocked" : "IrisGate locked")
            Button("Show IrisGate") { NSApp.activate(ignoringOtherApps: true); NSApp.windows.first?.makeKeyAndOrderFront(nil) }
            Button("Lock IrisGate") { state.lock() }
            Button("Stop Camera") { state.stopCamera() }
            Divider()
            Button("Quit IrisGate") { state.stopCamera(); NSApp.terminate(nil) }
        }
    }
}

struct Dashboard: View {
    @EnvironmentObject private var state: AppState
    @State private var section = "Overview"
    @State private var confirmErase = false
    private let mint = Color(red: 0.63, green: 0.94, blue: 0.78)
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 30) {
                HStack { Image(systemName: "viewfinder").font(.title); Text("IrisGate").font(.title2.bold()) }.foregroundStyle(mint)
                    .padding(.top, 30)
                Text("PRESENCE, PRIVATELY.").font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundStyle(.secondary)
                VStack(spacing: 8) {
                    nav("Overview", "square.grid.2x2")
                    nav("Your face", "person.crop.circle")
                    nav("Recognition", "viewfinder.circle")
                    nav("About", "info.circle")
                }
                Spacer()
                Label("On-device processing", systemImage: "lock.shield").font(.caption).foregroundStyle(mint)
                Text("0.1.0 · EXPERIMENTAL").font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
            }.padding(24).frame(width: 210).background(Color.white.opacity(0.035))
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        Text("WORKSPACE / \(section.uppercased())").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                        Spacer()
                        Label(state.cameraRunning ? "Camera active" : "Camera off", systemImage: "circle.fill")
                            .font(.caption).foregroundStyle(state.cameraRunning ? mint : .secondary)
                    }
                    if section == "About" { about }
                    else if section == "Recognition" { recognition }
                    else {
                        Text(section == "Your face" ? "A familiar face.\nA private identity." : "Welcome to\nyour own space.")
                            .font(.system(size: 42, weight: .medium, design: .rounded)).tracking(-1.5)
                        Text("A local face-recognition workspace for your Mac.").foregroundStyle(.secondary)
                        cameraCard
                        HStack(alignment: .top, spacing: 12) {
                            metric("01", "Face model", state.modelReady ? state.modelName : "Bring your own licensed model")
                            metric("02", "Enrollment", state.enrolled ? "Stored in Keychain" : "Not enrolled yet")
                            metric("03", "App gate", state.unlocked ? "Unlocked" : "Locked")
                        }
                        setupControls
                    }
                }.padding(36)
            }
        }.background(Color(red: 0.055, green: 0.065, blue: 0.063))
            .alert("IrisGate", isPresented: Binding(get: { state.error != nil }, set: { if !$0 { state.error = nil } })) {
                Button("OK") { state.error = nil }
            } message: { Text(state.error ?? "") }
            .confirmationDialog("Delete the face enrollment stored by IrisGate?", isPresented: $confirmErase) {
                Button("Delete enrollment", role: .destructive) { state.eraseEnrollment() }
                Button("Cancel", role: .cancel) {}
            }
    }
    private func nav(_ name: String, _ icon: String) -> some View {
        Button { section = name } label: {
            Label(name, systemImage: icon).frame(maxWidth: .infinity, alignment: .leading).padding(12)
                .background(section == name ? mint.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(section == name ? mint : .secondary)
        }.buttonStyle(.plain)
    }
    private var cameraCard: some View {
        ZStack {
            if state.cameraRunning { CameraPreview(session: state.camera.session) }
            else { Color.white.opacity(0.025) }
            VStack(spacing: 14) {
                Image(systemName: state.unlocked ? "lock.open" : "viewfinder")
                    .font(.system(size: 66, weight: .ultraLight)).foregroundStyle(mint)
                if !state.cameraRunning {
                    Text(state.unlocked ? "You’re in." : "Your camera is resting.").font(.title3)
                    Text("Only start it when you’re ready.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(state.instruction).font(.callout.weight(.medium)).padding(12)
                    .background(.black.opacity(0.72), in: Capsule())
            }.padding(28)
        }.frame(height: 265).clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(mint.opacity(0.15)))
            .overlay(alignment: .topLeading) {
                Text(state.scanning ? "RECOGNIZING" : state.enrolling ? "ENROLLING" : "PREVIEW")
                    .font(.system(size: 9, design: .monospaced)).padding(12)
            }
    }
    private func metric(_ number: String, _ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(number).font(.system(size: 10, design: .monospaced)).foregroundStyle(mint)
            Text(title).font(.headline)
            Text(value).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }.frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading).padding(16)
            .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
    }
    private var setupControls: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button("Import face model…") { state.importModel() }
                Button(state.enrolling ? "Restart enrollment" : "Enroll your face") { state.beginEnrollment() }.disabled(!state.modelReady)
                Spacer()
                Button(state.cameraRunning ? "Stop camera" : "Preview camera") {
                    if state.cameraRunning { state.stopCamera() } else { state.startCamera() }
                }
            }
            HStack {
                Button(state.scanning ? "Restart test" : "Test face unlock") { state.beginRecognition() }
                    .buttonStyle(.borderedProminent).tint(mint).foregroundStyle(.black)
                    .disabled(!state.enrolled || !state.modelReady)
                Button("Use Touch ID or password") { state.systemAuthentication() }
                if state.unlocked { Button("Lock app") { state.lock() } }
            }
            Text(state.status).font(.caption).foregroundStyle(.secondary)
            Text("Unlocks this app only. Does not unlock macOS or replace Touch ID.")
                .font(.caption).foregroundStyle(mint.opacity(0.8))
            if state.enrolled {
                Button("Delete enrollment…", role: .destructive) { confirmErase = true }.buttonStyle(.link)
            }
        }.controlSize(.large)
    }
    private var recognition: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Recognition,\non your terms.").font(.system(size: 42, weight: .medium, design: .rounded))
            GroupBox("Camera") {
                Picker("Device", selection: $state.cameraID) {
                    Text("Default camera").tag("")
                    ForEach(state.devices, id: \.uniqueID) { Text($0.localizedName).tag($0.uniqueID) }
                }.padding().onChange(of: state.cameraID) { _, _ in state.changeCamera() }
            }
            GroupBox("Match threshold") {
                VStack(alignment: .leading) {
                    Slider(value: $state.threshold, in: 0.5...0.95, step: 0.01)
                    Text(String(format: "%.2f · Higher values require a closer match", state.threshold)).font(.caption)
                    Text("Experimental default. Calibrate your model before relying on its scores.").foregroundStyle(.secondary).font(.caption)
                }.padding()
            }
            GroupBox("Motion challenge") {
                Text("Look forward, turn in a randomly selected direction, then return to center. A matching face must remain visible throughout. This is a basic motion demonstration, not validated spoof resistance.")
                    .padding().foregroundStyle(.secondary)
            }
            if let score = state.score { Text(String(format: "Latest cosine similarity: %.3f", score)).monospaced() }
            setupControls
        }
    }
    private var about: some View {
        VStack(alignment: .leading, spacing: 24) {
            Image(systemName: "viewfinder").font(.system(size: 72, weight: .ultraLight)).foregroundStyle(mint)
            Text("IrisGate").font(.system(size: 46, weight: .medium, design: .rounded))
            Text("Your presence. Your device.").font(.title2).foregroundStyle(.secondary)
            Text("An original SwiftUI implementation informed by static inspection of Glance 1.2. No Glance binary, artwork, animations, or model weights are included.")
            Text("Camera frames are processed in memory. Enrollment vectors stay in the local Keychain. IrisGate has no network client, analytics, account service, or password capture.")
            Text("This research prototype demonstrates face enrollment and an app gate. The model, alignment, threshold, and motion checks have not been validated as an authentication system. Keep macOS authentication enabled.")
                .foregroundStyle(.secondary)
            Link("View project on GitHub", destination: URL(string: "https://github.com/anasbinasad/irisgate")!)
            Text("Version 0.1.0 · macOS 15+").font(.caption.monospaced()).foregroundStyle(.secondary)
        }.lineSpacing(5)
    }
}
