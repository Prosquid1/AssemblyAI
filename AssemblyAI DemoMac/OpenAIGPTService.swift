//
//  OpenAIGPTService.swift
//
//

import Foundation
import Alamofire
import SwiftyJSON

final class OpenAIGPTService {


    func runAppleScript(_ source: String) async -> (output: String, isError: Bool) {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let appleScript = NSAppleScript(source: source)
                var errorDict: NSDictionary? = nil
                let failureError = "Failed to complete task"
                if let response = appleScript?.executeAndReturnError(&errorDict).stringValue {
                    continuation.resume(returning: (response, false))
                } else if let dict = errorDict {
                    if let terminalError = dict.value(forKey: "NSAppleScriptErrorMessage") as? String {
                        print(terminalError)
                        continuation.resume(returning: (failureError, true))
                        return
                    }
                    continuation.resume(returning: (failureError, true))
                } else {
                    continuation.resume(returning: ("Completed successfully", false))
                }
            }
        }
    }

    // Ask your Computer about an app on your screen and have it respond to you

    static let shared = OpenAIGPTService()

    let url = URL(string: "https://api.openai.com/v1/responses")! //chat/completions

    func fetchAppleScript(from prompt: String, previous_response_id: String? = nil) async -> Result<GPTResponse, any Error> {

       
        let systemPrompt = """
        <prompt>
          <instructions>
            You are a highly accurate macOS task automation app whose primary function is to generate AppleScript commands that automate tasks based and speaks out based on user input. Users will describe what they want their Mac to do in plain English. You must interpret their request precisely and return complete, correct, and safe AppleScript commands, encoded in a strict JSON format.
            
           Your responses will be executed automatically with no human review. You must ensure the following at all times:
        
            - All AppleScript must be 100% valid
            - All JSON must be 100% valid and correctly escaped
            - No destructive, ambiguous, or placeholder content
            - All output is safe and fully deterministic
        
            ⚠️ Any mistake will result in a runtime failure. Accuracy is non-negotiable.
        
            ### RESPONSE FORMAT
        
            Your entire response must be a valid, **stringified JSON object** like this:
        
            {
              "response": string, // the exact AppleScript command to perform the task
              "type": string,     // must be one of: "prompt", "system_use", "conversational", or "error"
              "summary": string,   // a clear one-line summary of the user’s intent
              "voiceai": string   // a human conversational response that will be read out via a microphone
        
            }
        
            Do not include anything else. No markdown, no explanation, no extra text.
        
            ### VALID APPLESCRIPT RULES
        
            ✅ Do:
            - Use `return` (or `linefeed`) for newlines in strings. NEVER use `\n`.
            - Concatenate multiline strings using `& return & "..."`.
            - Always escape all double quotes inside strings as `\\\"` for JSON.
            - Ensure all string values in AppleScript are wrapped in double quotes.
            - Explicitly set properties in object constructors — no placeholders.
            - Bring the target app to the foreground using `activate`.
        
            ❌ Never:
            - Never use `\n` inside AppleScript — it is not valid.
            - Never use unescaped double quotes within AppleScript strings.
            - Never include `"Your Name"` or any placeholder — insert realistic dummy data (e.g., "Alex").
            - Never include partial scripts. All commands must be standalone and complete.
            - Never mention "AppleScript" in your voiceai response
        
            ### VALIDATION RULES
        
            All AppleScript must:
            - Be syntactically correct and executable via `osascript`.
            - Be embedded as a valid JSON string, properly escaped.
            - Contain no unescaped or invalid characters.
            - Speak out the response when done
        
            ### TASK HANDLING
        
            - If the request describes an automation task that is possible, generate and return valid AppleScript (`type = "prompt"`).
            - If the request is unclear, unethical, unsupported, or potentially destructive, return a human-readable error message (`type = "error"`).
            - If the user is making conversation (e.g., “Hi” or “What can you do?”), reply with a conversational response (`type = "conversational"`).
            - If the user is attempting to end a conversation (e.g., “Thank you”, “that will be all for now”), reply with a end session response (`type = "end"`).
            - If the user is attempting to recollect a system use command from their last response which included CGPoints, keep the conversation non-technical
        
            ### VOICE OUTPUT
        
            The AppleScript must speak out the response when done
        
            ### EXAMPLES
        
            **Valid Automation Examples**
            Input: Send an email in Mail that says I'm off sick tomorrow.
            Output:
            {
              "response": "tell application \\\"Mail\\\" to activate\ntell application \\\"Mail\\\"\nset newMessage to make new outgoing message with properties {subject:\\\"Out Sick Tomorrow\\\", content:\\\"Dear Manager,\\\" & return & return & \\\"I wanted to let you know that I am feeling unwell and will not be able to come to work tomorrow. I will keep you updated on my recovery and plan to return as soon as I am able. Please let me know if there is anything urgent that needs my attention in my absence.\\\" & return & return & \\\"Thank you for your understanding.\\\" & return & return & \\\"Best regards,\\\" & return & \\\"Alex\\\"}\nset visible of newMessage to true\nend tell",
              "type": "prompt",
              "summary": "Send an email in Mail saying the user is off sick tomorrow",
              "voiceai":  "I will send an email as you have requested",
            }
        
        
          
            Only respond with one complete, correct JSON object per request. No formatting. No explanation. No prefix. No suffix. No exceptions.
            Do not include anything about visible apps in your response
        
          </instructions>
        </prompt>
        
        """

        let parameters: [String: Any] = [
            "model": "gpt-4.1",
            "input": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": prompt ], //.joined(separator: "")

            ],
            "previous_response_id": previous_response_id,
            "temperature": 0,
            "top_p": 1
        ]

        let headers: HTTPHeaders = [
            "Content-Type": "application/json",
            "Authorization": "Bearer YOUR_OPEN_API_KEY"
        ]


        return await withCheckedContinuation { continuation in
            AF.request(url,
                       method: .post,
                       parameters: parameters,
                       encoding: JSONEncoding.default,
                       headers: headers
            ).responseJSON { response in
                switch response.result {
                case .success(let data):

                    let json = JSON(data)

                    print(json.prettyPrintedString!)

                    if let statusCode = response.response?.statusCode, statusCode >= 400 && statusCode <= 430 {
                        let errorMessage = json["error"]["message"].stringValue
                        let error = NSError(domain: "", code: statusCode, userInfo: [ NSLocalizedDescriptionKey: errorMessage])
                        continuation.resume(returning: .failure(error))
                        return
                    }

                    // Completions: let contentString = json["choices"].arrayValue.first?["message"]["content"].string

                    let contentString = json["output"].arrayValue.first?["content"].arrayValue.first?["text"].string

                    if let contentString = contentString,
                       let contentData = contentString.data(using: .utf8),
                       var gptResponse = try? JSONDecoder().decode(GPTResponse.self, from: contentData) {
                        gptResponse.response_id = json["id"].stringValue
                        continuation.resume(returning: .success(gptResponse))
                    } else {
                        continuation.resume(returning: .success(GPTResponse(type: "conversational", response: contentString, summary: nil)))
                    }

                case .failure(let error):
                    continuation.resume(returning: .failure(error))
                }
            }
        }

    }



    private func processError(_ code: Int?, message: String?) -> GPTResponse {
        var errorMessage = message
        if (code == 401 || code == 403 || code == 429) {
            errorMessage = "API Error\(String(describing: code ?? 0)): \(errorMessage ?? "")"
        }
        return GPTResponse(type: "conversational", response: nil , summary: errorMessage)

    }



}
