import SwiftUI

struct TimedLogoMark: View {
    var size: CGFloat = 52

    private let accent = Color(red: 0.827, green: 0.184, blue: 0.184)
    private let shellTop = Color(red: 0.20, green: 0.22, blue: 0.27)
    private let shellBottom = Color(red: 0.10, green: 0.11, blue: 0.14)
    private let dial = Color(red: 0.97, green: 0.95, blue: 0.91)
    private let ink = Color(red: 0.12, green: 0.13, blue: 0.16)

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let center = CGPoint(x: side / 2, y: side * 0.54)

            ZStack {
                RoundedRectangle(cornerRadius: side * 0.28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                shellTop,
                                shellBottom
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: side * 0.28, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: side * 0.02)
                    )

                RoundedRectangle(cornerRadius: side * 0.12, style: .continuous)
                    .fill(accent)
                    .frame(width: side * 0.22, height: side * 0.10)
                    .offset(y: -side * 0.35)

                Circle()
                    .fill(dial)
                    .frame(width: side * 0.62, height: side * 0.62)
                    .offset(y: side * 0.04)

                Circle()
                    .stroke(ink.opacity(0.16), lineWidth: side * 0.04)
                    .frame(width: side * 0.62, height: side * 0.62)
                    .offset(y: side * 0.04)

                StopwatchAccentArc()
                    .stroke(
                        accent,
                        style: StrokeStyle(lineWidth: side * 0.055, lineCap: .round)
                    )
                    .frame(width: side * 0.53, height: side * 0.53)
                    .offset(y: side * 0.04)

                Rectangle()
                    .fill(ink)
                    .frame(width: side * 0.24, height: side * 0.07)
                    .offset(x: 0, y: side * 0.00)

                Rectangle()
                    .fill(ink)
                    .frame(width: side * 0.08, height: side * 0.28)
                    .offset(x: 0, y: side * 0.09)

                Path { path in
                    path.move(to: center)
                    path.addLine(to: CGPoint(x: side * 0.68, y: side * 0.39))
                }
                .stroke(accent, style: StrokeStyle(lineWidth: side * 0.035, lineCap: .round))

                Path { path in
                    path.move(to: center)
                    path.addLine(to: CGPoint(x: side * 0.50, y: side * 0.31))
                }
                .stroke(ink, style: StrokeStyle(lineWidth: side * 0.028, lineCap: .round))

                Circle()
                    .fill(accent)
                    .frame(width: side * 0.09, height: side * 0.09)
                    .offset(y: side * 0.04)
            }
            .shadow(color: Color.black.opacity(0.26), radius: side * 0.14, y: side * 0.06)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Timed logo")
    }
}

private struct StopwatchAccentArc: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.midY),
            radius: rect.width / 2,
            startAngle: .degrees(208),
            endAngle: .degrees(24),
            clockwise: false
        )
        return path
    }
}
