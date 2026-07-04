import Foundation
import GoogleMaps

extension GMSMapView {

    /// Apply the shared dark Lumo style to this Google map instance.
    func applyLumoStyle() {
        let json = """
        [
          {
            "featureType": "all",
            "elementType": "geometry",
            "stylers": [
              { "color": "#191C24" }
            ]
          },
          {
            "featureType": "all",
            "elementType": "labels.text.fill",
            "stylers": [
              { "color": "#E5E5E5" }
            ]
          },
          {
            "featureType": "all",
            "elementType": "labels.text.stroke",
            "stylers": [
              { "color": "#191C24" }
            ]
          },
          {
            "featureType": "poi",
            "elementType": "labels",
            "stylers": [
              { "visibility": "off" }
            ]
          },
          {
            "featureType": "road",
            "elementType": "geometry",
            "stylers": [
              { "color": "#2A2E37" }
            ]
          },
          {
            "featureType": "road",
            "elementType": "labels.text.fill",
            "stylers": [
              { "color": "#F0F0F0" }
            ]
          },
          {
            "featureType": "road",
            "elementType": "labels.text.stroke",
            "stylers": [
              { "color": "#191C24" }
            ]
          },
          {
            "featureType": "road.highway",
            "elementType": "geometry",
            "stylers": [
              { "color": "#3A3F49" }
            ]
          },
          {
            "featureType": "water",
            "elementType": "geometry",
            "stylers": [
              { "color": "#1E222C" }
            ]
          }
        ]
        """

        do {
            let style = try GMSMapStyle(jsonString: json)
            self.mapStyle = style
            print("✅ Applied global Lumo map style")
        } catch {
            print("❌ Failed to apply global Lumo style: \(error)")
        }

        self.isBuildingsEnabled = false
        self.isTrafficEnabled = false
    }
}
