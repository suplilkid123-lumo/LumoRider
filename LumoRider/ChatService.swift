// ChatService.swift
import Foundation
import UIKit
import Combine
import UserNotifications

// ✅ Matches public.messages

struct ChatRow: Identifiable, Decodable, Equatable {
    let id: UUID
    let ride_id: UUID
    let sender_id: String?
    let sender_role: String?
    let body: String?
    let image_url: String?
    let created_at: Date
    var read: Bool?
}

// MARK: - Shared flag (module-wide): whether ChatView is currently visible
enum LumoChatPresence {
    static var isChatOpen: Bool = false
}

// MARK: - Case A: Local banner when app is open but ChatView is NOT visible
private enum LocalPush {
    static func showIfChatClosed(title: String, body: String) {
        guard LumoChatPresence.isChatOpen == false else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "chat_local_" + UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }
}

// MARK: - REST Chat Service (shared logic for Rider + Driver)
@MainActor
final class ChatService: ObservableObject {

    private let supabaseURL = URL(string: "https://rpryqbdodbieioebedjg.supabase.co")!
    private let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJwcnlxYmRvZGJpZWlvZWJlZGpnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjUwNjE0MjYsImV4cCI6MjA4MDYzNzQyNn0.8ZTaA1bCyRUKb6U4NNZou6DMfXP3yyE1NeNL8Ljt9as"

    init() {
        if supabaseURL.absoluteString.contains("YOUR_PROJECT_REF") || anonKey.contains("YOUR_SUPABASE_ANON_KEY") {
            fatalError("ChatService: Set supabaseURL + anonKey (Supabase Dashboard → Project Settings → API)")
        }
    }

    @Published var rows: [ChatRow] = []

    // Unread indicator (Uber/Lyft-style dot/badge)
    @Published var hasUnread: Bool = false
    @Published var unreadCount: Int = 0

    // Set this from the UI: "rider" in Rider app, "driver" in Driver app
    var viewerRole: String = "rider"

