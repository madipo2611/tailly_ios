import SwiftUI

enum TaillyTheme {
    static let background = Color(red: 7/255, green: 10/255, blue: 20/255)
    static let surface = Color(red: 15/255, green: 21/255, blue: 39/255)
    static let card = Color(red: 19/255, green: 26/255, blue: 47/255)
    static let accent = Color(red: 185/255, green: 92/255, blue: 1)
    static let cyan = Color(red: 50/255, green: 230/255, blue: 1)
    static let muted = Color(red: 139/255, green: 147/255, blue: 167/255)
}

struct TaillyScreen<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View { content.background(TaillyTheme.background.ignoresSafeArea()) }
}
