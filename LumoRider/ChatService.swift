// ChatService.swift
import Foundation
import UIKit
import Combine
import UserNotifications
import FirebaseAuth

// ✅ Matches public.messages

struct ChatRow: Identifiable, Decodable, Equatable {
    let id: UUID
    let ride_id: UUID
    let sender_id: String?
    let sender_role: String?
    let body: String?
    let image_url: String?
    let sender: String?
    let type: String?
    let created_at: Date
    var read: Bool?
}

struct SignedChatImageURL: Equatable {
    let url: URL
    let expiresAt: Date
}

// MARK: - Shared flag (module-wide): whether ChatView is currently visible
enum LumoChatPresence {
    private static var openRideIDs: Set<UUID> = []

    static func setOpen(_ isOpen: Bool, rideId: UUID) {
        if isOpen { openRideIDs.insert(rideId) } else { openRideIDs.remove(rideId) }
    }

    static func isOpen(rideId: UUID) -> Bool {
        openRideIDs.contains(rideId)
    }
}

// MARK: - Case A: Local banner when app is open but ChatView is NOT visible
private enum LocalPush {
    static func showIfChatClosed(rideId: UUID, title: String, body: String) {
        guard !LumoChatPresence.isOpen(rideId: rideId) else { return }

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
    private var activeUserID: String?
    private var sessionGeneration = UUID()
    private var loadInFlight = false

    deinit {
        pollingTask?.cancel()
    }

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
        guard pollingRideId == rideId, !loadInFlight,
              let userID = activeUserID,
              Auth.auth().currentUser?.uid == userID else { return }
        let generation = sessionGeneration
        loadInFlight = true
        defer {
            if sessionGeneration == generation { loadInFlight = false }
        }
        do {
            let data = try await get(
                path: "messages",
                queryItems: [
                    URLQueryItem(name: "ride_id", value: "eq.\(rideId.uuidString)"),
                    URLQueryItem(name: "order", value: "created_at.asc")
                ]
            )
            let decoded = try decoder.decode([ChatRow].self, from: data)
            guard !Task.isCancelled, sessionGeneration == generation,
                  pollingRideId == rideId,
                  Auth.auth().currentUser?.uid == userID else { return }

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

                    LocalPush.showIfChatClosed(rideId: rideId, title: title, body: bodyText)
                }
            }

