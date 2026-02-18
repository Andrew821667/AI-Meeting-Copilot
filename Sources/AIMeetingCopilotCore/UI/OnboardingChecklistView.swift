import SwiftUI

public struct OnboardingChecklistView: View {
    @ObservedObject private var viewModel: MainViewModel

    public init(viewModel: MainViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Первичная настройка: разрешения и подтверждение")
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
                title: "Однократное подтверждение права на анализ",
                granted: viewModel.permissionsManager.checklist.oneTimeAcknowledgementAccepted
            )

            HStack(spacing: 10) {
                Button("Запросить доступ к микрофону") {
                    Task { await viewModel.requestMicPermission() }
                }
                Button("Запросить доступ к записи экрана") {
                    viewModel.requestScreenPermission()
                }
                Button("Подтвердить согласие") {
                    viewModel.acceptAcknowledgement()
                }
                Button("Обновить статус") {
                    viewModel.refreshPermissions()
                }
            }

            Text("Во время встречи используются только локальный индикатор захвата и карточки-подсказки. Всплывающие уведомления отключены.")
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
