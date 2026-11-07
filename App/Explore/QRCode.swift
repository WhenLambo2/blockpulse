import SwiftUI
import UIKit
import Photos
import CoreImage
import CoreImage.CIFilterBuiltins
import BitcoinKit

enum QRCodeImage {
    /// One context for every code: creating a CIContext is the slow part.
    private static let context = CIContext()

    /// Black on white with crisp modules, `scale` pixels per module.
    static func make(_ string: String, scale: CGFloat = 12) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: scale, y: scale)),
              let cg = context.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// The QR code with what it holds, as shown in the sheet and saved as an image.
struct QRCard: View {
    let kind: String
    let value: String
    let image: UIImage

    var body: some View {
        VStack(spacing: 14) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: 240, height: 240)
                .padding(14)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .accessibilityLabel("QR code for this \(kind.lowercased())")
            VStack(spacing: 6) {
                Text(kind.uppercased())
                    .font(.caption2.weight(.semibold))
                    .tracking(0.8)
                    .foregroundStyle(Theme.orange)
                Text(value)
                    .font(.system(.footnote, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 6) {
                BrandSymbol(height: 14).environment(\.colorScheme, .dark)
                Text("Blockpulse").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(.white)
            }
            .opacity(0.8)
            .accessibilityHidden(true)
        }
        .padding(24)
        .frame(width: 340)
        .background(D9.tile)
    }
}

/// QR code for an address or transaction, with save, share and copy.
struct QRCodeSheet: View {
    let kind: String
    /// Shown under the code.
    let value: String
    /// What the code holds.
    let payload: String
    let shareURL: URL?

    @Environment(\.dismiss) private var dismiss
    @State private var qr: UIImage?
    @State private var failed = false
    @State private var save: SaveState = .idle
    @State private var copied = false

    enum SaveState { case idle, saving, saved, denied, failed }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let qr {
                        QRCard(kind: kind, value: value, image: qr)
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        actions(qr)
                    } else if failed {
                        ExploreMessage(title: "Couldn't make a QR code", message: "Copy the text instead.",
                                       systemImage: "qrcode")
                    } else {
                        ProgressView().tint(Theme.orange).frame(height: 420)
                    }
                }
                .padding(20)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("QR code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.large])
        .tint(Theme.orange)
        // Built once, off the main thread, while the sheet slides up.
        .task {
            let payload = payload
            let image = await Task.detached(priority: .userInitiated) { QRCodeImage.make(payload) }.value
            if let image { qr = image } else { failed = true }
        }
    }

    /// The card as a picture, drawn only when it is saved or shared.
    private func cardImage(_ qr: UIImage) -> UIImage {
        let renderer = ImageRenderer(content: QRCard(kind: kind, value: value, image: qr))
        renderer.scale = 3
        return renderer.uiImage ?? qr
    }

    private func actions(_ qr: UIImage) -> some View {
        VStack(spacing: 10) {
            Button { saveToPhotos(qr) } label: {
                Label(saveTitle, systemImage: save == .saved ? "checkmark" : "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(save == .saving)
            .sensoryFeedback(.success, trigger: save) { _, new in new == .saved }
            if save == .denied {
                Text("Allow Blockpulse to add photos in Settings → Privacy & Security → Photos.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 10) {
                Button { Share.image(cardImage(qr), title: "\(kind) QR code") } label: {
                    Label("Share QR", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                }
                Button {
                    UIPasteboard.general.string = value
                    copied = true
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc").frame(maxWidth: .infinity)
                }
                .task(id: copied) {
                    guard copied else { return }
                    try? await Task.sleep(for: .seconds(2))
                    copied = false
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            if let shareURL {
                Button { Share.link(shareURL, title: "\(kind) \(Format.short(value))") } label: {
                    Label("Share link to this page", systemImage: "link").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
    }

    private var saveTitle: String {
        switch save {
        case .idle, .denied: "Save to Photos"
        case .saving: "Saving…"
        case .saved: "Saved to Photos"
        case .failed: "Couldn't save, try again"
        }
    }

    /// Asks only to add photos, never to read them, and reports what really happened.
    private func saveToPhotos(_ qr: UIImage) {
        let image = cardImage(qr)
        save = .saving
        Task {
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else {
                save = .denied
                return
            }
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                }
                save = .saved
            } catch {
                save = .failed
            }
        }
    }
}
