import AVFoundation
import Speech
import Combine

@MainActor final class SpeechInput: ObservableObject {
    @Published var recording = false
    @Published var transcript = ""
    @Published var error: String?
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var hasTap = false
    private var generation = UUID()
    private var starting = false

    func start() {
        guard !recording && !starting else { return }
        starting = true
        generation = UUID()
        let generation = generation
        error = nil
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                guard let self, self.generation == generation else { return }
                guard status == .authorized else { self.starting = false; self.error = "Allow Speech Recognition in System Settings to dictate."; return }
                AVCaptureDevice.requestAccess(for: .audio) { allowed in
                    Task { @MainActor in
                        guard self.generation == generation else { return }
                        guard allowed else { self.starting = false; self.error = "Allow Microphone in System Settings to dictate."; return }
                        self.beginRecording(generation: generation)
                    }
                }
            }
        }
    }

    private func beginRecording(generation: UUID) {
        starting = false
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else { error = "Speech recognition is unavailable. You can still type your message."; return }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.request = request
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { error = "No microphone is available."; return }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
        hasTap = true
        engine.prepare()
        do { try engine.start() } catch { self.error = error.localizedDescription; stop(); return }
        recording = true; transcript = ""
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self, self.generation == generation else { return }
                if let result { self.transcript = result.bestTranscription.formattedString }
                if result?.isFinal == true { self.stop() }
                else if let error, self.recording { self.error = error.localizedDescription; self.stop() }
            }
        }
    }

    func stop() {
        generation = UUID()
        starting = false
        recording = false
        if engine.isRunning { engine.stop() }
        if hasTap { engine.inputNode.removeTap(onBus: 0); hasTap = false }
        request?.endAudio(); task?.cancel(); request = nil; task = nil
    }
}
