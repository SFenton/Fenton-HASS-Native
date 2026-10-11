import HassCore
import SwiftUI

/// A tab that hasn't been ported yet.
struct PlaceholderScreen: View {
    var title: String
    var symbol: String

    var body: some View {
        ContentUnavailableView(title, systemImage: symbol, description: Text("Coming in a later update."))
            .navigationTitle(title)
    }
}
