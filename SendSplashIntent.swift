import AppIntents

struct SendSplashIntent: AppIntent {
    static var title: LocalizedStringResource = "Send Splash to Ollee"
    static var description = IntentDescription("Sends up to 6 characters to the Ollee watch splash screen via Bluetooth.")

    @Parameter(title: "Splash Text", description: "Text to display (max 6 characters)")
    var text: String

    static var parameterSummary: some ParameterSummary {
        Summary("Send \(\.$text) to Ollee watch")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let manager = OlleeBTManager.shared
        let success = await manager.send(value: text)
        if success {
            return .result(value: "Sent '\(text)' to Ollee watch.")
        } else {
            // Even if not immediately sent, we queue it. Return informative message.
            if manager.savedPeripheralUUID == nil {
                throw IntentError.noDevice
            }
            return .result(value: "Queued '\(text)' – will send when watch reconnects.")
        }
    }
}

enum IntentError: Error, CustomLocalizedStringResourceConvertible {
    case noDevice

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noDevice:
            return "No Ollee watch paired. Open the OlleeSplash app and select your watch first."
        }
    }
}
