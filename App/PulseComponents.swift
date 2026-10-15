import SwiftUI
import BitcoinKit

/// A card with a tappable header that folds its content. The open/closed state is remembered per card.
struct FoldableCard<Accessory: View, Content: View>: View {
    let title: String
    let systemImage: String
    @AppStorage private var isOpen: Bool
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var content: () -> Content

    init(_ title: String, systemImage: String, key: String, openByDefault: Bool = true,
         @ViewBuilder accessory: @escaping () -> Accessory,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.systemImage = systemImage
        _isOpen = AppStorage(wrappedValue: openByDefault, "fold.\(key)")
        self.accessory = accessory
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                withAnimation(.snappy(duration: 0.3)) { isOpen.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: systemImage)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.orange)
                        .frame(width: 22)
                    Text(title).font(.headline)
                    Spacer(minLength: 8)
                    accessory()
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isOpen ? 0 : -90))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(isOpen ? "Folds this card" : "Unfolds this card")

            if isOpen {
                content()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .card()
    }
}

extension FoldableCard where Accessory == EmptyView {
    init(_ title: String, systemImage: String, key: String, openByDefault: Bool = true,
         @ViewBuilder content: @escaping () -> Content) {
        self.init(title, systemImage: systemImage, key: key, openByDefault: openByDefault,
                  accessory: { EmptyView() }, content: content)
    }
}

/// Isometric block in the logo's three shades. `intensity` (0...1) dims it for low-fee projected blocks.
struct BlockCube: View {
    var intensity: Double = 1
    var size: CGFloat = 44

    var body: some View {
        Canvas { context, canvas in
            let w = canvas.width, h = canvas.height
            let top = Path { p in
                p.move(to: CGPoint(x: w / 2, y: 0))
                p.addLine(to: CGPoint(x: w, y: h * 0.25))
                p.addLine(to: CGPoint(x: w / 2, y: h * 0.5))
                p.addLine(to: CGPoint(x: 0, y: h * 0.25))
                p.closeSubpath()
            }
            let left = Path { p in
                p.move(to: CGPoint(x: 0, y: h * 0.25))
                p.addLine(to: CGPoint(x: w / 2, y: h * 0.5))
                p.addLine(to: CGPoint(x: w / 2, y: h))
                p.addLine(to: CGPoint(x: 0, y: h * 0.75))
                p.closeSubpath()
            }
            let right = Path { p in
                p.move(to: CGPoint(x: w / 2, y: h * 0.5))
                p.addLine(to: CGPoint(x: w, y: h * 0.25))
                p.addLine(to: CGPoint(x: w, y: h * 0.75))
                p.addLine(to: CGPoint(x: w / 2, y: h))
                p.closeSubpath()
            }
            context.opacity = intensity
            context.fill(top, with: .color(Theme.orange))
            context.fill(left, with: .color(Theme.orangeMid))
            context.fill(right, with: .color(Theme.orangeDeep))
        }
        .frame(width: size, height: size * 1.08)
        .accessibilityHidden(true)
    }
}

struct ProgressRing: View {
    let progress: Double
    var lineWidth: CGFloat = 10

    var body: some View {
        ZStack {
            Circle().stroke(Theme.orange.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(
                    AngularGradient(colors: [Theme.orangeDeep, Theme.orangeMid, Theme.orange], center: .center),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
    }
}

/// Timing of the block-found celebration, shared by the line, the card and the block number.
enum BlockFound {
    static let length: TimeInterval = 3.0
    /// Share of the celebration spent racing along the line before it bursts through the card.
    static let race: Double = 0.3
    static var burstDelay: TimeInterval { length * race }
}

/// The heartbeat line from the logo. While waiting for the next block a glow travels along it;
/// when `beat` changes (a new block, or the easter egg) the glow races along it, shaking,
/// and the line lights up and spikes while a ring ripples out from the peak.
struct HeartbeatLine: View {
    var beat: Int
    @State private var celebrationStart: Date?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let searchPeriod: TimeInterval = 3.4
    /// Where the peak sits along the line (matches HeartbeatShape).
    static let peakX: CGFloat = 0.56

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: scenePhase != .active || (reduceMotion && celebrationStart == nil))) { context in
            let now = context.date
            let celebration = celebrationStart.map { min(1, now.timeIntervalSince($0) / BlockFound.length) }
            GeometryReader { geo in
                ZStack {
                    if let p = celebration, p < 1 {
                        celebrating(p, size: geo.size)
                    } else {
                        searching(now)
                    }
                }
            }
        }
        .frame(height: 32)
        .onChange(of: beat) { _, _ in
            let start = Date()
            celebrationStart = start
            Task {
                try? await Task.sleep(for: .seconds(BlockFound.length))
                if celebrationStart == start { celebrationStart = nil }
            }
        }
        .accessibilityHidden(true)
    }

