import SwiftUI

public struct ProfileSettingsEditorView: View {
    @Binding var settings: ProfileRuntimeSettings
    let onReset: () -> Void

    public init(settings: Binding<ProfileRuntimeSettings>, onReset: @escaping () -> Void) {
        self._settings = settings
        self.onReset = onReset
    }

    public var body: some View {
        Form {
            Section("Порог срабатывания") {
                HStack {
                    Slider(value: $settings.threshold, in: 0.1...1.0, step: 0.01)
                    Text(String(format: "%.2f", settings.threshold))
                        .frame(width: 48, alignment: .trailing)
                }
            }

            Section("Cooldown (секунды)") {
                Stepper(value: $settings.cooldownSec, in: 5...600, step: 5) {
                    Text("\(Int(settings.cooldownSec)) сек")
                }
            }

            Section("Лимит карточек") {
                Stepper(value: $settings.maxCardsPer10Min, in: 1...20, step: 1) {
                    Text("\(settings.maxCardsPer10Min) карточек за 10 минут")
                }
            }

            Section("Пауза перед показом") {
                HStack {
                    Slider(value: $settings.minPauseSec, in: 0.5...5.0, step: 0.1)
                    Text(String(format: "%.1f c", settings.minPauseSec))
                        .frame(width: 56, alignment: .trailing)
                }
            }

            Section("Минимальный контекст") {
                Stepper(value: $settings.minContextMin, in: 0...10, step: 1) {
                    Text("\(settings.minContextMin) мин")
                }
            }

            Section {
                Button("Сбросить к значениям профиля", action: onReset)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 420)
    }
}
