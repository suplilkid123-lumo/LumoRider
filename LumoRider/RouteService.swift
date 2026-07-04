import Foundation
import CoreLocation
import GoogleMaps

class RouteService {
    static func fetchRoute(from origin: CLLocationCoordinate2D,
                           to destination: CLLocationCoordinate2D,
                           completion: @escaping (GMSPath?) -> Void) {
        
        let apiKey = "YOUR_GOOGLE_MAPS_API_KEY" // <-- PUT YOUR API KEY HERE
        
        let urlString =
        "https://maps.googleapis.com/maps/api/directions/json" +
        "?origin=\(origin.latitude),\(origin.longitude)" +
        "&destination=\(destination.latitude),\(destination.longitude)" +
        "&mode=driving" +
        "&key=\(apiKey)"
        
        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, _, error in
            guard let data = data,
                  error == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let routes = json["routes"] as? [[String: Any]],
                  let route = routes.first,
                  let poly = route["overview_polyline"] as? [String: Any],
                  let points = poly["points"] as? String,
                  let path = GMSPath(fromEncodedPath: points)
            else {
                completion(nil)
                return
            }
            
            completion(path)
        }.resume()
    }
}