    /// Dim line with a bright glow sweeping left to right.
    @ViewBuilder
    private func searching(_ now: Date) -> some View {
        let t = CGFloat(now.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.searchPeriod) / Self.searchPeriod)
        let head = t * 1.25  // runs past the end so the tail clears before the next sweep
        HeartbeatShape()
            .stroke(Theme.orange.opacity(0.35), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        if !reduceMotion {
            HeartbeatShape()
                .trim(from: max(0, head - 0.18), to: min(1, head))
                .stroke(Theme.orange, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                .shadow(color: Theme.orange.opacity(0.9), radius: 4)
        }
    }

    @ViewBuilder
    private func celebrating(_ p: Double, size: CGSize) -> some View {
        if p < BlockFound.race {
            // The glow races to the end, shaking harder as it goes; the peak jumps as it passes.
            let r: Double = p / BlockFound.race
            let quake: Double = reduceMotion ? 0 : 1.5 + 3 * r
            let spike: Double = r > Double(Self.peakX) ? sin(.pi * min(1, (r - Double(Self.peakX)) / 0.3)) : 0
            ZStack {
                HeartbeatShape(peak: 1 + 0.6 * spike)
                    .stroke(Theme.orange.opacity(0.35), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                HeartbeatShape(peak: 1 + 0.6 * spike)
                    .trim(from: max(0, r - 0.35), to: r)
                    .stroke(Theme.orange, style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
                    .shadow(color: Theme.orange, radius: 6 + 6 * r)
            }
            .offset(x: sin(p * 260) * quake, y: cos(p * 210) * quake)
        } else {
            // Burst: the whole line lit, the peak spiking and settling, rings rippling out.
            let q: Double = (p - BlockFound.race) / (1 - BlockFound.race)
            let spike: Double = max(0, 1 - q * 1.8) * abs(cos(q * .pi * 2.5))
            let glow: Double = 1 - q
            HeartbeatShape(peak: 1 + 1.1 * spike)
                .stroke(Theme.orange, style: StrokeStyle(lineWidth: 2.5 + 1.5 * glow, lineCap: .round, lineJoin: .round))
                .shadow(color: Theme.orange.opacity(glow), radius: 12 * glow)
            ForEach(0..<3) { ring in
                let rp: Double = max(0, min(1, q * 1.5 - Double(ring) * 0.2))
                Circle()
                    .stroke(Theme.orange.opacity((1 - rp) * 0.8), lineWidth: 2.5 * (1 - rp) + 0.5)
                    .frame(width: 12 + 180 * rp, height: 12 + 180 * rp)
                    .position(x: size.width * Self.peakX, y: 0)
            }
            Text("Block found")
                .font(.caption.weight(.heavy))
                .foregroundStyle(Theme.orange)
                .scaleEffect(1 + 0.25 * max(0, 1 - q * 4))
                .opacity(min(1, glow * 2.5))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
    }
}

/// The card around the heartbeat joins in: once the racing glow reaches the end of the line it
/// bursts through the card as a wave of light, the border flares, the card shakes and bumps,
/// and the phone gives a heavy tap and a success haptic.
struct BlockFoundEffect: ViewModifier {
    let beat: Int
    @State private var start: Date?
    @State private var burst = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: start == nil)) { context in
            let p: Double = start.map { min(1, context.date.timeIntervalSince($0) / BlockFound.length) } ?? 1
            // 0 before the burst, then 0...1 across the rest of the celebration.
            let b: Double = p < BlockFound.race || p >= 1 ? 0 : (p - BlockFound.race) / (1 - BlockFound.race)
            let flare: Double = b == 0 ? 0 : (b < 0.15 ? b / 0.15 : 1 - (b - 0.15) / 0.85)
            let shake: Double = reduceMotion || b == 0 || b > 0.3 ? 0 : sin(b * 140) * 8 * (1 - b / 0.3)
            content
                .overlay {
                    GeometryReader { g in
                        RadialGradient(
                            colors: [Theme.orange.opacity(0.55 * flare), Theme.orange.opacity(0.15 * flare), .clear],
                            center: UnitPoint(x: HeartbeatLine.peakX, y: 0.72),
                            startRadius: 0,
                            endRadius: max(g.size.width, g.size.height) * (0.15 + 1.3 * min(1, b * 1.6))
                        )
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .allowsHitTesting(false)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Theme.orange.opacity(flare), lineWidth: 2.5)
                        .allowsHitTesting(false)
                )
                .shadow(color: Theme.orange.opacity(0.7 * flare), radius: 24 * flare)
                .scaleEffect(1 + 0.03 * sin(.pi * min(1, b * 2.5)))
                .offset(x: shake, y: shake * 0.5)
        }
        .sensoryFeedback(.impact(weight: .heavy, intensity: 1), trigger: burst)
        .sensoryFeedback(.success, trigger: burst)
        .onChange(of: beat) { _, _ in
            let begin = Date()
            start = begin
            Task {
                try? await Task.sleep(for: .seconds(BlockFound.burstDelay))
                burst += 1
                try? await Task.sleep(for: .seconds(BlockFound.length - BlockFound.burstDelay))
                if start == begin { start = nil }
            }
        }
    }
}

struct HeartbeatShape: Shape {
    /// Scales the beat's height around the middle; above 1 it overshoots the frame (the block-found spike).
    var peak: CGFloat = 1

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height * peak, mid = rect.midY
        return Path { p in
            p.move(to: CGPoint(x: 0, y: mid))
            p.addLine(to: CGPoint(x: w * 0.38, y: mid))
            p.addLine(to: CGPoint(x: w * 0.44, y: mid - h * 0.15))
            p.addLine(to: CGPoint(x: w * 0.50, y: mid + h * 0.45))
            p.addLine(to: CGPoint(x: w * HeartbeatLine.peakX, y: mid - h * 0.5))
            p.addLine(to: CGPoint(x: w * 0.62, y: mid + h * 0.2))
            p.addLine(to: CGPoint(x: w * 0.66, y: mid))
            p.addLine(to: CGPoint(x: w, y: mid))
        }
    }
}

