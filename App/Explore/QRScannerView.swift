import SwiftUI
import UIKit
import AVFoundation
import PhotosUI
import ImageIO
import CoreImage
import BitcoinKit

/// Full-screen camera that reads QR codes on the device, or a QR code from a photo. It shows what it
/// found before opening it; codes it can't open say why.
struct QRScannerSheet: View {
    let tip: Int?
    let onOpen: (ExploreRoute) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var camera: CameraState = .checking
    @State private var scanned: String?
    @State private var photo: PhotosPickerItem?
    @State private var readingPhoto = false
    @State private var photoFailed = false

    enum CameraState { case checking, ready, denied, unsupported }

    /// Side of the frame drawn on screen; the camera reads a slightly larger square around it.
    static let frameSize: CGFloat = 240

    private var interpretation: SearchInterpretation? {
        scanned.map { SearchParser.interpret($0, tip: tip) }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch camera {
            case .ready:
                QRCameraView(paused: scanned != nil) { code in
                    if scanned == nil { scanned = code }
                }
                .ignoresSafeArea()
            case .checking:
                ProgressView().tint(.white)
            case .denied:
                cameraMessage("Camera access is off",
                              "Allow the camera for Blockpulse in Settings, or pick a photo with a QR code.")
            case .unsupported:
                cameraMessage("Scanning isn't available on this device", "Pick a photo with a QR code instead.")
            }
            if camera == .ready && scanned == nil { reticle }
            VStack {
                topBar
                Spacer()
                bottom
            }
            .padding(20)
        }
        .environment(\.colorScheme, .dark)
        .tint(Theme.orange)
        .sensoryFeedback(.success, trigger: scanned) { _, new in new != nil }
        .task { camera = await Self.prepareCamera() }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task { await read(item) }
        }
    }

    private var topBar: some View {
        HStack {
            Button("Close") { dismiss() }
                .fontWeight(.semibold)
                .foregroundStyle(.white)
            Spacer()
            if readingPhoto {
                ProgressView().tint(Theme.orange)
            } else {
                PhotosPicker(selection: $photo, matching: .images) {
                    Label("From photo", systemImage: "photo")
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.orange)
                }
            }
        }
    }

    private var reticle: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .strokeBorder(Theme.orange, lineWidth: 4)
            .frame(width: Self.frameSize, height: Self.frameSize)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var bottom: some View {
        if let code = scanned, let i = interpretation {
            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    if let target = i.target {
                        SectionLabel(target.title + (code.lowercased().hasPrefix("bitcoin:") ? " · payment link" : ""))
                        Text(i.query)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(.white)
                            .lineLimit(3)
                        if code.contains("?") && code.lowercased().hasPrefix("bitcoin:") {
                            Text("The amount and label in the link are ignored.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if let issue = i.issue {
                        Text(issue.title).font(.headline).foregroundStyle(.white)
                        Text(issue.message).font(.subheadline).foregroundStyle(.secondary)
                    } else {
                        Text("Not something Blockpulse can open").font(.headline).foregroundStyle(.white)
                        Text("This QR code isn't a Bitcoin address, transaction or block.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                HStack(spacing: 10) {
                    Button { scanned = nil } label: { Text("Scan again").frame(maxWidth: .infinity) }
                        .buttonStyle(.bordered)
                    if let target = i.target {
                        Button {
                            dismiss()
                            onOpen(target.route)
                        } label: { Text(openLabel(target)).frame(maxWidth: .infinity) }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .controlSize(.large)
            }
        } else if photoFailed {
            Text("No QR code found in that photo.")
                .font(.subheadline)
                .foregroundStyle(.white)
                .padding(12)
                .background(Theme.card, in: Capsule())
        } else if camera == .ready {
            Text("Point at a QR code with an address, transaction or payment link.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
        }
    }

    private func openLabel(_ target: SearchTarget) -> String {
        switch target {
        case .address: "Open address"
        case .transaction: "Open transaction"
        default: "Open block"
        }
    }

    private func cameraMessage(_ title: String, _ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "camera").font(.largeTitle).foregroundStyle(Theme.orange)
            Text(title).font(.headline).foregroundStyle(.white)
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(32)
    }

    private func read(_ item: PhotosPickerItem) async {
        photoFailed = false
        readingPhoto = true
        defer {
            readingPhoto = false
            // Lets the same photo be picked again.
            photo = nil
        }
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            photoFailed = true
            return
        }
        let message = await Task.detached(priority: .userInitiated) { QRPhotoReader.read(data) }.value
        if let message { scanned = message } else { photoFailed = true }
    }

    /// Asks for the camera the first time.
    private static func prepareCamera() async -> CameraState {
        guard AVCaptureDevice.default(for: .video) != nil else { return .unsupported }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return .ready
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video) ? .ready : .denied
        default: return .denied
        }
    }
}

