import Foundation
import Combine
#if canImport(FirebaseAuth)
import FirebaseAuth
#endif

struct RideHistoryRecord: Decodable, Identifiable {
    let id: String
    let pickupAddress: String?
    let dropoffAddress: String?
    let createdAt: String?
    let completedAt: String?
    let cancelledAt: String?
    let paidAmount: Double?
    let estimatedFare: Double?
    let currency: String?
    let rideType: String?
    let rideTypeLabel: String?
    let serviceType: String?
    let status: String

    enum CodingKeys: String, CodingKey {
        case id, currency, status
        case pickupAddress = "pickup_address"
        case dropoffAddress = "dropoff_address"
        case createdAt = "created_at"
        case completedAt = "completed_at"
        case cancelledAt = "cancelled_at"
        case paidAmount = "paid_amount"
        case estimatedFare = "estimated_fare"
        case rideType = "ride_type"
        case rideTypeLabel = "ride_type_label"
        case serviceType = "service_type"
    }

    var finalDateString: String? { completedAt ?? cancelledAt ?? createdAt }
    var fare: Double? { paidAmount ?? estimatedFare }
    var displayRideType: String { rideType ?? rideTypeLabel ?? serviceType ?? "—" }
}

struct ActiveRideRecord: Decodable, Identifiable {
    let id: String
    let status: String
    let driverId: String?
    let pickupAddress: String?
    let dropoffAddress: String?
    let pickupLat: Double?
    let pickupLng: Double?
    let dropoffLat: Double?
    let dropoffLng: Double?
    let paidAmount: Double?
    let estimatedFare: Double?
    let currency: String?
    let rideType: String?
    let rideTypeLabel: String?
    let serviceType: String?
    let driverName: String?
    let driverRating: Double?
    let driverVehicle: String?
    let driverServiceLevel: String?
    let driverPlate: String?
    let driverColor: String?
    let driverPhone: String?
    let driverPhotoURL: String?

    enum CodingKeys: String, CodingKey {
        case id, status, currency
        case driverId = "driver_id"
        case pickupAddress = "pickup_address"
        case dropoffAddress = "dropoff_address"
        case pickupLat = "pickup_lat"
        case pickupLng = "pickup_lng"
        case dropoffLat = "dropoff_lat"
        case dropoffLng = "dropoff_lng"
        case paidAmount = "paid_amount"
        case estimatedFare = "estimated_fare"
        case rideType = "ride_type"
        case rideTypeLabel = "ride_type_label"
        case serviceType = "service_type"
        case driverName = "driver_name"
        case driverRating = "driver_rating"
        case driverVehicle = "driver_vehicle_make_model"
        case driverServiceLevel = "driver_service_level"
        case driverPlate = "driver_plate"
        case driverColor = "driver_color"
        case driverPhone = "driver_phone"
        case driverPhotoURL = "driver_photo_url"
    }

    var normalizedStatus: String { status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    var displayRideType: String? { rideType ?? rideTypeLabel ?? serviceType }
    var fare: Double? { paidAmount ?? estimatedFare }
}

final class SupabaseRideService: ObservableObject {
    static let shared = SupabaseRideService()

    static let restorableStatuses: Set<String> = [
        "requested", "searching", "accepted", "arrived", "started", "in_progress"
    ]
    static let terminalStatuses: Set<String> = [
        "completed", "cancelled", "canceled", "cancelled_by_rider", "rider_cancelled",
        "cancelled_by_driver", "driver_cancelled", "cancelled_no_show", "no_show", "declined"
    ]

    private let baseURL = URL(string: "https://rpryqbdodbieioebedjg.supabase.co")!
    private let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJwcnlxYmRvZGJpZWlvZWJlZGpnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjUwNjE0MjYsImV4cCI6MjA4MDYzNzQyNn0.8ZTaA1bCyRUKb6U4NNZou6DMfXP3yyE1NeNL8Ljt9as"

    private init() {}

    func fetchRideHistory() async throws -> [RideHistoryRecord] {
        #if canImport(FirebaseAuth)
        guard let user = Auth.auth().currentUser, !user.uid.isEmpty else {
            throw NSError(domain: "SupabaseRideService.fetchRideHistory", code: 401, userInfo: [
                NSLocalizedDescriptionKey: "Please sign in to view your ride history."
            ])
        }

        let accessToken = try await user.getIDToken()
        var components = URLComponents(
            url: baseURL.appendingPathComponent("rest/v1/rides"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "rider_id", value: "eq.\(user.uid)"),
            URLQueryItem(name: "status", value: "in.(completed,cancelled,cancelled_by_driver,cancelled_by_rider)"),
            URLQueryItem(name: "order", value: "created_at.desc")
        ]

        guard let url = components?.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw NSError(domain: "SupabaseRideService.fetchRideHistory", code: statusCode, userInfo: [
                NSLocalizedDescriptionKey: "Unable to load ride history."
            ])
        }

