import SwiftUI
import WidgetKit

@main
struct BlockpulseWidgetsBundle: WidgetBundle {
    var body: some Widget {
        PriceWidget()
        BlocksWidget()
        FeesWidget()
        DashboardWidget()
        LockScreenWidget()
    }
}
