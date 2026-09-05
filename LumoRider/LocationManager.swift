import Foundation
import CoreLocation
import Combine

final class LumoLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {

    private let manager = CLLocationManager()

    @Published var coordinate: CLLocationCoordinate2D?
    @Published var currentAddress: String = ""
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var locationPermissionDenied: Bool = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        authorizationStatus = manager.authorizationStatus
        requestLocationAccessIfNeeded()
    }

    func requestLocationAccessIfNeeded() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            locationPermissionDenied = false
            manager.startUpdatingLocation()
        case .denied, .restricted:
            locationPermissionDenied = true
            manager.stopUpdatingLocation()
        @unknown default:
            manager.stopUpdatingLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        DispatchQueue.main.async {
            self.authorizationStatus = status
            self.locationPermissionDenied = status == .denied || status == .restricted
        }

        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation()
        case .denied, .restricted:
            manager.stopUpdatingLocation()
        case .notDetermined:
            break
        @unknown default:
            manager.stopUpdatingLocation()
        }
    }

    func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let location = locations.last else { return }
        DispatchQueue.main.async {
            self.coordinate = location.coordinate
        }
    }

    func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        let nsError = error as NSError

        if nsError.domain == kCLErrorDomain,
           let code = CLError.Code(rawValue: nsError.code),
           code == .denied {
            DispatchQueue.main.async {
                self.locationPermissionDenied = true
                self.authorizationStatus = manager.authorizationStatus
            }
            manager.stopUpdatingLocation()
            print("📍 Location permission denied or restricted.")
            return
        }

        if nsError.domain == kCLErrorDomain,
           let code = CLError.Code(rawValue: nsError.code),
           code == .locationUnknown {
            // Transient GPS condition. Core Location will continue updating.
            return
        }

        print("📍 Location error:", error.localizedDescription)
    }
}