        return try JSONDecoder().decode([RideHistoryRecord].self, from: data)
        #else
        throw NSError(domain: "SupabaseRideService.fetchRideHistory", code: 401, userInfo: [
            NSLocalizedDescriptionKey: "Please sign in to view your ride history."
        ])
        #endif
    }

    func fetchNewestActiveRide() async throws -> (ride: ActiveRideRecord?, accessToken: String) {
        #if canImport(FirebaseAuth)
        guard let user = Auth.auth().currentUser, !user.uid.isEmpty else {
            throw NSError(domain: "SupabaseRideService.fetchNewestActiveRide", code: 401, userInfo: [NSLocalizedDescriptionKey: "The rider is not signed in."])
        }

        var components = URLComponents(url: baseURL.appendingPathComponent("rest/v1/rides"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "rider_id", value: "eq.\(user.uid)"),
            URLQueryItem(name: "order", value: "created_at.desc"),
            URLQueryItem(name: "limit", value: "1")
        ]
        guard let url = components?.url else { throw URLError(.badURL) }

        func perform(token: String) async throws -> (Data, HTTPURLResponse) {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 15
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue(anonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            return (data, http)
        }

        var accessToken = try await user.getIDToken()
        var result = try await perform(token: accessToken)
        if result.1.statusCode == 401 {
            accessToken = try await user.getIDToken(forcingRefresh: true)
            result = try await perform(token: accessToken)
        }

        guard (200...299).contains(result.1.statusCode) else {
            throw NSError(domain: "SupabaseRideService.fetchNewestActiveRide", code: result.1.statusCode, userInfo: [NSLocalizedDescriptionKey: "Unable to restore the active ride."])
        }

        let ride = try JSONDecoder().decode([ActiveRideRecord].self, from: result.0).first
        guard let ride, Self.restorableStatuses.contains(ride.normalizedStatus) else {
            return (nil, accessToken)
        }
        return (ride, accessToken)
        #else
        throw NSError(domain: "SupabaseRideService.fetchNewestActiveRide", code: 401, userInfo: [NSLocalizedDescriptionKey: "The rider is not signed in."])
        #endif
    }

    func cancelPassengerRideByRider(rideId: String, reason: String? = nil) async throws {
        #if canImport(FirebaseAuth)
        guard UUID(uuidString: rideId) != nil else { throw URLError(.badURL) }
        guard let user = Auth.auth().currentUser, !user.uid.isEmpty else {
            throw NSError(domain: "SupabaseRideService.cancelPassengerRideByRider", code: 401, userInfo: [
                NSLocalizedDescriptionKey: "Please sign in before cancelling this ride."
            ])
        }

        let url = baseURL.appendingPathComponent("rest/v1/rpc/cancel_passenger_ride_by_rider_v1")
        let payload: [String: Any] = [
            "p_ride_id": rideId,
            "p_reason": (reason as Any?) ?? NSNull()
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)

        func perform(accessToken: String) async throws -> (Data, HTTPURLResponse) {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 12
            request.setValue(anonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.httpBody = body

            let hasToken = !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let method = request.httpMethod ?? "<nil>"
            let authorizationHeaderType = hasToken ? "Bearer Firebase ID token" : "missing"
            print("[Rider cancel] request URL: \(url.absoluteString)")
            print("[Rider cancel] HTTP method: \(method)")
            print("[Rider cancel] Firebase UID: \(user.uid)")
            print("[Rider cancel] Firebase ID token exists: \(hasToken)")
            print("[Rider cancel] Authorization header type: \(authorizationHeaderType)")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            let responseBody = String(data: data, encoding: .utf8) ?? "<non-UTF8 body>"
            print("[Rider cancel] HTTP status: \(http.statusCode)")
            print("[Rider cancel] response body: \(responseBody)")
            return (data, http)
        }

        var result = try await perform(accessToken: user.getIDToken())
        if result.1.statusCode == 401 {
            result = try await perform(accessToken: user.getIDToken(forcingRefresh: true))
        }
        guard (200...299).contains(result.1.statusCode) else {
            let responseBody = String(data: result.0, encoding: .utf8) ?? ""
            throw NSError(domain: "SupabaseRideService.cancelPassengerRideByRider", code: result.1.statusCode, userInfo: [
                NSLocalizedDescriptionKey: responseBody.isEmpty ? "Cancellation failed (HTTP \(result.1.statusCode))." : responseBody
            ])
        }
        await MainActor.run {
            self.stopObservingRideStatus(terminalStatus: "cancelled_by_rider")
        }
        #else
        throw NSError(domain: "SupabaseRideService.cancelPassengerRideByRider", code: 401)
        #endif
    }

    func createRideRequest(
        pickupLat: Double,
        pickupLng: Double,
        dropoffLat: Double,
        dropoffLng: Double,
        pickupAddress: String,
        dropoffAddress: String
    ) async throws -> String {

        #if canImport(FirebaseAuth)
        guard let user = Auth.auth().currentUser, !user.uid.isEmpty else {
            throw NSError(domain: "SupabaseRideService.createRideRequest", code: 401)
        }
        let accessToken = try await user.getIDToken()
        #else
        throw NSError(domain: "SupabaseRideService.createRideRequest", code: 401)
        #endif

        var components = URLComponents(
            url: baseURL.appendingPathComponent("/rest/v1/rides"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "select", value: "*")]

        guard let url = components?.url else { throw URLError(.badURL) }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("return=representation", forHTTPHeaderField: "Prefer")

        let pickupAddressFinal = pickupAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let dropoffAddressFinal = dropoffAddress.trimmingCharacters(in: .whitespacesAndNewlines)

        #if canImport(FirebaseAuth)
        let displayName = user.displayName
        let photoURL = user.photoURL?.absoluteString
        #else
        let displayName: String? = nil
        let photoURL: String? = nil
        #endif

        // If Firebase user profile isn't set, fall back to locally stored values (if any)
        let fallbackName = UserDefaults.standard.string(forKey: "lumo_profile_name")
        let fallbackPhoto = UserDefaults.standard.string(forKey: "lumo_profile_photo_url")

        let nameToSend: String = {
            if let n = displayName, !n.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return n }
            if let n = fallbackName, !n.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return n }
            return "Rider"
        }()

        let photoToSend: String = {
            if let p = photoURL, !p.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return p }
            if let p = fallbackPhoto, !p.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return p }
            return ""
        }()

        let payload: [String: Any] = [
            "rider_id": user.uid,
            "status": "requested",
            "driver_id": NSNull(),
            "pickup_lat": pickupLat,
            "pickup_lng": pickupLng,
            "dropoff_lat": dropoffLat,
            "dropoff_lng": dropoffLng,
            "pickup_address": pickupAddressFinal,
            "dropoff_address": dropoffAddressFinal,
            "rider_name": nameToSend,
            "rider_photo_url": photoToSend
        ]

        print("🚀 createRideRequest payload:")
        print(payload)

        req.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? -1
        let bodyString = String(data: data, encoding: .utf8) ?? ""
        print("📦 createRideRequest response status=\(status) body=\(bodyString)")
        print("ℹ️ If rider_name/rider_photo_url are missing or null in the response above, Supabase is stripping them (policy/trigger) or your app is not hitting this code path.")
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw NSError(domain: "SupabaseRideService.createRideRequest", code: 1, userInfo: [
                "status": (resp as? HTTPURLResponse)?.statusCode ?? -1,
                "body": String(data: data, encoding: .utf8) ?? ""
            ])
        }

        // Supabase returns an array of inserted rows when using return=representation
        let json = try JSONSerialization.jsonObject(with: data, options: [])
        if let arr = json as? [[String: Any]],
           let first = arr.first,
           let id = first["id"] as? String {
            DispatchQueue.main.async {
                self.activeRideStatus = "requested"
            }

            // ✅ Force-write rider identity after insert
            await patchRiderIdentity(rideId: id, name: nameToSend, photoURL: photoToSend)

            beginObservingRideStatus(rideId: id)
            return id
        }

        // Fallback: try to extract id from any other shape
        if let obj = json as? [String: Any], let id = obj["id"] as? String {
            DispatchQueue.main.async {
                self.activeRideStatus = "requested"
            }

            // ✅ Force-write rider identity after insert
            await patchRiderIdentity(rideId: id, name: nameToSend, photoURL: photoToSend)

            beginObservingRideStatus(rideId: id)
            return id
        }

        throw NSError(domain: "SupabaseRideService.createRideRequest", code: 2, userInfo: [
            "error": "Ride created but could not parse returned id",
            "body": String(data: data, encoding: .utf8) ?? ""
        ])
    }

    // ✅ Force-write rider identity after insert (some policies/triggers may null these on insert)
    private func patchRiderIdentity(rideId: String, name: String, photoURL: String) async {
        do {
            guard let user = Auth.auth().currentUser, !user.uid.isEmpty else {
                throw NSError(domain: "SupabaseRideService.patchRiderIdentity", code: 401)
            }
            let accessToken = try await user.getIDToken()
            let url = URL(string: "\(baseURL)/rest/v1/rides?id=eq.\(rideId)")!
            var req = URLRequest(url: url)
            req.httpMethod = "PATCH"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.setValue(anonKey, forHTTPHeaderField: "apikey")
            req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            req.setValue("return=representation", forHTTPHeaderField: "Prefer")

            let patch: [String: Any] = [
                "rider_name": name,
                "rider_photo_url": photoURL
            ]
            req.httpBody = try JSONSerialization.data(withJSONObject: patch, options: [])

            let (data, resp) = try await URLSession.shared.data(for: req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? -1
            let body = String(data: data, encoding: .utf8) ?? ""
            print("🩹 patchRiderIdentity status=\(status) body=\(body)")
        } catch {
            print("❌ patchRiderIdentity error:", error.localizedDescription)
        }
    }

    @Published private(set) var activeRideStatus: String? = nil
    @Published private(set) var activeRideID: String? = nil
    private var statusTask: Task<Void, Never>?
    private var sessionGeneration = UUID()

    func activeRideSessionToken() -> UUID {
        sessionGeneration
    }

    func isActiveRideSessionCurrent(_ token: UUID) -> Bool {
        sessionGeneration == token
    }

    func beginObservingRideStatus(rideId: String) {
        statusTask?.cancel()
        sessionGeneration = UUID()
        let generation = sessionGeneration
        activeRideID = rideId
        UserDefaults.standard.set(rideId, forKey: "lumo_active_ride_id")
        statusTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.fetchActiveRideStatus(rideId: rideId, generation: generation)
                guard !Task.isCancelled, self.isActiveRideSessionCurrent(generation) else { return }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private func fetchActiveRideStatus(rideId: String, generation: UUID) async {
        #if canImport(FirebaseAuth)
        guard isActiveRideSessionCurrent(generation), activeRideID == rideId else { return }
        guard let user = Auth.auth().currentUser, !user.uid.isEmpty else { return }

        var components = URLComponents(url: baseURL.appendingPathComponent("rest/v1/rides"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "select", value: "status"),
            URLQueryItem(name: "id", value: "eq.\(rideId)"),
            URLQueryItem(name: "rider_id", value: "eq.\(user.uid)"),
            URLQueryItem(name: "limit", value: "1")
        ]
        guard let url = components?.url else { return }

        func perform(accessToken: String) async throws -> (Data, HTTPURLResponse) {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue(anonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            return (data, http)
        }

        do {
            var result = try await perform(accessToken: user.getIDToken())
            if result.1.statusCode == 401 {
                result = try await perform(accessToken: user.getIDToken(forcingRefresh: true))
            }
            guard !Task.isCancelled, isActiveRideSessionCurrent(generation), activeRideID == rideId else { return }
            guard (200...299).contains(result.1.statusCode),
                  let rows = try JSONSerialization.jsonObject(with: result.0) as? [[String: Any]]
            else { return }

            guard let status = rows.first?["status"] as? String else {
                stopObservingRideStatus()
                return
            }
            let normalizedStatus = status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !Task.isCancelled, isActiveRideSessionCurrent(generation), activeRideID == rideId else { return }
            activeRideStatus = normalizedStatus
            if Self.terminalStatuses.contains(normalizedStatus) {
                stopObservingRideStatus(terminalStatus: normalizedStatus)
            }
        } catch {
            return
        }
        #endif
    }

    func stopObservingRideStatus(terminalStatus: String? = nil) {
        sessionGeneration = UUID()
        statusTask?.cancel()
        statusTask = nil
        activeRideID = nil
        activeRideStatus = terminalStatus
        UserDefaults.standard.removeObject(forKey: "lumo_active_ride_id")
    }
}