    private var pollingTask: Task<Void, Never>?
    private var pollingRideId: UUID?

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { dec in
            let container = try dec.singleValueContainer()
            let str = try container.decode(String.self)

            let f1 = ISO8601DateFormatter()
            f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = f1.date(from: str) { return date }

            let f2 = ISO8601DateFormatter()
            f2.formatOptions = [.withInternetDateTime]
            if let date = f2.date(from: str) { return date }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO8601 date: \(str)"
            )
        }
        return d
    }()

    func loadMessages(rideId: UUID) async {
        do {
            let data = try await get(
                path: "messages",
                queryItems: [
                    URLQueryItem(name: "ride_id", value: "eq.\(rideId.uuidString)"),
                    URLQueryItem(name: "order", value: "created_at.asc")
                ]
            )
            let decoded = try decoder.decode([ChatRow].self, from: data)

            // ✅ Case A: If a NEW incoming message arrives (not on first load) and ChatView is not open, show a banner
            let previousIds = Set(rows.map { $0.id })
            if !previousIds.isEmpty {
                let otherRole = (viewerRole.lowercased() == "driver") ? "rider" : "driver"
                let newlyAddedIncoming = decoded
                    .filter { !previousIds.contains($0.id) }
                    .filter { ($0.sender_role ?? "").lowercased() == otherRole }

                if let newest = newlyAddedIncoming.sorted(by: { $0.created_at < $1.created_at }).last {
                    let title = (otherRole == "driver") ? "New message from driver" : "New message from rider"
                    let bodyText: String = {
                        let t = (newest.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        if !t.isEmpty { return t }
                        let img = (newest.image_url ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        if !img.isEmpty { return "Sent a photo" }
                        return "New message"
                    }()

                    LocalPush.showIfChatClosed(title: title, body: bodyText)
                }
            }

            rows = Array(decoded)
            recomputeUnread()

            if pollingTask == nil || pollingRideId != rideId {
                startPolling(rideId: rideId, every: 1.0)
            }
        } catch {
            if let ns = error as NSError? {
                print("❌ loadMessages failed:", ns.code, ns.userInfo)
            } else {
                print("❌ loadMessages failed:", error)
            }
        }
    }

    func sendMessage(rideId: UUID, senderId: String, senderRole: String, body: String) async {
        let payload: [String: Any] = [
            "ride_id": rideId.uuidString,
            "sender_id": senderId,
            "sender_role": senderRole,
            "body": body
        ]

        do {
            _ = try await post(path: "messages", json: payload)
            await notifyDriverOfNewMessage(rideId: rideId, senderRole: senderRole, messageBody: body)
            await loadMessages(rideId: rideId)
        } catch {
            if let ns = error as NSError? {
                print("❌ sendMessage failed:", ns.code, ns.userInfo)
            } else {
                print("❌ sendMessage failed:", error)
            }
        }
    }

    func sendImageMessage(rideId: UUID, senderId: String, senderRole: String, image: UIImage) async {
        do {
            let imageURL = try await uploadChatImage(image)

            let payload: [String: Any] = [
                "ride_id": rideId.uuidString,
                "sender_id": senderId,
                "sender_role": senderRole,
                "image_url": imageURL
            ]

            _ = try await post(path: "messages", json: payload)
            await notifyDriverOfNewMessage(rideId: rideId, senderRole: senderRole, messageBody: "Sent a photo")
            await loadMessages(rideId: rideId)
        } catch {
            if let ns = error as NSError? {
                print("❌ sendImageMessage failed:", ns.code, ns.userInfo)
            } else {
                print("❌ sendImageMessage failed:", error)
            }
        }
    }

    func markIncomingMessagesRead(rideId: UUID) async {
        let otherRole = (viewerRole == "driver") ? "rider" : "driver"

        do {
            _ = try await patch(
                path: "messages",
                queryItems: [
                    URLQueryItem(name: "ride_id", value: "eq.\(rideId.uuidString)"),
                    URLQueryItem(name: "sender_role", value: "eq.\(otherRole)"),
                    URLQueryItem(name: "or", value: "(read.is.null,read.eq.false)")
                ],
                json: ["read": true]
            )

            for idx in rows.indices {
                if rows[idx].sender_role?.lowercased() == otherRole {
                    rows[idx].read = true
                }
            }
            recomputeUnread()
        } catch {
            if let ns = error as NSError? {
                print("❌ markIncomingMessagesRead failed:", ns.code, ns.userInfo)
            } else {
                print("❌ markIncomingMessagesRead failed:", error)
            }
        }
    }

    func startPolling(rideId: UUID, every seconds: Double = 1.0) {
        stopPolling()
        pollingRideId = rideId
        pollingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.loadMessages(rideId: rideId)
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        pollingRideId = nil
    }

    private func recomputeUnread() {
        let otherRole = (viewerRole == "driver") ? "rider" : "driver"
        let unread = rows.filter { row in
            (row.sender_role?.lowercased() == otherRole) && (row.read != true)
        }.count
        unreadCount = unread
        hasUnread = unread > 0
    }

    // MARK: - Push notify driver when rider sends a message

    private func fetchDriverIdForRide(_ rideId: UUID) async throws -> String {
        let data = try await get(
            path: "rides",
            queryItems: [
                URLQueryItem(name: "select", value: "driver_id"),
                URLQueryItem(name: "id", value: "eq.\(rideId.uuidString)"),
                URLQueryItem(name: "limit", value: "1")
            ]
        )

        guard
            let arr = try JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]],
            let first = arr.first,
            let driverId = first["driver_id"] as? String,
            !driverId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw NSError(domain: "ChatService.fetchDriverIdForRide", code: 0, userInfo: [
                "reason": "driver_id missing for ride"
            ])
        }

        return driverId
    }

    private func notifyDriverOfNewMessage(rideId: UUID, senderRole: String, messageBody: String) async {
        // Only notify the DRIVER when the RIDER sends a message.
        // (Driver-to-rider notifications are handled in the driver app / other flow.)
        let senderRoleLower = senderRole.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard senderRoleLower == "rider" else { return }

        print("📨 notifyDriverOfNewMessage: rider -> driver push for rideId=\(rideId)")

        do {
            let driverId = try await fetchDriverIdForRide(rideId)
            print("📨 notifyDriverOfNewMessage: driver_id=\(driverId)")

            let url = supabaseURL.appendingPathComponent("/functions/v1/notify-new-message")
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue(anonKey, forHTTPHeaderField: "apikey")
            req.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")

            let bodyText = messageBody.trimmingCharacters(in: .whitespacesAndNewlines)
            let payload: [String: Any] = [
                "to_user_id": driverId,
                "title": "New message",
                "body": bodyText.isEmpty ? "You received a new message" : bodyText,
                "data": [
                    "type": "chat",
                    "ride_id": rideId.uuidString,
                    "sender": "rider"
                ]
            ]

            req.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

            let (data, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse {
                print("📨 notifyDriverOfNewMessage: status=\(http.statusCode)")
            }
            print("📨 notifyDriverOfNewMessage: response=\(String(data: data, encoding: .utf8) ?? "")")
            try validate(resp: resp, data: data, tag: "POST functions/notify-new-message")
        } catch {
            if let ns = error as NSError? {
                print("❌ notifyDriverOfNewMessage failed:", ns.code, ns.userInfo)
            } else {
                print("❌ notifyDriverOfNewMessage failed:", error)
            }
        }
    }

    private func makeRequest(
        path: String,
        method: String,
        queryItems: [URLQueryItem]? = nil
    ) throws -> URLRequest {
        var components = URLComponents(
            url: supabaseURL.appendingPathComponent("/rest/v1/\(path)"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = queryItems

        guard let url = components?.url else {
            throw NSError(domain: "ChatService.makeRequest", code: 0)
        }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        return req
    }

    private func get(path: String, queryItems: [URLQueryItem]) async throws -> Data {
        let req = try makeRequest(path: path, method: "GET", queryItems: queryItems)
        let (data, resp) = try await URLSession.shared.data(for: req)
        try validate(resp: resp, data: data, tag: "GET \(path)")
        return data
    }

    private func post(path: String, json: [String: Any]) async throws -> Data {
        var req = try makeRequest(path: path, method: "POST", queryItems: nil)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("return=representation", forHTTPHeaderField: "Prefer")
        req.httpBody = try JSONSerialization.data(withJSONObject: json, options: [])

        let (data, resp) = try await URLSession.shared.data(for: req)
        try validate(resp: resp, data: data, tag: "POST \(path)")
        return data
    }

    private func patch(path: String, queryItems: [URLQueryItem], json: [String: Any]) async throws -> Data {
        var req = try makeRequest(path: path, method: "PATCH", queryItems: queryItems)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        req.httpBody = try JSONSerialization.data(withJSONObject: json, options: [])

        let (data, resp) = try await URLSession.shared.data(for: req)
        try validate(resp: resp, data: data, tag: "PATCH \(path)")
        return data
    }

    private func validate(resp: URLResponse, data: Data, tag: String) throws {
        guard let http = resp as? HTTPURLResponse else {
            throw NSError(domain: "ChatService.\(tag)", code: -1)
        }
        guard (200...299).contains(http.statusCode) else {
            throw NSError(domain: "ChatService.\(tag)", code: http.statusCode, userInfo: [
                "status": http.statusCode,
                "body": String(data: data, encoding: .utf8) ?? ""
            ])
        }
    }

    private func uploadChatImage(_ image: UIImage) async throws -> String {
        guard let data = image.jpegData(compressionQuality: 0.85) else {
            throw NSError(domain: "ChatService.uploadChatImage", code: 0)
        }

        let fileName = "\(UUID().uuidString).jpg"
        let uploadURL = supabaseURL.appendingPathComponent("/storage/v1/object/chat-images/\(fileName)")

        var req = URLRequest(url: uploadURL)
        req.httpMethod = "POST"
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        req.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")

        let (respData, resp) = try await URLSession.shared.upload(for: req, from: data)
        try validate(resp: resp, data: respData, tag: "UPLOAD chat-images")

        return supabaseURL
            .appendingPathComponent("/storage/v1/object/public/chat-images/\(fileName)")
            .absoluteString
    }
}
