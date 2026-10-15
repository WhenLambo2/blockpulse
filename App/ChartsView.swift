import SwiftUI
import BitcoinKit

/// Charts tab: a category bar on top; swipe sideways between categories and up/down through charts.
/// Favourites are edited in Settings or with the star on each chart.
struct ChartsView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("chartsCategory") private var categoryRaw = ChartCategory.favourites.rawValue

    private var category: Binding<ChartCategory> {
        Binding(
            get: { ChartCategory(rawValue: categoryRaw) ?? .favourites },
            set: { categoryRaw = $0.rawValue }
        )
    }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                BrandHeader()
                CategoryBar(selection: category)
                TabView(selection: category) {
                    ForEach(ChartCategory.allCases) { cat in
                        ChartPager(ids: cat == .favourites ? appState.favourites : cat.charts,
                                   bottomInset: geo.safeAreaInsets.bottom)
                            .tag(cat)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                // The pages run on under the tab bar, so the next chart peeks out behind it.
                .ignoresSafeArea(edges: .bottom)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
    }
}

/// Horizontal chips: ★ Favourites · Market · Fees · Mempool · Mining · Blocks.
struct CategoryBar: View {
    @Binding var selection: ChartCategory

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ChartCategory.allCases) { cat in
                        let selected = cat == selection
                        Button {
                            withAnimation(.snappy) { selection = cat }
                        } label: {
                            Label(cat.title, systemImage: cat.systemImage)
                                .labelStyle(.titleAndIcon)
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .foregroundStyle(selected ? Color.black : Color.primary)
                                .background(selected ? Theme.orange : Theme.card, in: Capsule())
                                .overlay(Capsule().strokeBorder(selected ? Color.clear : Theme.border))
                        }
                        .buttonStyle(.plain)
                        .id(cat)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .onAppear { proxy.scrollTo(selection, anchor: .center) }
            .onChange(of: selection) { _, new in withAnimation { proxy.scrollTo(new, anchor: .center) } }
        }
    }
}

/// Chart cards one per screen, swiped vertically. Each card ends above the tab bar and the next
/// one starts right after it, so its top shows through the tab bar as a hint to swipe up.
struct ChartPager: View {
    @Environment(AppState.self) private var appState
    let ids: [ChartID]
    /// Height of the tab bar (and home indicator) the pager runs under.
    let bottomInset: CGFloat

    static let gap: CGFloat = 12

    var body: some View {
        if ids.isEmpty {
            ContentUnavailableView(
                "No favourites yet",
                systemImage: "star",
                description: Text("Tap the star on any chart to pin it here, or pick them in Settings.")
            )
        } else {
            GeometryReader { geo in
                let cardHeight = max(320, geo.size.height - bottomInset - Self.gap * 1.5)
                ScrollView(.vertical) {
                    LazyVStack(spacing: Self.gap) {
                        ForEach(ids) { id in
                            ChartCard(id: id, isFavourite: appState.favourites.contains(id)) {
                                withAnimation(.snappy) { appState.toggleFavourite(id) }
                            }
                            .frame(height: cardHeight)
                            .padding(.horizontal, 16)
                        }
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.top, Self.gap / 2, for: .scrollContent)
                .contentMargins(.bottom, bottomInset + Self.gap, for: .scrollContent)
                .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
                .scrollIndicators(.hidden)
                .ignoresSafeArea(edges: .bottom)
            }
            // Measure down to the screen edge, whatever safe area the page view passes in.
            .ignoresSafeArea(edges: .bottom)
        }
    }
}
