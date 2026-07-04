import Foundation

struct Message: Identifiable, Codable {
    let id: UUID
    let ride_id: UUID
    let sender_id: String
    let sender_role: String
    let body: String?
    let image_url: String?
    let created_at: Date
    let read: Bool?
}
