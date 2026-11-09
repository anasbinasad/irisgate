import SwiftUI
import AVFoundation
import CryptoKit
import LocalAuthentication
import IrisGateCore

@MainActor final class AppState: ObservableObject {
    let camera = Camera()
    @Published var cameraRunning = false
    @Published var cameraID = UserDefaults.standard.string(forKey: "cameraID") ?? ""
    @Published var devices = Camera.devices
    @Published var modelName = "No model imported"
    @Published var modelReady = false
    @Published var enrolled = false
    @Published var enrolling = false
    @Published var sampleCount = 0
    @Published var scanning = false
    @Published var unlocked = false
    @Published var status = "Your presence. Your device."
    @Published var instruction = "Import a model, then enroll your face."
    @Published var score: Float?
    @Published var error: String?
    @Published var threshold: Double = {
        let saved = UserDefaults.standard.double(forKey: "threshold")
        return (0.5...0.95).contains(saved) ? saved : 0.72
    }() {
        didSet { UserDefaults.standard.set(threshold, forKey: "threshold"); cancelOperation() }
    }
    private var model: FaceModel?
    private var enrollment: Enrollment?
    private var samples: [[Float]] = []
    private var gate = RecognitionGate()
    private var operationStarted: TimeInterval = 0
    private var lastSample: TimeInterval = 0
    private var timer: Timer?
    private var authContext: LAContext?
    private var operationID = UUID()

