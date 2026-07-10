import Foundation
import AppKit
import Carbon.HIToolbox
import CoreAudio

/// Глобальный хоткей мьюта микрофона для сценария «переводчик»:
/// говоришь по-русски в мьюте → читаешь перевод вслух собеседнику.
///
/// Семантика мьюта важна: мьютим В ПРИЛОЖЕНИИ ВСТРЕЧИ (Zoom), а не системный
/// вход. Zoom-мьют глушит только Zoom — микрофон остаётся доступен копайлоту,
/// и переводчик продолжает слышать и переводить твою русскую речь.
/// Системный мьют (fallback, когда Zoom не запущен) глушит ВСЁ, включая
/// транскрипцию копайлота — для сценария перевода он не подходит.
///
/// Хоткей: ⌥⌘M (Carbon RegisterEventHotKey — работает глобально и не требует
/// разрешения Accessibility). Сам Zoom-мьют шлёт Cmd+Shift+A через System
/// Events — на первый раз macOS спросит разрешение «Automation».
@MainActor
public final class MicMuteHotkeyManager: ObservableObject {

    public enum LastAction: Equatable {
        case none
        case zoomToggled(Date)
        case systemMuted(Bool, Date)
        case failed(String, Date)
    }

    @Published public private(set) var lastAction: LastAction = .none
    @Published public private(set) var hotkeyRegistered = false

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    public init() {}

    deinit {
        // Carbon-ресурсы освобождаются при завершении процесса; явная
        // отписка здесь невозможна (deinit не @MainActor). Менеджер живёт
        // столько же, сколько приложение.
    }

    // MARK: - Hotkey registration

    public func registerHotkey() {
        guard hotKeyRef == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let callback: EventHandlerUPP = { _, _, userData in
            guard let userData else { return noErr }
            let manager = Unmanaged<MicMuteHotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            Task { @MainActor in
                manager.toggleMute()
            }
            return noErr
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &eventType, selfPtr, &eventHandler)

        let hotKeyID = EventHotKeyID(signature: OSType(0x41494D43) /* 'AIMC' */, id: 1)
        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_M),
            UInt32(cmdKey | optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        hotkeyRegistered = (status == noErr && hotKeyRef != nil)
    }

    // MARK: - Mute toggle

    public func toggleMute() {
        if let zoom = NSRunningApplication.runningApplications(withBundleIdentifier: "us.zoom.xos").first {
            toggleZoomMute(zoom: zoom)
        } else {
            // Zoom не запущен — переключаем системный вход (с оговоркой:
            // в этом режиме копайлот тоже не слышит; см. help в UI).
            toggleSystemInputMute()
        }
    }

    private func toggleZoomMute(zoom: NSRunningApplication) {
        // Cmd+Shift+A — стандартный шорткат Zoom «Mute/Unmute My Audio».
        // Активируем Zoom, шлём шорткат, возвращаем фокус прежнему приложению.
        let previousApp = NSWorkspace.shared.frontmostApplication
        zoom.activate()

        let script = """
        tell application "System Events"
            keystroke "a" using {command down, shift down}
        end tell
        """
        // Небольшая пауза, чтобы Zoom успел стать frontmost.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            var error: NSDictionary?
            NSAppleScript(source: script)?.executeAndReturnError(&error)
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    let msg = (error["NSAppleScriptErrorBriefMessage"] as? String) ?? "AppleScript error"
                    self.lastAction = .failed("Zoom-мьют: \(msg). Разреши Automation → System Events в Настройках.", Date())
                } else {
                    self.lastAction = .zoomToggled(Date())
                }
                // Возвращаем фокус туда, где был пользователь.
                if let previousApp, previousApp.bundleIdentifier != "us.zoom.xos" {
                    previousApp.activate()
                }
            }
        }
    }

    // MARK: - System input mute (fallback)

    private func toggleSystemInputMute() {
        guard let deviceID = Self.defaultInputDevice() else {
            lastAction = .failed("Не найдено устройство ввода.", Date())
            return
        }
        let muted = Self.inputMuted(deviceID: deviceID) ?? false
        if Self.setInputMuted(deviceID: deviceID, muted: !muted) {
            lastAction = .systemMuted(!muted, Date())
        } else {
            lastAction = .failed("Не удалось переключить системный мьют.", Date())
        }
    }

    private static func defaultInputDevice() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        return status == noErr && deviceID != 0 ? deviceID : nil
    }

    private static func muteAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func inputMuted(deviceID: AudioDeviceID) -> Bool? {
        var address = muteAddress()
        guard AudioObjectHasProperty(deviceID, &address) else { return nil }
        var muted = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &muted)
        return status == noErr ? (muted != 0) : nil
    }

    private static func setInputMuted(deviceID: AudioDeviceID, muted: Bool) -> Bool {
        var address = muteAddress()
        guard AudioObjectHasProperty(deviceID, &address) else { return false }
        var value = UInt32(muted ? 1 : 0)
        let size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &value) == noErr
    }
}
