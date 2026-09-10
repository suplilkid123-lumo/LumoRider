import Foundation
import FirebaseAuth

final class CallSessionService {
    static let shared = CallSessionService()
    private let supabaseURL = URL(string: "https://rpryqbdodbieioebedjg.supabase.co")!
    private let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJwcnlxYmRvZGJpZWlvZWJlZGpnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjUwNjE0MjYsImV4cCI6MjA4MDYzNzQyNn0.8ZTaA1bCyRUKb6U4NNZou6DMfXP3yyE1NeNL8Ljt9as"
    private var provisionedUserID: String?
    private init() {}

    func createRiderCall(rideId: UUID, requestId: UUID) async throws -> CallSession {
        try await rpc("create_passenger_call_session_v1", body: [
            "p_ride_id": rideId.uuidString.lowercased(),
            "p_client_request_id": requestId.uuidString.lowercased()
        ])
    }
    func fetchCallSession(callId: UUID) async throws -> CallSession {
        try await rpc("get_passenger_call_session_v1", body: ["p_call_id": callId.uuidString.lowercased()])
    }
    func fetchIncomingCall(rideId: UUID) async throws -> CallSession? {
        let data = try await rpcData("get_incoming_passenger_call_v1", body: ["p_ride_id": rideId.uuidString.lowercased()])
        if data == Data("null".utf8) { return nil }
        return try decode(data)
    }
    func updateCallStatus(callId: UUID, action: String) async throws -> CallSession {
        try await rpc("update_passenger_call_session_v1", body: [
            "p_call_id": callId.uuidString.lowercased(), "p_action": action
        ])
    }
    func endCall(callId: UUID) async throws { _ = try await updateCallStatus(callId: callId, action: "end") }
    func declineCall(callId: UUID) async throws { _ = try await updateCallStatus(callId: callId, action: "decline") }
    func acceptCall(callId: UUID) async throws -> CallSession { try await updateCallStatus(callId: callId, action: "accept") }

    private func rpc<T: Decodable>(_ name: String, body: [String: Any]) async throws -> T {
        try decode(try await rpcData(name, body: body))
    }
    private func rpcData(_ name: String, body: [String: Any]) async throws -> Data {
        guard let user = Auth.auth().currentUser else { throw CallSessionServiceError.notLoggedIn }
        var request = URLRequest(url: supabaseURL.appendingPathComponent("rest/v1/rpc/\(name)"))
        request.httpMethod = "POST"; request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let token = try await freshAuthenticatedToken(for: user)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        var (data,response) = try await URLSession.shared.data(for: request)
        if (response as? HTTPURLResponse)?.statusCode == 401 {
            let refreshedToken = try await user.getIDToken(forcingRefresh: true)
            request.setValue("Bearer \(refreshedToken)", forHTTPHeaderField: "Authorization")
            (data,response) = try await URLSession.shared.data(for: request)
        }
        guard Auth.auth().currentUser?.uid == user.uid else { throw URLError(.cancelled) }
        guard let http = response as? HTTPURLResponse else { throw CallSessionServiceError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            let payload = try? JSONSerialization.jsonObject(with: data) as? [String:Any]
            throw CallSessionServiceError.serverError(statusCode: http.statusCode,
                message: payload?["message"] as? String ?? payload?["error"] as? String ?? "Jiylo could not authorize this ride call.")
        }
        return data
    }

    func freshAuthenticatedToken(for user: User) async throws -> String {
        if provisionedUserID != user.uid {
            let initialToken = try await user.getIDToken(forcingRefresh: true)
            var request = URLRequest(url: supabaseURL.appendingPathComponent("functions/v1/provision-rider-role"))
            request.httpMethod = "POST"
            request.timeoutInterval = 20
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(initialToken)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                throw CallSessionServiceError.serverError(
                    statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1,
                    message: payload?["error"] as? String ?? "Rider call authorization could not be established."
                )
            }
            guard Auth.auth().currentUser?.uid == user.uid else { throw URLError(.cancelled) }
            provisionedUserID = user.uid
        }
        return try await user.getIDToken(forcingRefresh: true)
    }
    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do { return try makeDecoder().decode(T.self, from: data) }
        catch { throw CallSessionServiceError.invalidResponse }
    }
    private func makeDecoder() -> JSONDecoder {
        let decoder=JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container=try decoder.singleValueContainer(); let value=try container.decode(String.self)
            let fractional=ISO8601DateFormatter(); fractional.formatOptions=[.withInternetDateTime,.withFractionalSeconds]
            if let date=fractional.date(from:value) { return date }
            if let date=ISO8601DateFormatter().date(from:value) { return date }
            throw DecodingError.dataCorruptedError(in:container,debugDescription:"Invalid date")
        }
        return decoder
    }
}

enum CallSessionServiceError: LocalizedError {
    case notLoggedIn, invalidResponse
    case serverError(statusCode:Int,message:String)
    var errorDescription:String? { switch self {
    case .notLoggedIn: "Sign in again before calling your Driver."
    case .invalidResponse: "Jiylo returned an invalid call response."
    case .serverError(let statusCode,let message): "Call request failed (HTTP \(statusCode)): \(message)"
    } }
}