            rows = Array(decoded)
            recomputeUnread()
        } catch {
            if let ns = error as NSError? {
                print("❌ loadMessages failed:", ns.code, ns.userInfo)
            } else {
                print("❌ loadMessages failed:", error)
            }
        }
    }

    func sendMessage(rideId: UUID, senderId: String, senderRole: String, body: String) async {
        guard pollingRideId == rideId,
              activeUserID == senderId,
              Auth.auth().currentUser?.uid == senderId,
              validRole(senderRole), validFirebaseUID(senderId) else { return }
        let generation = sessionGeneration
        let payload: [String: Any] = [
            "ride_id": rideId.uuidString,
            "sender_id": senderId,
            "sender_role": senderRole,
            "sender": senderRole,
            "type": "text",
            "body": body
        ]

        do {
            _ = try await post(path: "messages", json: payload)
            guard !Task.isCancelled, sessionGeneration == generation,
                  pollingRideId == rideId,
                  Auth.auth().currentUser?.uid == senderId else { return }
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
        guard pollingRideId == rideId,
              activeUserID == senderId,
              Auth.auth().currentUser?.uid == senderId,
              validRole(senderRole), validFirebaseUID(senderId) else { return }
        let generation = sessionGeneration
        do {
            let objectPath = try await uploadChatImage(image, rideId: rideId, senderId: senderId, senderRole: senderRole)
            guard !Task.isCancelled, sessionGeneration == generation,
                  pollingRideId == rideId,
                  Auth.auth().currentUser?.uid == senderId else { return }

            let payload: [String: Any] = [
                "ride_id": rideId.uuidString,
                "sender_id": senderId,
                "sender_role": senderRole,
                "sender": senderRole,
                "type": "image",
                "body": objectPath,
                "image_url": objectPath
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
        guard pollingRideId == rideId, let userID = activeUserID,
              Auth.auth().currentUser?.uid == userID else { return }
        let generation = sessionGeneration
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
            guard !Task.isCancelled, sessionGeneration == generation,
                  pollingRideId == rideId,
                  Auth.auth().currentUser?.uid == userID else { return }

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

    func start(rideId: UUID, userID: String, every seconds: Double = 1.0) {
        stopPolling()
        guard Auth.auth().currentUser?.uid == userID else { return }
        sessionGeneration = UUID()
        let generation = sessionGeneration
        pollingRideId = rideId
        activeUserID = userID
        rows = []
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self,
                      self.sessionGeneration == generation,
                      self.pollingRideId == rideId,
                      Auth.auth().currentUser?.uid == userID else { return }
                await self.loadMessages(rideId: rideId)
                let delay = seconds.isFinite ? min(60, max(0.1, seconds)) : 1
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            }
        }
    }

    func stopPolling() {
        sessionGeneration = UUID()
        pollingTask?.cancel()
        pollingTask = nil
        pollingRideId = nil
        activeUserID = nil
        loadInFlight = false
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

            let (data, resp) = try await SupabaseRideService.shared.authenticatedRideData(for: req)
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
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        return req
    }

    private func get(path: String, queryItems: [URLQueryItem]) async throws -> Data {
        let req = try makeRequest(path: path, method: "GET", queryItems: queryItems)
        let (data, resp) = try await SupabaseRideService.shared.authenticatedRideData(for: req)
        try validate(resp: resp, data: data, tag: "GET \(path)")
        return data
    }

    private func post(path: String, json: [String: Any]) async throws -> Data {
        var req = try makeRequest(path: path, method: "POST", queryItems: nil)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("return=representation", forHTTPHeaderField: "Prefer")
        req.httpBody = try JSONSerialization.data(withJSONObject: json, options: [])

        let (data, resp) = try await SupabaseRideService.shared.authenticatedRideData(for: req)
        try validate(resp: resp, data: data, tag: "POST \(path)")
        return data
    }

    private func patch(path: String, queryItems: [URLQueryItem], json: [String: Any]) async throws -> Data {
        var req = try makeRequest(path: path, method: "PATCH", queryItems: queryItems)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        req.httpBody = try JSONSerialization.data(withJSONObject: json, options: [])

        let (data, resp) = try await SupabaseRideService.shared.authenticatedRideData(for: req)
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

    func signedImageURL(for attachment: String, rideId: UUID) async throws -> SignedChatImageURL {
        let objectPath = try validatedAttachmentPath(attachment, rideId: rideId)
        let signingURL = supabaseURL.appendingPathComponent("storage/v1/object/sign/chat-images/\(objectPath)")
        var request = URLRequest(url: signingURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["expiresIn": 300])

        let (data, response) = try await SupabaseRideService.shared.authenticatedRideData(for: request)
        try validate(resp: response, data: data, tag: "SIGN chat image")
        let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let signedPath = (payload?["signedURL"] ?? payload?["signedUrl"]) as? String,
              let signedURL = signedURL(from: signedPath, objectPath: objectPath) else {
            throw NSError(domain: "ChatService.signedImageURL", code: 0)
        }
        return SignedChatImageURL(url: signedURL, expiresAt: Date().addingTimeInterval(300))
    }

    private func uploadChatImage(_ image: UIImage, rideId: UUID, senderId: String, senderRole: String) async throws -> String {
        guard let data = image.jpegData(compressionQuality: 0.85) else {
            throw NSError(domain: "ChatService.uploadChatImage", code: 0)
        }
        guard senderRole.lowercased() == "rider", validFirebaseUID(senderId) else {
            throw NSError(domain: "ChatService.uploadChatImage", code: 1)
        }

        let fileName = "\(UUID().uuidString).jpg"
        let objectPath = "\(rideId.uuidString)/rider/\(senderId)/\(fileName)"
        guard (try? validatedAttachmentPath(objectPath, rideId: rideId)) != nil else {
            throw NSError(domain: "ChatService.uploadChatImage", code: 2)
        }
        let uploadURL = supabaseURL.appendingPathComponent("storage/v1/object/chat-images/\(objectPath)")

        var req = URLRequest(url: uploadURL)
        req.httpMethod = "POST"
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")

        let (respData, resp) = try await SupabaseRideService.shared.authenticatedRideUpload(for: req, from: data)
        try validate(resp: resp, data: respData, tag: "UPLOAD chat-images")

        return objectPath
    }

    private func validatedAttachmentPath(_ attachment: String, rideId: UUID) throws -> String {
        let value = attachment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.contains("\\"), !value.contains("%"), !value.contains("..") else {
            throw NSError(domain: "ChatService.attachment", code: 1)
        }

        if let legacyPath = validatedLegacyPublicPath(value) {
            return legacyPath
        }

        guard URL(string: value)?.scheme == nil else {
            throw NSError(domain: "ChatService.attachment", code: 2)
        }
        let components = value.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard components.count == 4,
              UUID(uuidString: components[0]) == rideId,
              validRole(components[1]),
              validFirebaseUID(components[2]),
              validObjectID(components[3]) else {
            throw NSError(domain: "ChatService.attachment", code: 3)
        }
        return value
    }

    private func validatedLegacyPublicPath(_ value: String) -> String? {
        guard let url = URL(string: value),
              url.scheme == "https", url.host == supabaseURL.host,
              url.port == nil, url.query == nil, url.fragment == nil,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              !components.percentEncodedPath.contains("%") else { return nil }
        let prefix = "/storage/v1/object/public/chat-images/"
        guard url.path.hasPrefix(prefix) else { return nil }
        let objectID = String(url.path.dropFirst(prefix.count))
        guard !objectID.contains("/"), !objectID.contains("\\"), validObjectID(objectID) else { return nil }
        return objectID
    }

    private func signedURL(from responseValue: String, objectPath: String) -> URL? {
        guard let url = URL(string: responseValue, relativeTo: supabaseURL)?.absoluteURL,
              url.scheme == "https", url.host == supabaseURL.host,
              url.path == "/storage/v1/object/sign/chat-images/\(objectPath)" else { return nil }
        return url
    }

    private func validRole(_ value: String) -> Bool {
        ["rider", "driver"].contains(value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    private func validFirebaseUID(_ value: String) -> Bool {
        value.range(of: "^[A-Za-z0-9_-]{1,128}$", options: .regularExpression) != nil
    }

    private func validObjectID(_ value: String) -> Bool {
        value.range(of: "^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\\.(jpg|jpeg|png|heic)$", options: .regularExpression) != nil
    }
}
