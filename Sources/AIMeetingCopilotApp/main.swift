import SwiftUI
import AIMeetingCopilotCore

@main
struct AIMeetingCopilotDesktopApp: App {
    @StateObject private var viewModel = MainViewModel()

    var body: some Scene {
        WindowGroup("AI Meeting Copilot") {
            ContentView(viewModel: viewModel)
        }
        .defaultSize(width: 1280, height: 820)
        .windowResizability(.automatic)
        .windowStyle(.automatic)
        .commands {
            CommandMenu("Доступы") {
                Button(viewModel.microphonePermissionGranted ? "Микрофон: выдан" : "Микрофон: не выдан") {}
                    .disabled(true)
                if !viewModel.microphonePermissionGranted {
                    Button("Запросить микрофон") {
                        Task { await viewModel.requestMicPermission() }
                    }
                }
                Button("Открыть настройки микрофона") {
                    viewModel.openSystemSettingsMicrophone()
                }

                Divider()

                Button(viewModel.speechPermissionGranted ? "Распознавание речи: выдано" : "Распознавание речи: не выдано") {}
                    .disabled(true)
                if !viewModel.speechPermissionGranted {
                    Button("Запросить распознавание речи") {
                        Task { await viewModel.requestSpeechPermission() }
                    }
                }
                Button("Открыть настройки распознавания речи") {
                    viewModel.openSystemSettingsSpeechRecognition()
                }

                Divider()

                Button(viewModel.screenPermissionGranted ? "Запись экрана: выдана" : "Запись экрана: не выдана") {}
                    .disabled(true)
                Button("Запросить запись экрана") {
                    viewModel.requestScreenPermission()
                }
                Button("Открыть настройки записи экрана") {
                    viewModel.openSystemSettingsScreenRecording()
                }

                Divider()

                Button(viewModel.consentAccepted ? "Подтверждение анализа: принято" : "Подтверждение анализа: не принято") {}
                    .disabled(true)
                if !viewModel.consentAccepted {
                    Button("Подтвердить право на анализ") {
                        viewModel.acceptAcknowledgement()
                    }
                }

                Divider()

                Button("Обновить статусы доступов") {
                    viewModel.refreshPermissions()
                }
            }
        }
    }
}
