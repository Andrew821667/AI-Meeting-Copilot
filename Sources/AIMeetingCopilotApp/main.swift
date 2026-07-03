import SwiftUI
import Speech
import AVFoundation
import os.log
import AIMeetingCopilotCore

@main
struct AIMeetingCopilotDesktopApp: App {
    @StateObject private var viewModel = MainViewModel()

    init() {
        // Диагностический режим: AIMC_ASR_FILE_TEST=/path/to/audio прогоняет
        // распознавание файла (server + on-device) внутри процесса приложения,
        // где уже есть TCC-разрешение Speech Recognition. Результат — в
        // unified log, category ASRFileTest.
        if let path = ProcessInfo.processInfo.environment["AIMC_ASR_FILE_TEST"] {
            Self.runASRFileTest(path: path)
        }
        // Стриминговый тест: кормим файл порциями как микрофон, чтобы
        // воспроизвести/локализовать баг стриминга без живого голоса.
        if let path = ProcessInfo.processInfo.environment["AIMC_ASR_STREAM_TEST"] {
            Self.runASRStreamTest(path: path)
        }
    }

    private static func runASRStreamTest(path: String) {
        let log = Logger(subsystem: "ai.meeting.copilot", category: "ASRStreamTest")
        Task {
            guard let rec = SFSpeechRecognizer(locale: Locale(identifier: "ru-RU")) else {
                log.error("stream: recognizer nil"); return
            }
            guard let file = try? AVAudioFile(forReading: URL(fileURLWithPath: path)) else {
                log.error("stream: cannot open \(path, privacy: .public)"); return
            }
            let srcFormat = file.processingFormat
            log.notice("stream: source \(srcFormat.sampleRate, privacy: .public)Hz \(srcFormat.channelCount, privacy: .public)ch")

            // Читаем весь файл.
            let total = AVAudioFrameCount(file.length)
            guard let whole = AVAudioPCMBuffer(pcmFormat: srcFormat, frameCapacity: total) else { return }
            try? file.read(into: whole)

            // Конвертируем в наш live-формат: Float32 mono 48kHz.
            guard let liveFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false),
                  let converter = AVAudioConverter(from: srcFormat, to: liveFormat) else { return }
            let outCap = AVAudioFrameCount(Double(total) * 48_000 / srcFormat.sampleRate) + 4800
            guard let converted = AVAudioPCMBuffer(pcmFormat: liveFormat, frameCapacity: outCap) else { return }
            var fed = false
            converter.convert(to: converted, error: nil) { _, st in
                if fed { st.pointee = .noDataNow; return nil }
                fed = true; st.pointee = .haveData; return whole
            }
            log.notice("stream: converted frames=\(converted.frameLength, privacy: .public)")

            // Репродукция live-сценария: тишина перед речью. Если 1110
            // прилетает на тишине и последующая речь теряется — вот баг.
            for silenceSec in [0.0, 2.0, 5.0] {
                let scale: Float = 0.1
                let chunkFrames = 512
                let req = SFSpeechAudioBufferRecognitionRequest()
                req.shouldReportPartialResults = true
                req.requiresOnDeviceRecognition = false

                var lastText = ""
                let task = rec.recognitionTask(with: req) { result, error in
                    if let result {
                        lastText = result.bestTranscription.formattedString
                    }
                    if let error {
                        let ns = error as NSError
                        log.error("stream[sil=\(silenceSec, privacy: .public)] ERROR domain=\(ns.domain, privacy: .public) code=\(ns.code, privacy: .public)")
                    }
                }

                // Сначала тишина (лёгкий шум пола как у реального микрофона).
                let silenceFrames = Int(silenceSec * 48_000)
                var sent = 0
                while sent < silenceFrames {
                    let n = min(chunkFrames, silenceFrames - sent)
                    guard let chunk = AVAudioPCMBuffer(pcmFormat: liveFormat, frameCapacity: AVAudioFrameCount(n)) else { break }
                    chunk.frameLength = AVAudioFrameCount(n)
                    if let dst = chunk.floatChannelData?[0] {
                        for i in 0..<n { dst[i] = Float.random(in: -0.0004...0.0004) }
                    }
                    req.append(chunk)
                    sent += n
                    try? await Task.sleep(nanoseconds: UInt64(Double(n) / 48_000 * 1_000_000_000))
                }

                // Потом речь.
                let frames = Int(converted.frameLength)
                var offset = 0
                while offset < frames {
                    let n = min(chunkFrames, frames - offset)
                    guard let chunk = AVAudioPCMBuffer(pcmFormat: liveFormat, frameCapacity: AVAudioFrameCount(n)) else { break }
                    chunk.frameLength = AVAudioFrameCount(n)
                    if let src = converted.floatChannelData?[0], let dst = chunk.floatChannelData?[0] {
                        for i in 0..<n { dst[i] = src[offset + i] * scale }
                    }
                    req.append(chunk)
                    offset += n
                    try? await Task.sleep(nanoseconds: UInt64(Double(n) / 48_000 * 1_000_000_000))
                }
                req.endAudio()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                task.cancel()
                log.notice("stream[sil=\(silenceSec, privacy: .public)] FINALTEXT: \(lastText, privacy: .public)")
            }
            log.notice("stream: done")
        }
    }

    private static func runASRFileTest(path: String) {
        let log = Logger(subsystem: "ai.meeting.copilot", category: "ASRFileTest")
        Task {
            guard let rec = SFSpeechRecognizer(locale: Locale(identifier: "ru-RU")) else {
                log.error("ASRFileTest: recognizer nil")
                return
            }
            log.notice("ASRFileTest: available=\(rec.isAvailable, privacy: .public) onDeviceSupport=\(rec.supportsOnDeviceRecognition, privacy: .public)")
            for onDevice in [false, true] {
                let mode = onDevice ? "onDevice" : "server"
                let req = SFSpeechURLRecognitionRequest(url: URL(fileURLWithPath: path))
                req.requiresOnDeviceRecognition = onDevice
                do {
                    let text: String = try await withCheckedThrowingContinuation { cont in
                        var done = false
                        rec.recognitionTask(with: req) { result, error in
                            if let error {
                                if !done { done = true; cont.resume(throwing: error) }
                                return
                            }
                            if let result, result.isFinal {
                                if !done { done = true; cont.resume(returning: result.bestTranscription.formattedString) }
                            }
                        }
                    }
                    log.notice("ASRFileTest mode=\(mode, privacy: .public) RESULT: \(text, privacy: .public)")
                } catch {
                    let ns = error as NSError
                    log.error("ASRFileTest mode=\(mode, privacy: .public) ERROR domain=\(ns.domain, privacy: .public) code=\(ns.code, privacy: .public) desc=\(ns.localizedDescription, privacy: .public)")
                }
            }
            log.notice("ASRFileTest: done")
        }
    }

    var body: some Scene {
        WindowGroup("AI Meeting Copilot") {
            ContentView(viewModel: viewModel)
        }
        .defaultSize(width: 1280, height: 820)
        .windowResizability(.automatic)
        .windowStyle(.automatic)
        .commands {
            CommandGroup(after: .newItem) {
                OpenMemoryWindowButton()
            }

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
                    // Глубокая проверка через ScreenCaptureKit — preflight
                    // на macOS часто не отражает свежий grant из System Settings.
                    viewModel.refreshPermissionsWithProbe()
                }
            }
        }

        Window("Память / Контекст", id: "memory") {
            MemoryWindowView(viewModel: viewModel.memoryViewModel)
        }
        .defaultSize(width: 720, height: 560)
    }
}

private struct OpenMemoryWindowButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Контекст и память…") {
            openWindow(id: "memory")
        }
        .keyboardShortcut("M", modifiers: [.command, .shift])
    }
}
