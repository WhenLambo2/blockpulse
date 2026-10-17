import SwiftUI
import UIKit
import VisionKit
import AVFoundation
import PhotosUI
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
    @State private var photoFailed = false

    enum CameraState { case checking, ready, denied, unsupported }

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
            VStack {
                topBar
                Spacer()
                if camera == .ready && scanned == nil { reticle }
                Spacer()
                bottom
            }
            .padding(20)
        }
        .preferredColorScheme(.dark)
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
            PhotosPicker(selection: $photo, matching: .images) {
                Label("From photo", systemImage: "photo")
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.orange)
            }
        }
    }

    private var reticle: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .strokeBorder(Theme.orange, lineWidth: 4)
            .frame(width: 240, height: 240)
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
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = CIImage(data: data),
              let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]),
              let message = detector.features(in: image).compactMap({ ($0 as? CIQRCodeFeature)?.messageString }).first
        else {
            photoFailed = true
            return
        }
        scanned = message
    }

    /// Asks for the camera the first time; the scanner itself needs the permission and a capable device.
    private static func prepareCamera() async -> CameraState {
        guard DataScannerViewController.isSupported else { return .unsupported }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else { return .denied }
        default:
            return .denied
        }
        return DataScannerViewController.isAvailable ? .ready : .denied
    }
}

/// VisionKit's scanner, looking for QR codes only.
struct QRCameraView: UIViewControllerRepresentable {
    let paused: Bool
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        // Starting only works once the scanner is on screen.
        DispatchQueue.main.async { try? scanner.startScanning() }
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.onScan = onScan
        if paused {
            if scanner.isScanning { scanner.stopScanning() }
        } else if !scanner.isScanning {
            try? scanner.startScanning()
        }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onScan: (String) -> Void

        init(onScan: @escaping (String) -> Void) { self.onScan = onScan }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in addedItems {
                if case .barcode(let code) = item, let value = code.payloadStringValue {
                    onScan(value)
                    return
                }
            }
        }
    }
}
