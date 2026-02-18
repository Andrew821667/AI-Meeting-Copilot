import SwiftUI

public struct OnboardingChecklistView: View {
    @ObservedObject private var viewModel: MainViewModel
    @State private var consentChecked = false

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

            Toggle(
                "Я подтверждаю, что имею право записывать и анализировать встречи в своих сценариях использования.",
                isOn: $consentChecked
            )
            .toggleStyle(.checkbox)
            .disabled(viewModel.permissionsManager.checklist.oneTimeAcknowledgementAccepted)

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
                .disabled(!consentChecked || viewModel.permissionsManager.checklist.oneTimeAcknowledgementAccepted)
                Button("Обновить статус") {
                    viewModel.refreshPermissions()
                }
            }

            Text("Согласие версии v\(PermissionsManager.currentConsentVersion) сохраняется локально. Во время встречи показывается только локальный индикатор CAPTURE; всплывающие уведомления отключены.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onAppear {
            if viewModel.permissionsManager.checklist.oneTimeAcknowledgementAccepted {
                consentChecked = true
            }
        }
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
