import SwiftUI

public struct OnboardingChecklistView: View {
    @ObservedObject private var viewModel: MainViewModel

    public init(viewModel: MainViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Onboarding: разрешения и подтверждение")
                .font(.title3.weight(.semibold))

            checklistRow(
                title: "Разрешение на микрофон",
                granted: viewModel.permissionsManager.checklist.microphonePermissionGranted
            )

            checklistRow(
                title: "Разрешение на запись экрана (для SCK)",
                granted: viewModel.permissionsManager.checklist.screenRecordingPermissionGranted
            )

            checklistRow(
                title: "One-time подтверждение права на анализ",
                granted: viewModel.permissionsManager.checklist.oneTimeAcknowledgementAccepted
            )

            HStack(spacing: 10) {
                Button("Запросить микрофон") {
                    Task { await viewModel.requestMicPermission() }
                }
                Button("Запросить запись экрана") {
                    viewModel.requestScreenPermission()
                }
                Button("Подтвердить consent") {
                    viewModel.acceptAcknowledgement()
                }
                Button("Обновить") {
                    viewModel.refreshPermissions()
                }
            }

            Text("Во время встречи используются только локальный индикатор CAPTURE и overlay карточки. Popup/toast уведомления выключены.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private func checklistRow(title: String, granted: Bool) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(granted ? .green : .red)
            Text(title)
            Spacer()
        }
    }
}
