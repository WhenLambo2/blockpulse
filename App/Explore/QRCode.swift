import SwiftUI
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins
import BitcoinKit

enum QRCodeImage {
    /// Black on white with crisp modules, `scale` pixels per module.
    static func make(_ string: String, scale: CGFloat = 12) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: scale, y: scale)),
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
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
    @State private var saved = false
    @State private var copied = false

    private var qr: UIImage? { QRCodeImage.make(payload) }

    /// The card as a picture, for saving and sharing.
    @MainActor
    private func cardImage(_ qr: UIImage) -> UIImage? {
        let renderer = ImageRenderer(content: QRCard(kind: kind, value: value, image: qr))
        renderer.scale = 3
        return renderer.uiImage
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let qr {
                        QRCard(kind: kind, value: value, image: qr)
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        actions(qr)
                    } else {
                        ExploreMessage(title: "Couldn't make a QR code", message: "Copy the text instead.",
                                       systemImage: "qrcode")
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
    }

    private func actions(_ qr: UIImage) -> some View {
        let image = cardImage(qr) ?? qr
        return VStack(spacing: 10) {
            Button {
                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                saved = true
            } label: {
                Label(saved ? "Saved to Photos" : "Save to Photos", systemImage: saved ? "checkmark" : "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .sensoryFeedback(.success, trigger: saved) { _, new in new }
            HStack(spacing: 10) {
                ShareLink(item: Image(uiImage: image), preview: SharePreview("\(kind) QR code", image: Image(uiImage: image))) {
                    Label("Share QR", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                }
                Button {
                    UIPasteboard.general.string = value
                    copied = true
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            if let shareURL {
                ShareLink(item: shareURL) {
                    Label("Share link to this page", systemImage: "link").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
    }
}
