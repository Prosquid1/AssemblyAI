//
//  OpenAISpeechManager.swift
//  AssemblyAI Demo
//
//  Created by Oyeleke Okiki on 6/11/26.
//


import Foundation
import AVFoundation



@MainActor
final class OpenAISpeechManager: NSObject {

    private var audioPlayer: AVAudioPlayer?
    private var completion: (() -> Void)?

    func speak(
        _ text: String,
        completion: (() -> Void)? = nil
    ) async {
        stop()
        self.completion = completion

        do {
            let audioData = try await fetchSpeechData(for: text)
            try playAudio(data: audioData)
        } catch {
            print("Error generating speech: \(error)")
            completion?()
            self.completion = nil
        }
    }

    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
        completion = nil
    }

    private func fetchSpeechData(for text: String) async throws -> Data {
        guard let url = URL(string: "https://api.openai.com/v1/audio/speech") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer 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", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": "gpt-4o-mini-tts",
            "voice": "alloy",
            "input": text
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        return data
    }

    private func playAudio(data: Data) throws {
        audioPlayer = try AVAudioPlayer(data: data)
        audioPlayer?.delegate = self
        audioPlayer?.prepareToPlay()
        audioPlayer?.play()
    }
}

extension OpenAISpeechManager: AVAudioPlayerDelegate {

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        completion?()
        completion = nil
    }
}
