import SwiftUI
import UIKit
import GoogleMaps
import CoreLocation

struct GoogleMapView: UIViewRepresentable {
    var centerCoordinate: CLLocationCoordinate2D
    var rideId: String?

    // Use your real Supabase config (full anon key)
    private let supabaseURL = URL(string: "https://rpryqbdodbieioebedjg.supabase.co")!
    private let supabaseAnonKey =
    (Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String)
    ?? "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJwcnlxYmRvZGJpZWlvZWJlZGpnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjUwNjE0MjYsImV4cCI6MjA4MDYzNzQyNn0.8ZTaA1bCyRUKb6U4NNZou6DMfXP3yyE1NeNL8Ljt9as"

    private static let locationManager: CLLocationManager = {
        let lm = CLLocationManager()
        return lm
    }()

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> GMSMapView {
        let camera = GMSCameraPosition(
            latitude: centerCoordinate.latitude,
            longitude: centerCoordinate.longitude,
            zoom: 13
        )

        let mapView = GMSMapView()
        mapView.camera = camera
        GoogleMapView.locationManager.requestWhenInUseAuthorization()
        mapView.isMyLocationEnabled = true
        mapView.settings.myLocationButton = false
        mapView.settings.rotateGestures = false
        mapView.settings.tiltGestures = false
        mapView.applyLumoStyle()

        context.coordinator.mapView = mapView

        if let rideId = rideId {
            context.coordinator.startTracking(
                rideId: rideId,
                supabaseURL: supabaseURL,
                supabaseAnonKey: supabaseAnonKey
            )
        }

        return mapView
    }

    func updateUIView(_ mapView: GMSMapView, context: Context) {}

    final class Coordinator {
        weak var mapView: GMSMapView?
        private var marker: GMSMarker?
        private var pollingTimer: Timer?

        func startTracking(rideId: String, supabaseURL: URL, supabaseAnonKey: String) {
            fetchLatest(rideId: rideId, supabaseURL: supabaseURL, supabaseAnonKey: supabaseAnonKey)

            DispatchQueue.main.async {
                self.pollingTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
                    self?.fetchLatest(rideId: rideId, supabaseURL: supabaseURL, supabaseAnonKey: supabaseAnonKey)
                }
            }
        }

        func stopTracking() {
            pollingTimer?.invalidate()
            pollingTimer = nil
        }

        deinit {
            stopTracking()
        }

        private func fetchLatest(rideId: String, supabaseURL: URL, supabaseAnonKey: String) {
            // Pull driver coords from rides row
            // /rest/v1/rides?select=driver_lat,driver_lng,driver_heading&id=eq.<rideId>&limit=1
            var components = URLComponents(url: supabaseURL.appendingPathComponent("/rest/v1/rides"), resolvingAgainstBaseURL: false)
            components?.queryItems = [
                URLQueryItem(name: "select", value: "driver_lat,driver_lng,driver_heading"),
                URLQueryItem(name: "id", value: "eq.\(rideId)"),
                URLQueryItem(name: "limit", value: "1")
            ]

            guard let url = components?.url else { return }

            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            req.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
            req.setValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Accept")

            URLSession.shared.dataTask(with: req) { [weak self] data, _, error in
                guard let self else { return }
                if let error = error {
                    print("[GoogleMapView] polling error: \(error.localizedDescription)")
                    return
                }
                guard let data else { return }

                do {
                    if let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                       let row = arr.first {

                        let lat = Self.parseDouble(row["driver_lat"])
                        let lng = Self.parseDouble(row["driver_lng"])
                        let heading = Self.parseDouble(row["driver_heading"]) ?? 0.0
                        guard let lat, let lng else { return }

                        let position = CLLocationCoordinate2D(latitude: lat, longitude: lng)

                        DispatchQueue.main.async {
                            guard let mapView = self.mapView else { return }

                            if let marker = self.marker {
                                CATransaction.begin()
                                CATransaction.setAnimationDuration(1.0)
                                marker.position = position
                                marker.rotation = heading
                                CATransaction.commit()
                            } else {
                                let m = GMSMarker(position: position)
                                m.icon = UIImage(named: "driver_car")
                                m.groundAnchor = CGPoint(x: 0.5, y: 0.5)
                                m.rotation = heading
                                m.map = mapView
                                self.marker = m
                            }
                        }
                    }
                } catch {
                    print("[GoogleMapView] JSON parse error: \(error)")
                }
            }.resume()
        }

        private static func parseDouble(_ value: Any?) -> Double? {
            if value == nil { return nil }
            if let d = value as? Double { return d }
            if let i = value as? Int { return Double(i) }
            if let s = value as? String, let d = Double(s) { return d }
            return nil
        }
    }
}