/// Finds a QR code in a photo. Photos are shrunk first: a 48 MP image takes seconds to search at
/// full size, and a QR code stays readable at 2,000 pixels.
enum QRPhotoReader {
    private static let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil,
                                             options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])

    static func read(_ data: Data) -> String? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: 2000,
              ] as CFDictionary),
              let detector
        else { return nil }
        return detector.features(in: CIImage(cgImage: cg))
            .compactMap { ($0 as? CIQRCodeFeature)?.messageString }
            .first
    }
}

/// The camera, reading QR codes with AVFoundation's metadata output.
struct QRCameraView: UIViewControllerRepresentable {
    let paused: Bool
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> QRCaptureController {
        let controller = QRCaptureController()
        controller.onScan = onScan
        return controller
    }

    func updateUIViewController(_ controller: QRCaptureController, context: Context) {
        controller.onScan = onScan
        controller.paused = paused
    }

    static func dismantleUIViewController(_ controller: QRCaptureController, coordinator: ()) {
        controller.stop()
    }
}

/// Owns the capture session. Setup and start run on a background queue, so the screen is never held
/// up by the camera; codes arrive on the main queue.
final class QRCaptureController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onScan: ((String) -> Void)?
    /// While a result is on screen, codes are ignored but the camera keeps running, so "Scan again"
    /// is instant.
    var paused = false

    private let capture = CaptureBox()
    private let output = AVCaptureMetadataOutput()
    private let preview = AVCaptureVideoPreviewLayer()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        preview.videoGravity = .resizeAspectFill
        preview.session = capture.session
        view.layer.addSublayer(preview)
        output.setMetadataObjectsDelegate(self, queue: .main)
        NotificationCenter.default.addObserver(self, selector: #selector(sessionStarted),
                                               name: AVCaptureSession.didStartRunningNotification,
                                               object: capture.session)
        capture.start(output: output)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview.frame = view.bounds
        updateScanArea()
    }

    func stop() { capture.stop() }

    @objc private func sessionStarted() {
        DispatchQueue.main.async { self.updateScanArea() }
    }

    /// Reads only a square around the on-screen frame: less to search per frame, and no stray codes
    /// at the edges. Conversion needs a running session, so it repeats once the camera starts.
    private func updateScanArea() {
        guard capture.session.isRunning, view.bounds.width > 0 else { return }
        let side = min(min(view.bounds.width, view.bounds.height) * 0.9, QRScannerSheet.frameSize * 1.5)
        let square = CGRect(x: view.bounds.midX - side / 2, y: view.bounds.midY - side / 2, width: side, height: side)
        let area = preview.metadataOutputRectConverted(fromLayerRect: square)
        capture.queue.async { [output = self.output] in output.rectOfInterest = area }
    }

    nonisolated func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject],
                                    from connection: AVCaptureConnection) {
        let value = metadataObjects.lazy
            .compactMap { ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue }
            .first
        guard let value else { return }
        MainActor.assumeIsolated {
            guard !paused else { return }
            onScan?(value)
        }
    }
}

/// The session and its queue, kept off the main thread.
private final class CaptureBox: @unchecked Sendable {
    let session = AVCaptureSession()
    let queue = DispatchQueue(label: "se.blockpul.qr-capture")
    private var configured = false

    func start(output: AVCaptureMetadataOutput) {
        queue.async { [self] in
            if !configured {
                configured = true
                configure(output: output)
            }
            if !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        queue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    private func configure(output: AVCaptureMetadataOutput) {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else { return }
        session.beginConfiguration()
        // 720p is plenty for QR codes and starts faster than the photo presets.
        if session.canSetSessionPreset(.hd1280x720) { session.sessionPreset = .hd1280x720 }
        if session.canAddInput(input) { session.addInput(input) }
        if session.canAddOutput(output) {
            session.addOutput(output)
            if output.availableMetadataObjectTypes.contains(.qr) { output.metadataObjectTypes = [.qr] }
        }
        session.commitConfiguration()
        // QR codes are held close: focus near and keep refocusing.
        if (try? device.lockForConfiguration()) != nil {
            if device.isAutoFocusRangeRestrictionSupported { device.autoFocusRangeRestriction = .near }
            if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
            device.unlockForConfiguration()
        }
    }
}