/// Green dot that breathes while data is fresh, grey when stale.
struct FreshnessDot: View {
    let fresh: Bool
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(fresh ? Theme.up : Color.secondary)
            .frame(width: 8, height: 8)
            .overlay(
                Circle().stroke(fresh ? Theme.up : .clear, lineWidth: 2)
                    .scaleEffect(pulsing ? 2.2 : 1)
                    .opacity(pulsing ? 0 : 0.6)
            )
            .onAppear {
                guard fresh else { return }
                withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { pulsing = true }
            }
            .accessibilityLabel(fresh ? "Live" : "Stale")
    }
}

/// Four segments, lit up to the congestion level.
struct CongestionMeter: View {
    let congestion: Congestion

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Congestion.allCases, id: \.self) { level in
                Capsule()
                    .fill(level.level <= congestion.level ? Theme.series[min(level.level, 2)] : Theme.orange.opacity(0.12))
                    .frame(height: 6)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Congestion: \(congestion.rawValue)")
    }
}

/// Label on the left, value on the right, in the number font.
struct StatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.number(.body, weight: .medium))
        }
        .font(.subheadline)
    }
}

/// Logo D9 artwork on its 1024-unit grid, shared by the symbol and the icon (brand board, 2026-10-15).
enum D9 {
    static let top: [CGPoint] = [.init(x: 512, y: 112), .init(x: 862, y: 301), .init(x: 512, y: 490), .init(x: 162, y: 301)]
    static let left: [CGPoint] = [.init(x: 162, y: 301), .init(x: 512, y: 490), .init(x: 512, y: 868), .init(x: 162, y: 679)]
    static let right: [CGPoint] = [.init(x: 512, y: 490), .init(x: 862, y: 301), .init(x: 862, y: 679), .init(x: 512, y: 868)]
    static let pulse: [CGPoint] = [.init(x: 70, y: 650), .init(x: 330, y: 650), .init(x: 410, y: 490), .init(x: 490, y: 770),
                                   .init(x: 590, y: 350), .init(x: 680, y: 650), .init(x: 954, y: 650)]
    /// The symbol's bounding box (x, y, width, height) without the tile.
    static let symbolBox = CGRect(x: 30, y: 100, width: 964, height: 776)
    /// Pulse stroke: 66 units, or the heavier small-size cut (96) at 32 pt and below.
    static func pulseWidth(renderedSize: CGFloat) -> CGFloat { renderedSize <= 32 ? 96 : 66 }
    /// Brand ink, used for the pulse on light backgrounds.
    static let pulseInk = Color(hex: 0x18181B)
    static let tile = Color(hex: 0x09090B)

