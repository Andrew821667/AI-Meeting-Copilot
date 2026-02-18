import SwiftUI

public struct CaptureIndicatorView: View {
    public let mode: CaptureMode

    public init(mode: CaptureMode) {
        self.mode = mode
    }

    public var body: some View {
        Text(mode.localizedLabel)
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(backgroundColor)
            .foregroundStyle(.white)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(.white.opacity(0.25), lineWidth: 1)
            )
    }

    private var backgroundColor: Color {
        switch mode {
        case .off: return .gray
        case .screenCaptureKit: return .green
        case .blackHole: return .orange
        case .micOnly: return .blue
        }
    }
}
