import AVFoundation
import CoreMotion
import Foundation
import Observation

/// Partie AVFoundation de la caméra, exécutée sur une file dédiée.
/// Les résultats sont renvoyés au fil principal via des fermetures.
final class CameraSession: NSObject, @unchecked Sendable, AVCapturePhotoCaptureDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "app.growtin.camera.session")
    private let videoQueue = DispatchQueue(label: "app.growtin.camera.video")
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private var input: AVCaptureDeviceInput?
    private var outputsAdded = false
    private var photoHandler: ((Data?) -> Void)?
    private var lastBrightnessUpdate = Date.distantPast
    var onBrightness: ((Double) -> Void)?

    static func hasCamera(position: AVCaptureDevice.Position) -> Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) != nil
    }

    func configure(position: AVCaptureDevice.Position, completion: @escaping (Bool) -> Void) {
        queue.async { [self] in
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
                  let newInput = try? AVCaptureDeviceInput(device: device) else {
                completion(false)
                return
            }
            session.beginConfiguration()
            session.sessionPreset = .photo
            if let input { session.removeInput(input) }
            guard session.canAddInput(newInput) else {
                session.commitConfiguration()
                completion(false)
                return
            }
            session.addInput(newInput)
            input = newInput
            if !outputsAdded {
                if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }
                videoOutput.alwaysDiscardsLateVideoFrames = true
                videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
                videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
                if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }
                outputsAdded = true
            }
            session.commitConfiguration()
            if !session.isRunning { session.startRunning() }
            completion(true)
        }
    }

    func stop() {
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    func capture(completion: @escaping (Data?) -> Void) {
        queue.async { [self] in
            guard session.isRunning else {
                completion(nil)
                return
            }
            photoHandler = completion
            let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data = error == nil ? photo.fileDataRepresentation() : nil
        let handler = photoHandler
        photoHandler = nil
        handler?(data)
    }

    /// Luminosité moyenne du flux vidéo (canal de luminance), environ trois fois par seconde.
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = Date()
        guard now.timeIntervalSince(lastBrightnessUpdate) > 0.33,
              let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastBrightnessUpdate = now
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) else { return }
        let width = CVPixelBufferGetWidthOfPlane(buffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(buffer, 0)
        let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        let pointer = base.assumingMemoryBound(to: UInt8.self)
        var total = 0, count = 0
        var y = 0
        while y < height {
            var x = 0
            while x < width {
                total += Int(pointer[y * bytesPerRow + x])
                count += 1
                x += 16
            }
            y += 16
        }
        guard count > 0 else { return }
        onBrightness?(Double(total) / Double(count) / 255)
    }
}

/// État observable de la caméra pour l'interface.
@MainActor
@Observable
final class CameraController {
    enum Status: Equatable { case idle, running, unavailable, denied, failed }

    private(set) var status: Status = .idle
    private(set) var position: AVCaptureDevice.Position
    private(set) var liveBrightness: Double?
    private(set) var isCapturing = false
    @ObservationIgnored let cameraSession = CameraSession()

    init(position: AVCaptureDevice.Position) {
        self.position = position
        cameraSession.onBrightness = { [weak self] value in
            Task { @MainActor in self?.liveBrightness = value }
        }
    }

    var isFrontCamera: Bool { position == .front }

    func start() async {
        guard CameraSession.hasCamera(position: position) || CameraSession.hasCamera(position: .back) else {
            status = .unavailable
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                status = .denied
                return
            }
        default:
            status = .denied
            return
        }
        if !CameraSession.hasCamera(position: position) { position = position == .front ? .back : .front }
        await configure()
    }

    func flip() async {
        let next: AVCaptureDevice.Position = position == .front ? .back : .front
        guard CameraSession.hasCamera(position: next) else { return }
        position = next
        await configure()
    }

    func stop() {
        cameraSession.stop()
        status = .idle
    }

    func capture() async -> Data? {
        isCapturing = true
        defer { isCapturing = false }
        return await withCheckedContinuation { continuation in
            cameraSession.capture { data in continuation.resume(returning: data) }
        }
    }

    private func configure() async {
        let success = await withCheckedContinuation { continuation in
            cameraSession.configure(position: position) { continuation.resume(returning: $0) }
        }
        status = success ? .running : .failed
    }
}

/// Inclinaison de l'appareil, pour reproduire le même angle d'une photo à l'autre.
@MainActor
@Observable
final class MotionMonitor {
    private(set) var pitch: Double?
    private(set) var roll: Double?
    @ObservationIgnored private let manager = CMMotionManager()

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 15
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let attitude = motion?.attitude else { return }
            let pitch = attitude.pitch * 180 / .pi
            let roll = attitude.roll * 180 / .pi
            Task { @MainActor in
                self?.pitch = pitch
                self?.roll = roll
            }
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }
}