    /// Draws the cube and pulse; `transform` maps grid units to the canvas.
    static func draw(in context: GraphicsContext, transform: CGAffineTransform, pulseColor: Color, pulseWidth: CGFloat, scale: CGFloat) {
        func poly(_ points: [CGPoint], closed: Bool) -> Path {
            Path { p in
                p.addLines(points.map { $0.applying(transform) })
                if closed { p.closeSubpath() }
            }
        }
        context.fill(poly(top, closed: true), with: .color(Theme.orange))
        context.fill(poly(left, closed: true), with: .color(Theme.orangeMid))
        context.fill(poly(right, closed: true), with: .color(Theme.orangeDeep))
        context.stroke(poly(pulse, closed: false), with: .color(pulseColor),
                       style: StrokeStyle(lineWidth: pulseWidth * scale, lineCap: .round, lineJoin: .round))
    }
}

/// The symbol: cube and pulse without the tile. The pulse is white on dark and brand ink on light;
/// the blocks always keep their three oranges.
struct BrandSymbol: View {
    var height: CGFloat = 28
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let box = D9.symbolBox
        Canvas { context, canvas in
            let k = canvas.height / box.height
            let transform = CGAffineTransform(translationX: -box.minX, y: -box.minY).concatenating(.init(scaleX: k, y: k))
            D9.draw(in: context, transform: transform,
                    pulseColor: colorScheme == .dark ? .white : D9.pulseInk,
                    pulseWidth: D9.pulseWidth(renderedSize: height), scale: k)
        }
        .frame(width: height * box.width / box.height, height: height)
        .accessibilityHidden(true)
    }
}

/// The app icon: symbol on the ink tile with the iOS mask. Only where Blockpulse is shown as the
/// app itself (Settings, About), never as a header logo.
struct BlockpulseLogo: View {
    var size: CGFloat = 64

    var body: some View {
        Canvas { context, canvas in
            let k = canvas.width / 1024
            context.fill(Path(CGRect(origin: .zero, size: canvas)), with: .color(D9.tile))
            D9.draw(in: context, transform: .init(scaleX: k, y: k), pulseColor: .white,
                    pulseWidth: D9.pulseWidth(renderedSize: size), scale: k)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// Lockup at the top of every tab: symbol 28 pt high, wordmark cap height half of that
/// (SF Pro Rounded Bold), gap 0.3 × symbol height.
struct BrandHeader: View {
    static let symbolHeight: CGFloat = 28

    var body: some View {
        HStack(spacing: Self.symbolHeight * 0.3) {
            BrandSymbol(height: Self.symbolHeight)
            Text("Blockpulse")
                .font(.system(size: Self.symbolHeight * 0.5 / 0.7, weight: .bold, design: .rounded))
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.top, 6)
        .padding(.bottom, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Blockpulse")
        .accessibilityAddTraits(.isHeader)
    }
}
