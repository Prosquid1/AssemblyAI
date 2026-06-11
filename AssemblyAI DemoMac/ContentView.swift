//
//  ContentView.swift
//  AssemblyAI Demo
//
//  Created by Oyeleke Okiki on 6/11/26.
//

import SwiftUI

struct ContentView: View {

    @StateObject private var speechRecognizer = JarvisRecognizer()

    private var speaker = OpenAISpeechManager()
    @State private var messages: [Message] = []


    var body: some View {
        VStack {
            VoiceButton(
                isActive: .constant(false)
            ) {
                switch speechRecognizer.state {

                case .idle:
                    speaker.stop()
                    speechRecognizer.startListening()

                case .listening:
                    speechRecognizer.stopListening()

                case .thinking:
                    break

                case .speaking:
                    break
                }
            }
        }

    }
}

extension ContentView {
    private func sendMessage(_ input: String) {
        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else { return }
        var message: Message = Message(userPrompt: "", output: GPTResponse(type: ""), isError: false)
 

        let GPTService = OpenAIGPTService.shared

        Task {
            let result = await GPTService.fetchAppleScript(from: trimmedInput, previous_response_id: generateLastResponseID(messages))
            switch result {
            case .success(let output):
                if output.type == "prompt", let script = output.response {
                    Task {
                        let executionResult = await GPTService.runAppleScript(script.trimmingCharacters(in: .whitespacesAndNewlines))
                        var modifiedOutput = output
                        modifiedOutput.summary = executionResult.output

                        message = Message(userPrompt: trimmedInput, output: modifiedOutput, isError: executionResult.isError)
                        DispatchQueue.main.async {
                            resumeOperations(message, message.output.voiceai)
                        }
                    }
                    return
                } else if output.type == "error" {
                    var modifiedOutput = output
                    modifiedOutput.summary = output.response
                    message = Message(userPrompt: trimmedInput, output: modifiedOutput, isError: true)
                }  else if output.type == "end" {
                    var modifiedOutput = output
                    modifiedOutput.summary = "User ended conversation"
                    message = Message(userPrompt: trimmedInput, output: modifiedOutput, isError: false)
                } else {
                    message = Message(userPrompt: trimmedInput, output: output, isError: false)
                }

                resumeOperations(message, message.output.voiceai)

            case .failure(let error):
                let errorGPTReponse = processError(error)
                let message = Message(userPrompt: trimmedInput, output: errorGPTReponse, isError: true)
                resumeOperations(message, "Operation failed, Please try again later")
            }
        }
    }

    func processError(_ error: Error) -> GPTResponse {
        var errorMessage = error.localizedDescription
        let code = error._code
        if (code == 401 || code == 403 || code == 429) {
            errorMessage = "API Error\(String(describing: code ?? 0)): \(errorMessage ?? "")"
        }
        return GPTResponse(type: "conversational", response: nil , summary: errorMessage)
    }

    func resumeOperations(_ message: Message, _ audioOutput: String? = nil) {
        messages.insert(message, at: 0)
        // if it was previously listening
        Task { @MainActor in
            if let voiceaiOutput = audioOutput {
                speechRecognizer.setSpeaking()
                await speaker.speak(voiceaiOutput) {
                    message.output.type == "end" ? speechRecognizer.stopListening() : speechRecognizer.startListening()
                }
            }
        }
    }

    private func generateMessageHistory(_ history: [Message], adHocSystemUseMessage: String? = nil) -> [[String: String]] {
        if (history.isEmpty) { return [] }
        var messages: [[String: String]] = []

        for message in history.suffix(5) {
            messages.append([
                "role": "user",
                "content": message.userPrompt
            ])

            if let response = message.output.voiceai,
               !response.isEmpty {
                messages.append([
                    "role": "assistant",
                    "content": response
                ])
            }
        }

        if let temp = adHocSystemUseMessage {
            messages.append([
                "role": "user",
                "content": temp
            ])
        }

        return messages

    }

    private func generateLastResponseID(_ history: [Message]) -> String? {
        if (history.isEmpty) { return nil }

        return history.suffix(10).reversed().first {
            guard let responseId = $0.output.response_id else { return false }
            return !responseId.isEmpty
        }?.output.response_id

        return nil

    }
}

#Preview {
    ContentView()
}
