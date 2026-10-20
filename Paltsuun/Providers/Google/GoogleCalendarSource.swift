import AppKit
import Foundation
import Observation

enum GoogleCalendarError: LocalizedError {
    case missingClientID
    case notConnected
    case signInExpired
    case signInFailed(String)
    case calendarAccessNotGranted
    case tokenRequestFailed(error: String, description: String?)
    case requestFailed(status: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case .missingClientID: "Enter the OAuth client ID first."
        case .notConnected: "Not connected. Connect Google Calendar in Settings."
        case .signInExpired: "Sign-in expired. Connect Google Calendar again in Settings."
        case .signInFailed(let reason): "Sign-in failed: \(reason)"
        case .calendarAccessNotGranted: "Access to Google Calendar wasn't granted. Connect again and allow calendar access."
        case .tokenRequestFailed(let error, let description): "Sign-in failed: \(description ?? error)"
        case .requestFailed(let status, let message): message ?? "Google Calendar returned HTTP \(status)."
        }
    }
}

/// Reads the primary Google Calendar with the Calendar API.
///
/// Signs in with OAuth 2.0 for desktop apps: Google's consent page opens in the default browser
/// and redirects back to a loopback address served by the app, using PKCE. The OAuth client is
/// the user's own, created in Google Cloud Console (see README). The refresh token is kept in
/// the keychain.
@Observable
final class GoogleCalendarSource: RemoteCalendarSource {
    static let clientIDKey = "googleClientID"
    static let clientSecretKey = "googleClientSecret"
    private static let accountNameKey = "googleAccountName"

