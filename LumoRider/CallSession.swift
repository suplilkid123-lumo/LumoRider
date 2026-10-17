import Foundation

enum CallStatus: String, Codable {
    case ringing
    case accepted
    case declined
    case ended
    case missed
    case failed
}

enum CallUserType: String, Codable {
    case rider
    case driver
}

struct CallSession: Identifiable, Codable {
    let id: UUID
    let rideId: UUID
    let callerType: CallUserType
    let receiverType: CallUserType
    let status: CallStatus
    let createdAt: Date
    let acceptedAt: Date?
    let answeredAt: Date?
    let endedAt: Date?
    let expiresAt: Date
    let isCaller: Bool
    let otherPartyName: String

    enum CodingKeys: String, CodingKey {
        case id
        case rideId = "ride_id"
        case callerType = "caller_type"
        case receiverType = "receiver_type"
        case status
        case createdAt = "created_at"
        case acceptedAt = "accepted_at"
        case answeredAt = "answered_at"
        case endedAt = "ended_at"
        case expiresAt = "expires_at"
        case isCaller = "is_caller"
        case otherPartyName = "other_party_name"
    }
}
