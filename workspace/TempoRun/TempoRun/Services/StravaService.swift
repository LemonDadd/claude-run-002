import Foundation

/// Strava 同步（OAuth2 + Activity Upload API v3）
/// 实际工程中需在 https://www.strava.com/settings/api 注册应用并填入 clientID/secret。
/// 上传格式：GPX（含轨迹），multipart/form-data。
final class StravaService {
    static let shared = StravaService()

    private let clientID = "YOUR_STRAVA_CLIENT_ID"
    private let clientSecret = "YOUR_STRAVA_CLIENT_SECRET"
    private let redirectURI = "temporun://strava/callback"
    private let tokenKey = "stravaToken"

    private var accessToken: StravaToken? {
        get {
            guard let data = Keychain.load(tokenKey) else { return nil }
            return try? JSONDecoder().decode(StravaToken.self, from: data)
        }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                Keychain.save(tokenKey, data: data)
            } else {
                Keychain.delete(tokenKey)
            }
        }
    }

    var isConnected: Bool { accessToken != nil }

    var authorizeURL: URL? {
        URL(string: "https://www.strava.com/oauth/mobile/authorize?client_id=\(clientID)"
             + "&redirect_uri=\(redirectURI)&response_type=code&approval_prompt=auto&scope=activity:write")
    }

    func handleCallback(_ url: URL) async -> Bool {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = comps.queryItems?.first(where: { $0.name == "code" })?.value else { return false }
        var request = URLRequest(url: URL(string: "https://www.strava.com/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "client_id": clientID, "client_secret": clientSecret,
            "code": code, "grant_type": "authorization_code"
        ])
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return false }
            accessToken = try JSONDecoder().decode(StravaToken.self, from: data)
            return true
        } catch { return false }
    }

    func upload(_ run: RunSummary) async -> Bool {
        guard let token = accessToken?.access_token else { return false }
        let gpx = GPXExporter.makeGPX(run)
        let boundary = UUID().uuidString
        var request = URLRequest(url: URL(string: "https://www.strava.com/api/v3/uploads")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func append(_ string: String) { body.append(string.data(using: .utf8)!) }
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"data_type\"\r\n\r\ngpx\r\n")
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"name\"\r\n\r\nTempoRun \(Formatters.day.string(from: run.startDate))\r\n")
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"run.gpx\"\r\n")
        append("Content-Type: application/gpx+xml\r\n\r\n")
        body.append(gpx)
        append("\r\n--\(boundary)--\r\n")
        request.httpBody = body

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 201
        } catch { return false }
    }

    func disconnect() { accessToken = nil }

    private struct StravaToken: Codable {
        let access_token: String
        let refresh_token: String?
        let expires_at: TimeInterval?
    }
}

enum GPXExporter {
    static func makeGPX(_ run: RunSummary) -> Data {
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="TempoRun" xmlns="http://www.topografix.com/GPX/1/1">
        <trk><name>TempoRun \(Formatters.day.string(from: run.startDate))</name><trkseg>
        """
        let formatter = ISO8601DateFormatter()
        for p in run.track {
            xml += String(format: "<trkpt lat=\"%.6f\" lon=\"%.6f\"><ele>%.1f</ele><time>%@</time></trkpt>",
                          p.latitude, p.longitude, p.altitude, formatter.string(from: p.timestamp))
        }
        xml += "</trkseg></trk></gpx>"
        return xml.data(using: .utf8) ?? Data()
    }
}
