import SwiftUI

public struct ContentView: View {
    @StateObject private var viewModel = MainViewModel()

    public init() {}

    public var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 16) {
                header

                if !viewModel.onboardingReady {
                    OnboardingChecklistView(viewModel: viewModel)
                }

                controls
                liveTranscript

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }

            sidebar
                .frame(width: 320)
        }
        .padding(16)
        .frame(minWidth: 1100, minHeight: 700)
    }

    private var header: some View {
        HStack {
            CaptureIndicatorView(mode: viewModel.captureMode)
            Spacer()
            Text("State: \(viewModel.sessionState.rawValue)")
                .font(.subheadline.monospaced())
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button("Start Capture") {
                viewModel.startCapture()
            }
            .disabled(!viewModel.onboardingReady || viewModel.sessionState == .capturing || viewModel.sessionState == .paused)

            Button("Pause") {
                viewModel.pauseCapture()
            }
            .disabled(viewModel.sessionState != .capturing)

            Button("Resume") {
                viewModel.resumeCapture()
            }
            .disabled(viewModel.sessionState != .paused)

            Button("Stop Capture") {
                viewModel.stopCapture()
            }
            .disabled(viewModel.sessionState != .capturing)

            Button("Panic Capture") {
                viewModel.triggerPanicCapture()
            }
            .keyboardShortcut(.space, modifiers: [.command, .shift])
            .disabled(viewModel.sessionState != .capturing)

            Spacer()

            VStack(alignment: .leading, spacing: 4) {
                Text(String(format: "mic RMS: %.3f", viewModel.lastMicRms))
                Text(String(format: "system RMS: %.3f", viewModel.lastSystemRms))
                Text(viewModel.isUserSpeaking ? "mic: speaking" : "mic: silent")
            }
            .font(.caption.monospaced())
        }
    }

    private var liveTranscript: some View {
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
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cards")
                .font(.title3.weight(.semibold))

            if let card = viewModel.activeCard {
                InsightCardView(
                    card: card,
                    collapsed: viewModel.isCardCollapsed,
                    onPin: { viewModel.togglePinActiveCard() },
                    onCopy: { viewModel.copyActiveReply() },
                    onClose: { viewModel.dismissActiveCard() }
                )
            } else {
                Text("Активной карточки нет")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Text("Последние 3 карточки")
                .font(.headline)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(viewModel.recentCards) { card in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(card.insight)
                                .font(.subheadline)
                                .lineLimit(2)
                            Text(card.triggerReason)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }

            if let summary = viewModel.lastSessionSummary {
                Divider()
                Text("Session Export")
                    .font(.headline)
                Text(summary.exportJSONPath)
                    .font(.caption)
                    .textSelection(.enabled)
                Text(summary.reportMDPath)
                    .font(.caption)
                    .textSelection(.enabled)
            }

            Spacer()
        }
    }
}
