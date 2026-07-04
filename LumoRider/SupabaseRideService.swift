import Foundation
import Combine
#if canImport(FirebaseAuth)
import FirebaseAuth
#endif

final class SupabaseRideService: ObservableObject {
    static let shared = SupabaseRideService()

    private let baseURL = URL(string: "https://rpryqbdodbieioebedjg.supabase.co")!
    private let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJwcnlxYmRvZGJpZWlvZWJlZGpnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjUwNjE0MjYsImV4cCI6MjA4MDYzNzQyNn0.8ZTaA1bCyRUKb6U4NNZou6DMfXP3yyE1NeNL8Ljt9as"

    private init() {
        // Restore active ride across app launches (rider must always react to terminal status)
        if let saved = UserDefaults.standard.string(forKey: "lumo_active_ride_id"), !saved.isEmpty {
            currentRideId = saved
            fetchActiveRideStatus(rideId: saved)
        }
    }

    func createRideRequest(
        riderId: String,
        pickupLat: Double,
        pickupLng: Double,
        dropoffLat: Double,
        dropoffLng: Double,
        pickupAddress: String,
        dropoffAddress: String
    ) async throws -> String {

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
        req.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        req.setValue("return=representation", forHTTPHeaderField: "Prefer")

        let pickupAddressFinal = pickupAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let dropoffAddressFinal = dropoffAddress.trimmingCharacters(in: .whitespacesAndNewlines)

        #if canImport(FirebaseAuth)
        let displayName = Auth.auth().currentUser?.displayName
        let photoURL = Auth.auth().currentUser?.photoURL?.absoluteString
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
            "rider_id": riderId,
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
            let url = URL(string: "\(baseURL)/rest/v1/rides?id=eq.\(rideId)")!
            var req = URLRequest(url: url)
            req.httpMethod = "PATCH"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.setValue(anonKey, forHTTPHeaderField: "apikey")
            req.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
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

    @Published var activeRideStatus: String? = nil
    private var statusTimer: Timer?
    private var currentRideId: String?

    func beginObservingRideStatus(rideId: String) {
        UserDefaults.standard.set(rideId, forKey: "lumo_active_ride_id")
        fetchActiveRideStatus(rideId: rideId)
    }

    func fetchActiveRideStatus(rideId: String) {
        currentRideId = rideId
        statusTimer?.invalidate()

        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }

            // Immediate fetch (don’t wait for first timer tick)
            do {
                let url = URL(string: "\(self.baseURL)/rest/v1/rides?id=eq.\(rideId)&select=status")!
                var req = URLRequest(url: url)
                req.httpMethod = "GET"
                req.setValue("Bearer \(self.anonKey)", forHTTPHeaderField: "Authorization")
                req.setValue(self.anonKey, forHTTPHeaderField: "apikey")

                URLSession.shared.dataTask(with: req) { data, _, _ in
                    guard
                        let data = data,
                        let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                        let status = json.first?["status"] as? String
                    else { return }

                    DispatchQueue.main.async {
                        self.activeRideStatus = status
                        if status == "completed"
                            || status == "cancelled"
                            || status == "cancelled_by_driver"
                            || status == "cancelled_by_rider" {
                            self.statusTimer?.invalidate()
                            self.statusTimer = nil
                        }
                    }
                }.resume()
            }

            let url = URL(string: "\(self.baseURL)/rest/v1/rides?id=eq.\(rideId)&select=status")!

            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            req.setValue("Bearer \(self.anonKey)", forHTTPHeaderField: "Authorization")
            req.setValue(self.anonKey, forHTTPHeaderField: "apikey")

            URLSession.shared.dataTask(with: req) { data, _, _ in
                guard
                    let data = data,
                    let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                    let status = json.first?["status"] as? String
                else { return }

                DispatchQueue.main.async {
                    self.activeRideStatus = status

                    // STOP polling once trip is terminal (Uber / Lyft behavior)
                    if status == "completed"
                        || status == "cancelled"
                        || status == "cancelled_by_driver"
                        || status == "cancelled_by_rider" {
                        self.statusTimer?.invalidate()
                        self.statusTimer = nil
                    }
                }
            }.resume()
        }
    }

    func stopObservingRideStatus() {
        statusTimer?.invalidate()
        statusTimer = nil
        currentRideId = nil
        activeRideStatus = nil
        UserDefaults.standard.removeObject(forKey: "lumo_active_ride_id")
    }
}