    init() {
        do { enrollment = try SecureStore.load(); enrolled = enrollment != nil }
        catch { self.error = error.localizedDescription }
        camera.onFrame = { [weak self] frame in self?.receive(frame) }
        camera.onError = { [weak self] message in
            self?.error = message; self?.stopCamera()
        }
        if let path = UserDefaults.standard.string(forKey: "modelPath") {
            do { try loadModel(URL(fileURLWithPath: path)) }
            catch { self.error = "Stored model could not be loaded: \(error.localizedDescription)" }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.willResignActiveNotification,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.authContext == nil else { return }
                    self.stopCamera(); self.lock()
                }
            }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.stopCamera() }
            }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkTimeout() }
        }
    }

    func importModel() {
        cancelOperation(); stopCamera()
        let panel = NSOpenPanel()
        panel.title = "Import your licensed Core ML face model"
        panel.message = "Select an .mlmodel, .mlpackage, or .mlmodelc with input_image (112×112) and embedding (512)."
        panel.canChooseDirectories = true; panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try loadModel(url) } catch { self.error = error.localizedDescription }
    }

    private func loadModel(_ url: URL) throws {
        let loaded = try FaceModel(url: url)
        model = loaded; camera.setModel(loaded)
        modelName = url.lastPathComponent; modelReady = true
        UserDefaults.standard.set(url.path, forKey: "modelPath")
        if let enrollment, enrollment.modelDigest != loaded.digest {
            instruction = "Model changed. Enroll again before recognition."
        } else { instruction = enrolled ? "Ready for an app unlock test." : "Ready to enroll your face." }
    }

    func startCamera() {
        guard !cameraRunning else { return }
        Task {
            let allowed: Bool
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: allowed = true
            case .notDetermined: allowed = await AVCaptureDevice.requestAccess(for: .video)
            default: allowed = false
            }
            guard allowed else {
                error = "Enable Camera access for IrisGate in System Settings → Privacy & Security → Camera."
                return
            }
            devices = Camera.devices
            cameraRunning = true
            camera.start(deviceID: cameraID)
            status = "Camera active · processing on this Mac"
        }
    }

    func stopCamera() {
        camera.stop(); cameraRunning = false; cancelOperation()
        status = "Camera off"
    }

    func changeCamera() {
        UserDefaults.standard.set(cameraID, forKey: "cameraID")
        cancelOperation()
        if cameraRunning { camera.start(deviceID: cameraID) }
    }

    func beginEnrollment() {
        guard modelReady else { return }
        cancelOperation(); unlocked = false
        samples = []; sampleCount = 0; enrolling = true
        operationStarted = Date.timeIntervalSinceReferenceDate
        instruction = "Look straight at the camera · 0 / 9"
        startCamera()
    }

    func beginRecognition() {
        guard let enrollment, let model, enrollment.modelDigest == model.digest else {
            error = "Enroll with the current model first."; return
        }
        cancelOperation(); unlocked = false; scanning = true
        gate = RecognitionGate()
        operationStarted = Date.timeIntervalSinceReferenceDate
        instruction = "Look straight at the camera"
        startCamera()
    }

    func cancelOperation() {
        operationID = UUID(); authContext?.invalidate(); authContext = nil
        enrolling = false; scanning = false; samples = []; sampleCount = 0
        score = nil; gate.reset()
    }

    func lock() {
        unlocked = false; cancelOperation()
        instruction = "App locked. Start a new recognition test."
    }

    func eraseEnrollment() {
        do {
            try SecureStore.delete(); enrollment = nil; enrolled = false
            lock(); instruction = "Enrollment removed from Keychain."
        } catch { self.error = error.localizedDescription }
    }

    func systemAuthentication() {
        cancelOperation()
        let context = LAContext(); authContext = context
        let id = operationID
        context.evaluatePolicy(.deviceOwnerAuthentication,
            localizedReason: "Unlock the IrisGate demonstration") { [weak self] success, error in
                Task { @MainActor in
                    guard let self, self.operationID == id else { return }
                    if success { self.unlocked = true; self.instruction = "App unlocked using macOS authentication." }
                    else if let error { self.error = error.localizedDescription }
                    self.authContext = nil
                }
            }
    }

    private func checkTimeout() {
        if (enrolling || scanning), Date.timeIntervalSinceReferenceDate - operationStarted > (enrolling ? 45 : 15) {
            cancelOperation(); instruction = "Timed out. Try again in steady lighting."
        }
    }

    private func receive(_ frame: FaceFrame) {
        guard cameraRunning else { return }
        // Reject delayed queued frames from earlier operations.
        guard frame.timestamp >= operationStarted || !(enrolling || scanning) else { return }
        status = frame.message
        guard let vector = frame.embedding, frame.count == 1, let model else {
            if scanning { gate.reset(); score = nil }
            return
        }
        if enrolling {
            let pose = samples.count / 3
            let correctPose = pose == 0 ? abs(frame.yaw) < 0.14 :
                (pose == 1 ? frame.yaw > 0.20 : frame.yaw < -0.20)
            instruction = ["Look straight ahead", "Turn your head slightly left", "Turn your head slightly right"][min(pose, 2)] + " · \(sampleCount) / 9"
            guard correctPose, frame.timestamp - lastSample > 0.4 else { return }
            if let reference = samples.first,
               (Embeddings.cosine(reference, vector) ?? -1) < Float(threshold) {
                status = "Face changed or pose is too different. Return to center."; return
            }
            lastSample = frame.timestamp; samples.append(vector); sampleCount = samples.count
            if samples.count == 9 {
                let record = Enrollment(modelDigest: model.digest, samples: samples)
                do {
                    try SecureStore.save(record); enrollment = record; enrolled = true
                    cancelOperation(); instruction = "Enrollment saved in your Mac’s Keychain."
                } catch { self.error = error.localizedDescription; cancelOperation() }
            }
        } else if scanning {
            score = enrollment?.similarity(to: vector, modelDigest: model.digest)
            let verified = gate.observe(similarity: score, threshold: Float(threshold), yaw: frame.yaw,
                                       faceCount: frame.count, timestamp: frame.timestamp)
            switch gate.phase {
            case .center: instruction = "Look straight at the camera"
            case .turn: instruction = gate.direction > 0 ? "Turn your head slightly left" : "Turn your head slightly right"
            case .returnToCenter: instruction = "Return to center"
            case .verified: instruction = "Presence verified. App unlocked."
            }
            if verified { scanning = false; unlocked = true; camera.stop(); cameraRunning = false }
        }
    }
}
