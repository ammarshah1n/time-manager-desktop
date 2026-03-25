import SwiftUI

struct TimedLogoMark: View {
    var size: CGFloat = 52

    private let accent = Color(red: 0.827, green: 0.184, blue: 0.184)

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let center = CGPoint(x: side / 2, y: side / 2)

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.10),
                                Color.white.opacity(0.03)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Circle()
                    .stroke(Color.white.opacity(0.16), lineWidth: side * 0.055)

                Circle()
                    .inset(by: side * 0.14)
                    .stroke(accent.opacity(0.92), lineWidth: side * 0.05)

                Path { path in
                    path.move(to: CGPoint(x: center.x, y: side * 0.30))
                    path.addLine(to: CGPoint(x: center.x, y: side * 0.60))
                    path.move(to: CGPoint(x: center.x, y: center.y))
                    path.addLine(to: CGPoint(x: side * 0.69, y: side * 0.38))
                }
                .stroke(
                    Color.white.opacity(0.92),
                    style: StrokeStyle(lineWidth: side * 0.055, lineCap: .round, lineJoin: .round)
                )

                Rectangle()
                    .fill(Color.white)
                    .frame(width: side * 0.42, height: side * 0.08)
                    .offset(x: -side * 0.06, y: -side * 0.09)

                Rectangle()
                    .fill(Color.white)
                    .frame(width: side * 0.09, height: side * 0.30)
                    .offset(x: -side * 0.06, y: side * 0.04)

                Circle()
                    .fill(accent)
                    .frame(width: side * 0.12, height: side * 0.12)
            }
            .shadow(color: accent.opacity(0.22), radius: side * 0.12, y: side * 0.03)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Timed logo")
    }
}
