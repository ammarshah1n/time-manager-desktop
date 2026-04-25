// BucketDot.swift — Timed macOS
// The single allowed colour signal in the app. An 8pt circle next to a row
// or sidebar item — like Apple Reminders' list-color dot. Read at a glance,
// invisible if you're not looking for it. Never used larger than 12pt.

import SwiftUI

struct BucketDot: View {
    var color: Color
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
    }
}

