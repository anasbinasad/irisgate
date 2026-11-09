import AVFoundation
import Vision
import AppKit
import SwiftUI

struct FaceFrame {
    var count = 0
    var yaw: Double = 0
    var embedding: [Float]?
    var message = "Look toward the camera"
    var timestamp = Date.timeIntervalSinceReferenceDate
}

final class Camera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "irisgate.camera", qos: .userInitiated)
    private var model: FaceModel?
    private var lastFrame: TimeInterval = 0
    var onFrame: ((FaceFrame) -> Void)?
    var onError: ((String) -> Void)?

    static var devices: [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video, position: .unspecified).devices
    }

    func setModel(_ model: FaceModel?) { queue.async { self.model = model } }

    func start(deviceID: String) {
        queue.async {
            do {
                self.session.stopRunning()
                self.session.beginConfiguration()
                for input in self.session.inputs { self.session.removeInput(input) }
                for output in self.session.outputs { self.session.removeOutput(output) }
                self.session.sessionPreset = .vga640x480
                guard let device = Self.devices.first(where: { $0.uniqueID == deviceID }) ?? Self.devices.first else {
                    self.session.commitConfiguration()
                    throw IrisError.message("No camera found. Connect a camera and try again.")
                }
                let input: AVCaptureDeviceInput
                do { input = try AVCaptureDeviceInput(device: device) }
                catch { self.session.commitConfiguration(); throw error }
                guard self.session.canAddInput(input) else {
                    self.session.commitConfiguration(); throw IrisError.message("Camera input unavailable")
                }
                self.session.addInput(input)
                let output = AVCaptureVideoDataOutput()
                output.alwaysDiscardsLateVideoFrames = true
                output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                output.setSampleBufferDelegate(self, queue: self.queue)
                guard self.session.canAddOutput(output) else {
                    self.session.commitConfiguration(); throw IrisError.message("Camera output unavailable")
                }
                self.session.addOutput(output)
                self.session.commitConfiguration()
                self.session.startRunning()
            } catch { DispatchQueue.main.async { self.onError?(error.localizedDescription) } }
        }
    }

    func stop() { queue.async { self.session.stopRunning() } }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        let now = Date.timeIntervalSinceReferenceDate
        guard now - lastFrame >= 0.18, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastFrame = now
        var frame = FaceFrame(timestamp: now)
        do {
            let request = VNDetectFaceLandmarksRequest()
            try VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up).perform([request])
            let faces = request.results ?? []
            frame.count = faces.count
            if faces.count == 1, let face = faces.first {
                frame.yaw = face.yaw?.doubleValue ?? 0
                if face.boundingBox.width < 0.18 {
                    frame.message = "Move closer to the camera"
                } else if abs(frame.yaw) > 0.65 {
                    frame.message = "Turn slightly back toward the camera"
                } else if face.yaw == nil {
                    frame.message = "Face pose unavailable"
                } else if let model {
                    frame.embedding = try model.embedding(pixelBuffer: buffer, face: face)
                    frame.message = "Face detected"
                } else { frame.message = "Import a face model to continue" }
            } else { frame.message = faces.isEmpty ? "No face in view" : "Only one person should be in view" }
        } catch { frame.message = error.localizedDescription }
        DispatchQueue.main.async { self.onFrame?(frame) }
    }
}

struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    final class Preview: NSView {
        let preview = AVCaptureVideoPreviewLayer()
        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            preview.videoGravity = .resizeAspectFill
            layer?.addSublayer(preview)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is unsupported") }
        override func layout() { super.layout(); preview.frame = bounds }
    }
    func makeNSView(context: Context) -> Preview {
        let view = Preview(frame: .zero); view.preview.session = session; return view
    }
    func updateNSView(_ view: Preview, context: Context) { view.preview.session = session }
}
