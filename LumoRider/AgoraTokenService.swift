import Foundation
import FirebaseAuth

struct AgoraTokenResponse: Decodable {
    let appId:String; let token:String; let channelName:String; let uid:UInt; let expiresIn:Int; let callId:UUID
    enum CodingKeys:String,CodingKey { case appId="app_id",token,channelName="channel_name",uid,expiresIn="expires_in",callId="call_id" }
}

final class AgoraTokenService {
    static let shared=AgoraTokenService()
    private let functionURL=URL(string:"https://rpryqbdodbieioebedjg.supabase.co/functions/v1/passenger-voice-token")!
    private let anonKey="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJwcnlxYmRvZGJpZWlvZWJlZGpnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjUwNjE0MjYsImV4cCI6MjA4MDYzNzQyNn0.8ZTaA1bCyRUKb6U4NNZou6DMfXP3yyE1NeNL8Ljt9as"
    private init() {}
    func fetchToken(callId:UUID) async throws -> AgoraTokenResponse {
        guard let user=Auth.auth().currentUser else { throw AgoraTokenServiceError.notLoggedIn }
        var request=URLRequest(url:functionURL); request.httpMethod="POST"; request.timeoutInterval=20
        request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        request.setValue(anonKey,forHTTPHeaderField:"apikey")
        request.httpBody=try JSONEncoder().encode(["call_id":callId.uuidString.lowercased()])
        let token = try await CallSessionService.shared.freshAuthenticatedToken(for: user)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data,response)=try await URLSession.shared.data(for:request)
        guard Auth.auth().currentUser?.uid == user.uid else { throw URLError(.cancelled) }
        guard let http=response as? HTTPURLResponse else { throw AgoraTokenServiceError.invalidResponse }
        guard (200...299).contains(http.statusCode) else { throw AgoraTokenServiceError.serverError }
        let result=try JSONDecoder().decode(AgoraTokenResponse.self,from:data)
        guard result.callId==callId,!result.token.isEmpty,!result.channelName.isEmpty,result.uid>0 else { throw AgoraTokenServiceError.invalidResponse }
        return result
    }
}

enum AgoraTokenServiceError:LocalizedError {
    case notLoggedIn,invalidResponse,serverError
    var errorDescription:String? { switch self {
    case .notLoggedIn:"Sign in again before calling your Driver."
    case .invalidResponse:"Jiylo returned an invalid voice authorization."
    case .serverError:"Jiylo could not authorize a private voice call. Message your Driver or try again."
    } }
}
