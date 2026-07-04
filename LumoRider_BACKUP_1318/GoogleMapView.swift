import SwiftUI
import GoogleMaps
import CoreLocation

/// Simple reusable Google Maps view used on the Home screen
/// and in the full-screen map.
struct GoogleMapView: UIViewRepresentable {
    var centerCoordinate: CLLocationCoordinate2D

    func makeUIView(context: Context) -> GMSMapView {
        let camera = GMSCameraPosition(
            latitude: centerCoordinate.latitude,
            longitude: centerCoordinate.longitude,
            zoom: 13
        )

        let mapView = GMSMapView(frame: .zero, camera: camera)
        mapView.isMyLocationEnabled = false
        mapView.settings.myLocationButton = false
        mapView.settings.rotateGestures = false
        mapView.settings.tiltGestures = false

        // If you have a custom Lumo style extension, apply it here
        mapView.applyLumoStyle()

        return mapView
    }

    func updateUIView(_ mapView: GMSMapView, context: Context) {
        let camera = GMSCameraPosition(
            latitude: centerCoordinate.latitude,
            longitude: centerCoordinate.longitude,
            zoom: 13
        )
        mapView.animate(to: camera)
    }
}
