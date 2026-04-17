import Foundation

struct AIIssueResult: Decodable {
    let title: String
    let body: String
    let labels: [String]
}

private struct ClaudeRequest: Encodable {
    let model: String
    let max_tokens: Int
    let system: String
    let messages: [Message]

    struct Message: Encodable {
        let role: String
        let content: String
    }
}

private struct ClaudeResponse: Decodable {
    let content: [ContentBlock]

    struct ContentBlock: Decodable {
        let type: String
        let text: String?
    }
}

enum ClaudeClientError: LocalizedError {
    case noAPIKey
    case httpError(Int, String)
    case noContent
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No Claude API key configured"
        case .httpError(let code, let body):
            return "Claude API error (\(code)): \(body)"
        case .noContent:
            return "Claude returned an empty response"
        case .decodingFailed(let detail):
            return "Failed to parse Claude response: \(detail)"
        }
    }
}

enum ClaudeClient {

    static func generateIssue(
        rawTodo: String,
        templates: [IssueTemplate],
        fileContext: String?,
        claudeMD: String?
    ) async throws -> AIIssueResult {
        guard let apiKey = KeychainService.read(key: .claudeAPIKey), !apiKey.isEmpty else {
            throw ClaudeClientError.noAPIKey
        }

        var userMessage = "Raw developer note: \"\(rawTodo)\"\n\n"

        if let fileContext, !fileContext.isEmpty {
            userMessage += "File context (the file where this TODO was found):\n```\n\(fileContext)\n```\n\n"
        }

        if let claudeMD, !claudeMD.isEmpty {
            userMessage += "Project context (CLAUDE.md):\n```\n\(claudeMD)\n```\n\n"
        }

        userMessage += "Available templates (choose the most appropriate one and fill it in):\n\n"

        for template in templates {
            userMessage += "--- Template: \(template.name) ---\n"
            userMessage += "<\(template.templateDescription)>\n"
            userMessage += "\(template.body)\n\n"
        }

        let request = ClaudeRequest(
            model: Constants.claudeModel,
            max_tokens: Constants.claudeMaxTokens,
            system: Constants.systemPrompt,
            messages: [
                ClaudeRequest.Message(role: "user", content: userMessage)
            ]
        )

        var urlRequest = URLRequest(url: URL(string: Constants.claudeAPIURL)!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue(Constants.claudeAPIVersion, forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeClientError.httpError(0, "Invalid response")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "No response body"
            print("[BarTicket] Claude API error (\(httpResponse.statusCode)): \(body)")
            throw ClaudeClientError.httpError(httpResponse.statusCode, body)
        }

        let claudeResponse = try JSONDecoder().decode(ClaudeResponse.self, from: data)

        guard let text = claudeResponse.content.first?.text else {
            throw ClaudeClientError.noContent
        }

        print("[BarTicket] Claude API raw response: \(text)")
        return try parseIssue(from: text)
    }

    private static func parseIssue(from text: String) throws -> AIIssueResult {
        if let data = text.data(using: .utf8),
           let issue = try? JSONDecoder().decode(AIIssueResult.self, from: data) {
            return issue
        }

        // Strip code fences and retry
        let stripped = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let data = stripped.data(using: .utf8),
           let issue = try? JSONDecoder().decode(AIIssueResult.self, from: data) {
            return issue
        }

        throw ClaudeClientError.decodingFailed("Could not parse JSON from Claude response")
    }
}
