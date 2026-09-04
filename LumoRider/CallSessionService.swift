import Foundation
import FirebaseAuth

final class CallSessionService {
    static let shared = CallSessionService()
    private let supabaseURL = URL(string: "https://rpryqbdodbieioebedjg.supabase.co")!
    private let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJwcnlxYmRvZGJpZWlvZWJlZGpnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjUwNjE0MjYsImV4cCI6MjA4MDYzNzQyNn0.8ZTaA1bCyRUKb6U4NNZou6DMfXP3yyE1NeNL8Ljt9as"
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
        let token = try await user.getIDToken()
        var request = URLRequest(url: supabaseURL.appendingPathComponent("rest/v1/rpc/\(name)"))
        request.httpMethod = "POST"; request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data,response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CallSessionServiceError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            let payload = try? JSONSerialization.jsonObject(with: data) as? [String:Any]
            throw CallSessionServiceError.serverError(statusCode: http.statusCode,
                message: payload?["message"] as? String ?? "Lumo could not authorize this ride call.")
        }
        return data
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
    case .invalidResponse: "Lumo returned an invalid call response."
    case .serverError(_,let message): message
    } }
}
