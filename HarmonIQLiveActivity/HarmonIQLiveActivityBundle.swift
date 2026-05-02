import SwiftUI
import WidgetKit

@main
struct HarmonIQLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        if #available(iOS 16.1, *) {
            HarmonIQLiveActivityWidget()
        }
    }
}
