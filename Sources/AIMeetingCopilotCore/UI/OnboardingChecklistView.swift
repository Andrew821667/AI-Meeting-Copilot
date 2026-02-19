import SwiftUI

public struct OnboardingChecklistView: View {
    @ObservedObject private var viewModel: MainViewModel
    @State private var consentChecked = false

    public init(viewModel: MainViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Разрешения и подтверждение")
                .font(.title3.weight(.semibold))

            Text("Проверяйте статусы перед запуском. Блок всегда доступен для повторной проверки разрешений.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if !viewModel.microphonePermissionGranted {
                checklistRow(title: "Разрешение на микрофон", granted: false)
                HStack(spacing: 8) {
                    Button("Запросить доступ к микрофону") {
                        Task { await viewModel.requestMicPermission() }
                    }
                    Button("Открыть настройки микрофона") {
                        viewModel.openSystemSettingsMicrophone()
                    }
                }
            }

            if !viewModel.speechPermissionGranted {
                checklistRow(title: "Доступ к распознаванию речи", granted: false)
                HStack(spacing: 8) {
                    Button("Запросить доступ к распознаванию") {
                        Task { await viewModel.requestSpeechPermission() }
                    }
                    Button("Открыть настройки распознавания") {
                        viewModel.openSystemSettingsSpeechRecognition()
                    }
                }
            }

            if viewModel.requiresScreenPermission && !viewModel.screenPermissionGranted {
                checklistRow(title: "Доступ к аудио собеседника (запись экрана)", granted: false)
                HStack(spacing: 8) {
                    Button("Запросить доступ к аудио собеседника") {
                        viewModel.requestScreenPermission()
                    }
                    Button("Открыть настройки записи экрана") {
                        viewModel.openSystemSettingsScreenRecording()
                    }
                }
            }

            if !viewModel.consentAccepted {
                checklistRow(title: "Однократное подтверждение права на анализ", granted: false)
                Toggle(
                    "Я подтверждаю, что имею право записывать и анализировать встречи в своих сценариях использования.",
                    isOn: $consentChecked
                )
                .toggleStyle(.checkbox)

                Button("Подтвердить согласие") {
                    viewModel.acceptAcknowledgement()
                }
                .disabled(!consentChecked)
            }

            if viewModel.hasPendingPermissionItems {
                Button("Обновить статус") {
                    viewModel.refreshPermissionsWithProbe()
                }
            } else {
                Text("Все обязательные доступы выданы. Управление статусами и доступами доступно в верхнем меню приложения: «Доступы».")
                    .font(.footnote)
                    .foregroundStyle(.green)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Согласие версии v\(PermissionsManager.currentConsentVersion) сохраняется локально. Во время встречи показывается только локальный индикатор CAPTURE; всплывающие уведомления отключены.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if viewModel.screenPermissionMissingForMeetingMode {
                Text("Для режима «Встреча (собеседник + я)» доступ к записи экрана обязателен: иначе не будет аудио собеседника.")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(viewModel.startGuideText)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(viewModel.onboardingReady ? (viewModel.screenPermissionMissingForMeetingMode ? .orange : .green) : .orange)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .background(Color(red: 0.97, green: 0.93, blue: 0.87))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onAppear {
            if viewModel.consentAccepted {
                consentChecked = true
            }
            viewModel.refreshPermissions()
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
