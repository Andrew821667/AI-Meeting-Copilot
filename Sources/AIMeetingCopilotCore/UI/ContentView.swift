import SwiftUI

public struct ContentView: View {
    @StateObject private var viewModel = MainViewModel()

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                CaptureIndicatorView(mode: viewModel.captureMode)
                Spacer()
                Text("State: \(viewModel.sessionState.rawValue)")
                    .font(.subheadline.monospaced())
            }

            if !viewModel.onboardingReady {
                OnboardingChecklistView(viewModel: viewModel)
            }

            HStack(spacing: 10) {
                Button("Start Capture") {
                    viewModel.startCapture()
                }
                .disabled(!viewModel.onboardingReady || viewModel.sessionState == .capturing)

                Button("Stop Capture") {
                    viewModel.stopCapture()
                }
                .disabled(viewModel.sessionState != .capturing)

                Spacer()

                VStack(alignment: .leading, spacing: 4) {
                    Text(String(format: "mic RMS: %.3f", viewModel.lastMicRms))
                    Text(String(format: "system RMS: %.3f", viewModel.lastSystemRms))
                    Text(viewModel.isUserSpeaking ? "mic: speaking" : "mic: silent")
                }
                .font(.caption.monospaced())
            }

            GroupBox("Live Transcript") {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(viewModel.transcript) { segment in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("[\(segment.isFinal ? "FINAL" : "PART")] \(segment.speaker)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(segment.text)
                                    .font(.body)
                                Text(String(format: "%.2f - %.2f", segment.tsStart, segment.tsEnd))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(segment.isFinal ? Color.green.opacity(0.12) : Color.gray.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.footnote)
            }
        }
        .padding(16)
        .frame(minWidth: 900, minHeight: 620)
    }
}
