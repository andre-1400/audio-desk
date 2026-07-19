// GroqThemeGenerator.swift
// Calls the Groq API (Llama 3.3 70B) and parses the response into a GeneratedThemeSpec.

import Foundation
import Combine

@MainActor
final class AIThemeGenerator: ObservableObject {

    @Published var isGenerating = false
    @Published var lastError: String?
    @Published var result: GeneratedThemeSpec?

    private let endpoint = GroqConfiguration.proxyEndpoint
    private let model = "llama-3.3-70b-versatile"

    // MARK: - Public

    func generate(prompt: String, styleSuffix: String) async {
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            lastError = "Please enter a prompt."
            return
        }

        isGenerating = true
        lastError = nil
        result = nil

        do {
            let spec = try await fetchThemeSpec(prompt: prompt, styleSuffix: styleSuffix)
            result = spec
        } catch {
            lastError = friendlyError(error)
        }

        isGenerating = false
    }

    // MARK: - Request

    private func fetchThemeSpec(prompt: String, styleSuffix: String) async throws -> GeneratedThemeSpec {
        guard let url = URL(string: endpoint) else {
            throw GeneratorError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("theme", forHTTPHeaderField: "X-Vinyl-Feature")
        request.timeoutInterval = 30

        let body = GroqRequest(
            model: model,
            messages: [
                .init(role: "system", content: buildSystemPrompt()),
                .init(role: "user", content: buildUserMessage(userPrompt: prompt, styleSuffix: styleSuffix))
            ],
            responseFormat: .init(type: "json_object")
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw GeneratorError.httpError(http.statusCode, msg)
        }

        return try parseResponse(data: data)
    }

    // MARK: - Response parsing

    private func parseResponse(data: Data) throws -> GeneratedThemeSpec {
        let groqResp = try JSONDecoder().decode(GroqResponse.self, from: data)
        guard let text = groqResp.choices?.first?.message?.content, !text.isEmpty else {
            throw GeneratorError.emptyResponse
        }

        if let specData = text.data(using: .utf8),
           let spec = try? JSONDecoder().decode(GeneratedThemeSpec.self, from: specData) {
            return validated(spec)
        }

        if let extracted = extractFirstJSONObject(from: text),
           let specData = extracted.data(using: .utf8),
           let spec = try? JSONDecoder().decode(GeneratedThemeSpec.self, from: specData) {
            return validated(spec)
        }

        throw GeneratorError.parseFailure(text)
    }

    private func validated(_ spec: GeneratedThemeSpec) -> GeneratedThemeSpec {
        var s = spec
        if s.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            s.name = "Custom AI Theme"
        }
        if let opacity = s.shelfOpacity { s.shelfOpacity = max(0, min(1, opacity)) }
        if let strength = s.shadowStrength { s.shadowStrength = max(0, min(1, strength)) }
        return s
    }

    private func extractFirstJSONObject(from text: String) -> String? {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}") else { return nil }
        guard start <= end else { return nil }
        return String(text[start...end])
    }

    // MARK: - Prompt template

    private func buildSystemPrompt() -> String {
        """
        You generate theme JSON for a premium macOS vinyl record widget.
        Return valid JSON only. No markdown, no commentary, no code fences.
        Use only 6-digit hex colors with a leading #.

        COLOR HARMONY RULES:
        - Derive ALL colors from a single coherent palette. Pick 1-2 dominant hues and build every color from tints, shades, and neutrals of those hues.
        - Borders and outlines (widgetBorder, shelfOutline, queueBarBorder, connectOverlayBorder, sleeveCardBorder) must be subtle: a slightly lighter or darker shade of the adjacent background color, never a contrasting or random hue.
        - Text colors (trackTitle, trackArtist, trackIdle, queueBarText, sleeveNowText, sleevePlaceholderLetter) must have high contrast against their backgrounds. Use near-white for dark backgrounds, near-black for light backgrounds.
        - Accent/dot colors (trackPlayingDot, trackPausedDot, albumArtRingColor) should be the most saturated color in the palette — the "pop" color. Use it sparingly.
        - Overlay backgrounds (connectOverlayBackground, queueBarBackground, sleeveNowBackground) should be semi-dark desaturated versions of the main palette, so content stays readable.
        - shelfButtonBackground and shelfButtonIcon should feel like they belong on the widget body, not float unrelated.
        - sleevePlaceholderOuter, sleevePlaceholderMiddle, sleevePlaceholderInner should step progressively lighter or darker — a concentric ring effect.
        - widgetTopSheen should be a very subtle near-white or near-transparent highlight (e.g. #FFFFFF with low implied opacity baked in as a very light hex).

        QUALITY RULES:
        - Never use pure #000000 or pure #FFFFFF unless the theme explicitly calls for it.
        - Avoid muddy mid-grays unless the theme is monochrome.
        - Keep the design premium, cinematic, and physically believable (like real hardware).
        - Do not use extreme neon or random rainbow palettes unless the style mode explicitly requests it.
        - shelfOpacity: 0.80–0.95. shadowStrength: 0.45–0.75. Stay in these ranges unless theme demands otherwise.

        ARRAY FIELDS — must be arrays of exactly 3 hex color strings:
        widgetBodyGradient, albumArtLabelGradient, screwGradient, shelfPanelGradient, sleeveCardGradient

        Required JSON keys:
        name, mood, widgetBodyGradient, widgetBorder, widgetTopSheen,
        albumArtLabelGradient, albumArtRingColor,
        trackPlayingDot, trackPausedDot, trackTitle, trackArtist, trackIdle,
        screwGradient,
        shelfButtonBackground, shelfButtonRing, shelfButtonIcon,
        shelfPanelGradient, shelfOutline,
        queueBarText, queueBarBackground, queueBarBorder,
        connectOverlayIcon, connectOverlayTitle, connectOverlaySubtitle,
        connectOverlayBackground, connectOverlayBorder,
        sleeveCardGradient, sleeveCardBorder,
        sleeveNowText, sleeveNowBackground,
        sleevePlaceholderOuter, sleevePlaceholderMiddle,
        sleevePlaceholderInner, sleevePlaceholderLetter,
        shelfOpacity, shadowStrength
        """
    }

    private func buildUserMessage(userPrompt: String, styleSuffix: String) -> String {
        """
        \(styleSuffix)

        User prompt: \(userPrompt)
        """
    }

    // MARK: - Error formatting

    private func friendlyError(_ error: Error) -> String {
        switch error {
        case GeneratorError.httpError(let code, let msg):
            if code == 400 { return "Invalid request. Check your prompt." }
            if code == 401 || code == 403 { return "API key is invalid or unauthorized." }
            if code == 429 { return "Theme generation is temporarily unavailable — rate limit reached. Try again in a moment." }
            return "Server error \(code): \(msg.prefix(120))"
        case GeneratorError.emptyResponse:
            return "AI returned an empty response. Try again."
        case GeneratorError.parseFailure:
            return "Could not parse the theme JSON. Try rephrasing your prompt."
        case GeneratorError.invalidURL:
            return "Internal error: invalid URL."
        default:
            let msg = error.localizedDescription
            if msg.contains("timed out") { return "Request timed out. Check your connection." }
            return msg
        }
    }
}

// MARK: - Local error type

private enum GeneratorError: Error {
    case invalidURL
    case httpError(Int, String)
    case emptyResponse
    case parseFailure(String)
}

// MARK: - Groq REST models

private struct GroqRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }
    struct ResponseFormat: Encodable {
        let type: String
    }
    let model: String
    let messages: [Message]
    let responseFormat: ResponseFormat

    enum CodingKeys: String, CodingKey {
        case model, messages
        case responseFormat = "response_format"
    }
}

private struct GroqResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
        }
        let message: Message?
    }
    let choices: [Choice]?
}
