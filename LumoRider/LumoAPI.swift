import Foundation
#if canImport(FirebaseAuth)
import FirebaseAuth
#endif

// MARK: - Data models

struct CreateRideRequest: Codable {
    let riderId: String
    let pickupLat: Double
    let pickupLng: Double
    let dropoffLat: Double
    let dropoffLng: Double
    let pickupAddress: String
    let dropoffAddress: String
}

struct RideDTO: Codable, Identifiable {
    let id: String
    let rider_id: String
    let driver_id: String?
    let status: String
    let pickup_lat: Double
    let pickup_lng: Double
    let dropoff_lat: Double
    let dropoff_lng: Double
    let pickup_address: String
    let dropoff_address: String
    let created_at: String
}

// MARK: - Supabase REST client (PostgREST)

final class LumoAPI {

    private let baseURL = URL(string: "https://rpryqbdodbieioebedjg.supabase.co")!
    private let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJwcnlxYmRvZGJpZWlvZWJlZGpnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjUwNjE0MjYsImV4cCI6MjA4MDYzNzQyNn0.8ZTaA1bCyRUKb6U4NNZou6DMfXP3yyE1NeNL8Ljt9as"

    private func makeRequest(
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem]? = nil
    ) throws -> URLRequest {

        var components = URLComponents(
            url: baseURL.appendingPathComponent("/rest/v1/\(path)"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = queryItems

        guard let url = components?.url else { throw URLError(.badURL) }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        return req
    }

    // MARK: - Rider: create ride (status = requested)

    func createRide(_ body: CreateRideRequest) async throws -> RideDTO {
        var req = try makeRequest(
            path: "rides",
            method: "POST",
            queryItems: [URLQueryItem(name: "select", value: "*")]
        )

        req.setValue("return=representation", forHTTPHeaderField: "Prefer")

        #if canImport(FirebaseAuth)
        let displayName = Auth.auth().currentUser?.displayName
        let photoURL = Auth.auth().currentUser?.photoURL?.absoluteString
        #else
        let displayName: String? = nil
        let photoURL: String? = nil
        #endif

        let payload: [String: Any] = [
            "rider_id": body.riderId,
            "pickup_lat": body.pickupLat,
            "pickup_lng": body.pickupLng,
            "dropoff_lat": body.dropoffLat,
            "dropoff_lng": body.dropoffLng,
            "pickup_address": body.pickupAddress,
            "dropoff_address": body.dropoffAddress,
            "status": "requested",
            "driver_id": NSNull(),
            "rider_name": (displayName?.isEmpty == false) ? displayName! : "Rider",
            "rider_photo_url": photoURL ?? ""
        ]

        req.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw NSError(domain: "LumoAPI.createRide", code: 1, userInfo: [
                "status": (resp as? HTTPURLResponse)?.statusCode ?? -1,
                "body": String(data: data, encoding: .utf8) ?? ""
            ])
        }

        let inserted = try JSONDecoder().decode([RideDTO].self, from: data)
        guard let first = inserted.first else { throw NSError(domain: "LumoAPI.createRide", code: 2) }
        return first
    }

    // MARK: - Driver: fetch requested rides (driver_id IS NULL)

    func fetchPlacedRides(limit: Int = 1) async throws -> [RideDTO] {
        let req = try makeRequest(
            path: "rides",
            queryItems: [
                URLQueryItem(name: "status", value: "eq.requested"),
                URLQueryItem(name: "driver_id", value: "is.null"),
                URLQueryItem(name: "order", value: "created_at.desc"),
                URLQueryItem(name: "limit", value: "\(max(1, limit))")
            ]
        )

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw NSError(domain: "LumoAPI.fetchPlacedRides", code: 1, userInfo: [
                "status": (resp as? HTTPURLResponse)?.statusCode ?? -1,
                "body": String(data: data, encoding: .utf8) ?? ""
            ])
        }

        return try JSONDecoder().decode([RideDTO].self, from: data)
    }

    // MARK: - Driver: accept ride (status -> accepted)

    func acceptRide(rideId: String, driverId: String) async throws {
        var req = try makeRequest(
            path: "rides",
            method: "PATCH",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(rideId)")]
        )

        req.setValue("return=minimal", forHTTPHeaderField: "Prefer")

        let payload: [String: Any] = [
            "status": "accepted",
            "driver_id": driverId
        ]

        req.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw NSError(domain: "LumoAPI.acceptRide", code: 1, userInfo: [
                "status": (resp as? HTTPURLResponse)?.statusCode ?? -1,
                "body": String(data: data, encoding: .utf8) ?? ""
            ])
        }
    }
}