    private static let scope = "https://www.googleapis.com/auth/calendar.events.readonly"
    private static let authorizationURL = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    private static let tokenURL = URL(string: "https://oauth2.googleapis.com/token")!
    private static let revokeURL = URL(string: "https://oauth2.googleapis.com/revoke")!
    private static let eventsURL = URL(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events")!
    private static let keychainService = "com.esamatti.Paltsuun.google"
    private static let refreshTokenAccount = "refreshToken"
    private static let signInTimeout: Duration = .seconds(5 * 60)
    /// Event types that aren't meetings.
    private static let ignoredEventTypes: Set<String> = ["outOfOffice", "focusTime", "workingLocation", "birthday"]

    let id = "google"
    let displayName = "Google Calendar"
    private(set) var isConnected: Bool
    private(set) var accountName: String?

    @ObservationIgnored private var accessToken: (value: String, expires: Date)?

    init() {
        isConnected = Keychain.read(service: Self.keychainService, account: Self.refreshTokenAccount) != nil
        accountName = UserDefaults.standard.string(forKey: Self.accountNameKey)
    }

    private var clientID: String {
        UserDefaults.standard.string(forKey: Self.clientIDKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var clientSecret: String {
        UserDefaults.standard.string(forKey: Self.clientSecretKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    // MARK: Sign-in

    func connect() async throws {
        guard !clientID.isEmpty else { throw GoogleCalendarError.missingClientID }

        let receiver = try OAuthLoopbackReceiver()
        defer { receiver.stop() }
        let redirectURI = try await receiver.start().absoluteString
        let verifier = OAuth.randomToken()
        let state = OAuth.randomToken()

        var components = URLComponents(url: Self.authorizationURL, resolvingAgainstBaseURL: false)!
        components.percentEncodedQuery = OAuth.formEncoded([
            ("client_id", clientID),
            ("redirect_uri", redirectURI),
            ("response_type", "code"),
            ("scope", Self.scope),
            ("code_challenge", OAuth.codeChallenge(for: verifier)),
            ("code_challenge_method", "S256"),
            ("state", state),
            // Ask for a refresh token, also when the app was authorized before.
            ("access_type", "offline"),
            ("prompt", "consent"),
        ])
        NSWorkspace.shared.open(components.url!)

        let redirect = try await receiver.waitForRedirect(timeout: Self.signInTimeout)
        let items = URLComponents(url: redirect, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

        guard value("state") == state else { throw GoogleCalendarError.signInFailed("Unexpected response from Google.") }
        if let error = value("error") {
            throw GoogleCalendarError.signInFailed(error == "access_denied" ? "Access was denied." : error)
        }
        guard let code = value("code") else { throw GoogleCalendarError.signInFailed("No authorization code received.") }

        let token = try await requestToken([
            ("grant_type", "authorization_code"),
            ("code", code),
            ("redirect_uri", redirectURI),
            ("code_verifier", verifier),
        ])
        // The user can leave the calendar permission unchecked on the consent page.
        guard token.scope?.split(separator: " ").contains(Substring(Self.scope)) ?? true else {
            throw GoogleCalendarError.calendarAccessNotGranted
        }
        guard let refreshToken = token.refreshToken else {
            throw GoogleCalendarError.signInFailed("Google didn't return a refresh token.")
        }
        try Keychain.save(refreshToken, service: Self.keychainService, account: Self.refreshTokenAccount)
        accessToken = (token.accessToken, Date().addingTimeInterval(token.expiresIn))
        isConnected = true
    }

    func disconnect() async {
        if let refreshToken = Keychain.read(service: Self.keychainService, account: Self.refreshTokenAccount) {
            // Best effort: also remove the app's access from the Google account.
            var request = URLRequest(url: Self.revokeURL)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data(OAuth.formEncoded([("token", refreshToken)]).utf8)
            _ = try? await URLSession.shared.data(for: request)
        }
        forgetCredentials()
    }

    private func forgetCredentials() {
        Keychain.delete(service: Self.keychainService, account: Self.refreshTokenAccount)
        accessToken = nil
        isConnected = false
        accountName = nil
        UserDefaults.standard.removeObject(forKey: Self.accountNameKey)
    }

    // MARK: Events

    func fetchEvents(in interval: DateInterval) async throws -> [Meeting] {
        var meetings: [Meeting] = []
        var pageToken: String?
        repeat {
            var parameters = [
                ("timeMin", interval.start.formatted(.iso8601)),
                ("timeMax", interval.end.formatted(.iso8601)),
                // Expand recurring events into their occurrences.
                ("singleEvents", "true"),
                ("maxResults", "2500"),
            ]
            if let pageToken { parameters.append(("pageToken", pageToken)) }
            var components = URLComponents(url: Self.eventsURL, resolvingAgainstBaseURL: false)!
            components.percentEncodedQuery = OAuth.formEncoded(parameters)

            let page: EventList = try await get(components.url!)
            meetings += (page.items ?? []).compactMap(meeting(from:))
            if let summary = page.summary, summary != accountName {
                // The primary calendar is named after the account's email address.
                accountName = summary
                UserDefaults.standard.set(summary, forKey: Self.accountNameKey)
            }
            pageToken = page.nextPageToken
        } while pageToken != nil
        return meetings
    }

    private func meeting(from event: Event) -> Meeting? {
        guard event.status != "cancelled",
              !Self.ignoredEventTypes.contains(event.eventType ?? ""),
              // All-day events have a `date` instead of a `dateTime`.
              let start = event.start?.dateTime.flatMap(Self.parseDate),
              let end = event.end?.dateTime.flatMap(Self.parseDate)
        else { return nil }

        let videoEntryPoint = event.conferenceData?.entryPoints?.first { $0.entryPointType == "video" }?.uri
        let url = (event.hangoutLink ?? videoEntryPoint).flatMap(URL.init(string:))
        let isDeclined = event.attendees?.first { $0.isSelf == true }?.responseStatus == "declined"
        return Meeting(
            id: "\(id):\(event.id)",
            providerID: id,
            title: event.summary ?? "",
            start: start,
            end: end,
            url: url,
            isDeclined: isDeclined
        )
    }

    nonisolated private static func parseDate(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions.insert(.withFractionalSeconds)
        return formatter.date(from: string)
    }

    // MARK: Requests

    /// Sends an authorized GET request, refreshing the access token once if it was rejected.
    private func get<Response: Decodable>(_ url: URL) async throws -> Response {
        var request = URLRequest(url: url)
        var (data, status) = try await send(&request, forceTokenRefresh: false)
        if status == 401 {
            (data, status) = try await send(&request, forceTokenRefresh: true)
        }
        guard (200..<300).contains(status) else {
            let message = (try? JSONDecoder().decode(APIErrorResponse.self, from: data))?.error.message
            throw GoogleCalendarError.requestFailed(status: status, message: message)
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }

    private func send(_ request: inout URLRequest, forceTokenRefresh: Bool) async throws -> (Data, Int) {
        let token = try await validAccessToken(forceRefresh: forceTokenRefresh)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    private func validAccessToken(forceRefresh: Bool) async throws -> String {
        if !forceRefresh, let accessToken, accessToken.expires > Date().addingTimeInterval(60) {
            return accessToken.value
        }
        guard let refreshToken = Keychain.read(service: Self.keychainService, account: Self.refreshTokenAccount) else {
            isConnected = false
            throw GoogleCalendarError.notConnected
        }
        do {
            let token = try await requestToken([("grant_type", "refresh_token"), ("refresh_token", refreshToken)])
            accessToken = (token.accessToken, Date().addingTimeInterval(token.expiresIn))
            return token.accessToken
        } catch GoogleCalendarError.tokenRequestFailed(error: "invalid_grant", _) {
            // The refresh token was revoked or expired.
            forgetCredentials()
            throw GoogleCalendarError.signInExpired
        }
    }

    private func requestToken(_ parameters: [(String, String)]) async throws -> TokenResponse {
        var parameters = parameters + [("client_id", clientID)]
        if !clientSecret.isEmpty { parameters.append(("client_secret", clientSecret)) }
        var request = URLRequest(url: Self.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(OAuth.formEncoded(parameters).utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let error = try? JSONDecoder().decode(TokenErrorResponse.self, from: data)
            throw GoogleCalendarError.tokenRequestFailed(error: error?.error ?? "HTTP \(status)", description: error?.errorDescription)
        }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }
}

// MARK: - API types

private struct TokenResponse: Decodable {
    var accessToken: String
    var expiresIn: TimeInterval
    var refreshToken: String?
    var scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
    }
}

private struct TokenErrorResponse: Decodable {
    var error: String
    var errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}

private struct APIErrorResponse: Decodable {
    struct Body: Decodable {
        var message: String?
    }

    var error: Body
}

private struct EventList: Decodable {
    var summary: String?
    var items: [Event]?
    var nextPageToken: String?
}

private struct Event: Decodable {
    struct Time: Decodable {
        var dateTime: String?
    }

    struct Attendee: Decodable {
        var isSelf: Bool?
        var responseStatus: String?

        enum CodingKeys: String, CodingKey {
            case isSelf = "self"
            case responseStatus
        }
    }

    struct ConferenceData: Decodable {
        struct EntryPoint: Decodable {
            var entryPointType: String?
            var uri: String?
        }

        var entryPoints: [EntryPoint]?
    }

    var id: String
    var status: String?
    var eventType: String?
    var summary: String?
    var start: Time?
    var end: Time?
    var hangoutLink: String?
    var conferenceData: ConferenceData?
    var attendees: [Attendee]?
}
