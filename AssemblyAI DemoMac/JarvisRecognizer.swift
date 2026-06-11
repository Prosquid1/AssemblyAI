//
//  JarvisRecognizer.swift

//

import AVFoundation
import Combine
import AppKit
import Foundation

@MainActor
final class AssemblyAIRecognizer: ObservableObject {

    enum State {
        case idle
        case listening
        case thinking
        case speaking
    }

    @Published var transcript = ""
    @Published var state: State = .idle

    // MARK: - Configuration

    private let apiKey = "1f17f7bab07049da8a43d0c0d224ee87"
    private let sampleRate = 16000
    private let silenceDuration: TimeInterval = 1.5

    // MARK: - Audio

    private let audioEngine = AVAudioEngine()

    // MARK: - WebSocket

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?

    // MARK: - Timers / state

    private var silenceTimer: Timer?
    private var isUserSpeaking = false
    private var sessionOpen = false

    // MARK: - Callbacks

    var onFinalTranscript: ((String) -> Void)?
    var onVoiceDetected: (() -> Void)!

    // MARK: - Public

    func startListening() {
        guard state == .idle || state == .speaking else { return }
        Task { await beginRecognition() }
    }

    func stopListening() {
        silenceTimer?.invalidate()
        silenceTimer = nil

        audioEngine.stop()
        if audioEngine.inputNode.numberOfInputs > 0 {
            audioEngine.inputNode.removeTap(onBus: 0)
        }

        sendTerminate()
        state = .idle
    }

    func setThinking()       { state = .thinking }
    func setSpeaking()       { state = .speaking }
    func returnToListening() { state = .listening }
}

// MARK: - AssemblyAIRecognizer WebSocket

private extension AssemblyAIRecognizer {

    func connectWebSocket() {
        var components = URLComponents()
        components.scheme = "wss"
        components.host   = "streaming.assemblyai.com"
        components.path   = "/v3/ws"
        components.queryItems = [
            URLQueryItem(name: "speech_model", value: "u3-rt-pro"),
            URLQueryItem(name: "sample_rate",  value: "\(sampleRate)"),
        ]

        guard let url = components.url else { return }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")

        urlSession    = URLSession(configuration: .default)
        webSocketTask = urlSession?.webSocketTask(with: request)
        webSocketTask?.resume()

        receiveMessages()
    }

    func receiveMessages() {
        webSocketTask?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                if case .string(let text) = message {
                    self.handleMessage(text)
                }
                self.receiveMessages()   // keep the loop alive
            case .failure(let error):
                print("WebSocket receive error:", error)
            }
        }
    }

    func handleMessage(_ json: String) {
        guard
            let data = json.data(using: .utf8),
            let obj  = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let type = obj["type"] as? String
        else { return }

        switch type {
        case "Begin":
            sessionOpen = true
            print("AssemblyAI session opened:", obj["id"] ?? "")

        case "Turn":
            let text      = obj["transcript"] as? String ?? ""
            let endOfTurn = obj["end_of_turn"] as? Bool ?? false

            DispatchQueue.main.async {
                self.transcript = text
                if !text.isEmpty {
                    self.resetSilenceTimer()
                }
                if endOfTurn && !text.isEmpty {
                    self.finishUtterance()
                }
            }

        case "Termination":
            sessionOpen = false
            webSocketTask?.cancel(with: .normalClosure, reason: nil)
            webSocketTask = nil

        default:
            break
        }
    }

    func sendTerminate() {
        guard sessionOpen else { return }
        let payload = #"{"type":"Terminate"}"#
        webSocketTask?.send(.string(payload)) { _ in }
        sessionOpen = false
    }
}

// MARK: - Audio engine

private extension AssemblyAIRecognizer {

    func beginRecognition() async {
        transcript = ""
        connectWebSocket()

        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)

        // AssemblyAI needs 16-bit mono PCM at the chosen sample rate.
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Double(sampleRate),
            channels: 1,
            interleaved: true
        ) else { return }

        // The hardware format may differ — use a converter tap.
        let hardwareFormat = inputNode.outputFormat(forBus: 0)

        guard let converter = AVAudioConverter(from: hardwareFormat, to: format) else {
            print("Could not create audio converter")
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hardwareFormat) { [weak self] buffer, _ in
            guard let self else { return }

            self.detectVoice(buffer)

            // Convert to 16-bit PCM
            let frameCount = AVAudioFrameCount(
                Double(buffer.frameLength) * Double(self.sampleRate) / hardwareFormat.sampleRate
            )
            guard
                frameCount > 0,
                let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
            else { return }

            var error: NSError?
            converter.convert(to: converted, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }
            guard error == nil, converted.frameLength > 0 else { return }

            // Send raw bytes over the WebSocket
            let byteCount = Int(converted.frameLength) * 2   // 2 bytes per Int16 sample
            let audioData  = Data(bytes: converted.int16ChannelData![0], count: byteCount)
            self.webSocketTask?.send(.data(audioData)) { _ in }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            state = .listening
            resetSilenceTimer()
        } catch {
            print("Audio engine failed to start:", error)
        }
    }

    func detectVoice(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<frameLength { sum += channelData[i] * channelData[i] }
        let rms = sqrt(sum / Float(frameLength))

        if rms > 0.01, !isUserSpeaking {
            isUserSpeaking = true
            print("🎤 User started speaking")
            DispatchQueue.main.async { self.onVoiceDetected() }
        } else if rms <= 0.01 {
            isUserSpeaking = false
        }
    }
}

// MARK: - Silence timer

private extension AssemblyAIRecognizer {

    func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceDuration, repeats: false) { [weak self] _ in
            self?.finishUtterance()
        }
    }

    func finishUtterance() {
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let finalText = transcript
        stopListening()
        onFinalTranscript?(finalText)
    }
}
