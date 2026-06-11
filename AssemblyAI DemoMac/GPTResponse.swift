//
//  GPTResponse.swift
//  AssemblyAI Demo
//
//  Created by Oyeleke Okiki on 6/11/26.
//


import SwiftUI
import SwiftyJSON
import CloudKit

struct GPTResponse: Decodable {
    var response_id: String?
    let type: String
    var response: String?
    var summary: String?
    var voiceai: String?
    var operator_app_name: String?
}

struct SystemDrawResponse: Decodable {
    var response_id: String?
    var x: Double?
    let y: Double?
    var instructions: String?
}

struct Message: Identifiable {
    let id = UUID()
    let userPrompt: String
    var output: GPTResponse
    let isError: Bool
}


extension JSON {
    var prettyPrintedString: String? {
        guard
            let data = try? rawData(),
            let object = try? JSONSerialization.jsonObject(with: data),
            let prettyData = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted]
            )
        else {
            return nil
        }

        return String(data: prettyData, encoding: .utf8)
    }
}
