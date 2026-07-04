import Foundation
import MapKit
import CoreLocation
import Combine

class LumoLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()

    @Published var region: MKCoordinateRegion?
    @Published var currentAddress: String = "Locating…"

    override init() {
        super.init()
        manager.delegate = self
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager,
                         didUpdateLocations locations: [CLLocation]) {

        guard let location = locations.last else { return }

        // Set map region
        let span = MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        self.region = MKCoordinateRegion(center: location.coordinate, span: span)

        // Reverse geocode → Pickup address
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            guard let self = self else { return }
            if let p = placemarks?.first {
                let street = [p.subThoroughfare, p.thoroughfare]
                    .compactMap { $0 }
                    .joined(separator: " ")

                let city = [p.locality, p.administrativeArea]
                    .compactMap { $0 }
                    .joined(separator: ", ")

                self.currentAddress = "\(street), \(city)"
            }
        }
    }
}

