import SwiftUI
import CoreLocation
import Combine
import GoogleMaps

// MARK: - Simple location manager to get the user's current location
class SimpleLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var userLocation: CLLocationCoordinate2D?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = kCLDistanceFilterNone
        manager.pausesLocationUpdatesAutomatically = false
        manager.activityType = .automotiveNavigation
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        userLocation = locations.last?.coordinate
        manager.startUpdatingLocation()
    }
}

// MARK: - MAIN VIEW

struct DriverTrackingView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var locationManager = SimpleLocationManager()

    @State private var driverCoordinate: CLLocationCoordinate2D?
    @State private var routeCoordinates: [CLLocationCoordinate2D] = []

    var body: some View {
        NavigationStack {
            ZStack {
                TrackingGoogleMapView(
                    userCoordinate: locationManager.userLocation,
                    driverCoordinate: driverCoordinate,
                    routeCoordinates: routeCoordinates
                )
                .ignoresSafeArea()

                VStack {
                    HStack {
                        Button { dismiss() } label: {
                            Image(systemName: "chevron.down")
                                .foregroundColor(.white)
                                .padding(10)
                                .background(Color.black.opacity(0.55))
                                .clipShape(Circle())
                        }

                        Spacer()

                        Text("Tracking driver")
                            .foregroundColor(.white)
                            .font(.system(size: 16, weight: .semibold))

                        NavigationLink(destination: MessageDriverView()) {
                            Text("Message driver")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.black)
                                .padding(.vertical, 6)
                                .padding(.horizontal, 12)
                                .background(Color.white)
                                .clipShape(Capsule())
                        }

                        Color.clear.frame(width: 36, height: 1)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 14)

                    Spacer()

                    VStack(alignment: .leading, spacing: 14) {
                        Text("Your driver is on the way")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)

                        Text(etaText)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))

                        VStack(spacing: 10) {
                            infoPill(icon: "clock", title: "Estimated arrival", value: etaText)
                            infoPill(icon: "map", title: "Distance to pickup", value: distanceText)
                        }
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
            .onReceive(locationManager.$userLocation.compactMap { $0 }) { location in
                // Create a fake driver position once (for now)
                if driverCoordinate == nil {
                    driverCoordinate = CLLocationCoordinate2D(
                        latitude: location.latitude + 0.01,
                        longitude: location.longitude + 0.01
                    )
                }

                // When we have both points, fetch the road-following route
                if let driver = driverCoordinate {
                    DirectionsService.shared.fetchRoute(from: driver, to: location) { coords in
                        DispatchQueue.main.async {
                            self.routeCoordinates = coords ?? []
                        }
                    }
                }
            }
        }
    }

    private var distanceText: String {
        guard let user = locationManager.userLocation,
              let driver = driverCoordinate else { return "Calculating…" }

        let userLoc = CLLocation(latitude: user.latitude, longitude: user.longitude)
        let driverLoc = CLLocation(latitude: driver.latitude, longitude: driver.longitude)
        let meters = userLoc.distance(from: driverLoc)
        let miles = meters / 1609.34
        return String(format: "%.1f mi away", miles)
    }

    private var etaText: String {
        guard let user = locationManager.userLocation,
              let driver = driverCoordinate else { return "— min away" }

        let userLoc = CLLocation(latitude: user.latitude, longitude: user.longitude)
        let driverLoc = CLLocation(latitude: driver.latitude, longitude: driver.longitude)
        let meters = userLoc.distance(from: driverLoc)
        let miles = meters / 1609.34
        let minutes = max(2, Int(round((miles / 25.0) * 60.0)))
        return "\(minutes) min away"
    }

    private func infoPill(icon: String, title: String, value: String) -> some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: icon)
                Text(title)
            }
            .foregroundColor(.white.opacity(0.8))

            Spacer()

            Text(value)
                .foregroundColor(.white)
                .fontWeight(.semibold)
        }
        .font(.footnote)
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(Color.white.opacity(0.08))
        .clipShape(Capsule())
    }
}

// MARK: - MAP VIEW

struct TrackingGoogleMapView: UIViewRepresentable {
    var userCoordinate: CLLocationCoordinate2D?
    var driverCoordinate: CLLocationCoordinate2D?
    var routeCoordinates: [CLLocationCoordinate2D]

    func makeUIView(context: Context) -> GMSMapView {
        let camera = GMSCameraPosition(latitude: 37.7749, longitude: -122.4194, zoom: 13)
        let mapView = GMSMapView(frame: .zero, camera: camera)
        mapView.isMyLocationEnabled = false

        // Lumo style
        mapView.applyLumoStyle()

        return mapView
    }

    func updateUIView(_ mapView: GMSMapView, context: Context) {
        mapView.clear()
        mapView.applyLumoStyle()

        var bounds: GMSCoordinateBounds?

        // User marker (pickup)
        if let user = userCoordinate {
            let marker = GMSMarker(position: user)

            let pinSize: CGFloat = 20
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: pinSize, height: pinSize))
            let pinImage = renderer.image { ctx in
                let rect = CGRect(x: 0, y: 0, width: pinSize, height: pinSize)
                ctx.cgContext.setFillColor(UIColor.black.cgColor)
                ctx.cgContext.fillEllipse(in: rect)

                let dotRect = rect.insetBy(dx: pinSize * 0.35, dy: pinSize * 0.35)
                ctx.cgContext.setFillColor(UIColor.white.cgColor)
                ctx.cgContext.fillEllipse(in: dotRect)
            }
            marker.icon = pinImage
            marker.map = mapView

            bounds = bounds?.includingCoordinate(user)
                ?? GMSCoordinateBounds(coordinate: user, coordinate: user)
        }

        // Driver marker (WHITE CAR)
        if let driver = driverCoordinate {
            let marker = GMSMarker(position: driver)
            if let img = UIImage(systemName: "car.fill")?.withRenderingMode(.alwaysTemplate) {
                let imageView = UIImageView(image: img)
                imageView.tintColor = .white
                marker.iconView = imageView
            }
            marker.map = mapView

            bounds = bounds?.includingCoordinate(driver)
                ?? GMSCoordinateBounds(coordinate: driver, coordinate: driver)
        }

        // Route polyline that follows the road (white)
        if !routeCoordinates.isEmpty {
            let path = GMSMutablePath()
            for coord in routeCoordinates {
                path.add(coord)
            }

            let polyline = GMSPolyline(path: path)
            polyline.strokeColor = .white
            polyline.strokeWidth = 4.0
            polyline.map = mapView

            // Include all route points in bounds
            for coord in routeCoordinates {
                bounds = bounds?.includingCoordinate(coord)
                    ?? GMSCoordinateBounds(coordinate: coord, coordinate: coord)
            }
        }

        if let b = bounds {
            let update = GMSCameraUpdate.fit(b, withPadding: 80)
            mapView.animate(with: update)
        }
    }
}

// MARK: - Directions Service (Google Directions API)

final class DirectionsService {
    static let shared = DirectionsService()

    // Make sure this key has Directions API enabled in Google Cloud.
    private let apiKey = "AIzaSyBGGtwh_qslNfTnr7jVJD4iYNNPHMbRYXY"

    struct DirectionsResponse: Decodable {
        struct Route: Decodable {
            struct OverviewPolyline: Decodable {
                let points: String
            }
            let overview_polyline: OverviewPolyline
        }
        let routes: [Route]
    }

    func fetchRoute(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        completion: @escaping ([CLLocationCoordinate2D]?) -> Void
    ) {
        let originParam = "\(origin.latitude),\(origin.longitude)"
        let destParam = "\(destination.latitude),\(destination.longitude)"

        guard let url = URL(string:
            "https://maps.googleapis.com/maps/api/directions/json?origin=\(originParam)&destination=\(destParam)&mode=driving&key=\(apiKey)"
        ) else {
            completion(nil)
            return
        }

        URLSession.shared.dataTask(with: url) { data, _, error in
            guard error == nil,
                  let data = data,
                  let response = try? JSONDecoder().decode(DirectionsResponse.self, from: data),
                  let firstRoute = response.routes.first else {
                completion(nil)
                return
            }

            let encoded = firstRoute.overview_polyline.points
            let decoded = Self.decodePolyline(encodedPolyline: encoded)
            completion(decoded)
        }.resume()
    }

    // MARK: - Polyline decoding (Google encoded polyline algorithm)
    private static func decodePolyline(encodedPolyline: String) -> [CLLocationCoordinate2D] {
        let data = encodedPolyline.data(using: .utf8)!
        let length = data.count
        var index = 0

        var latitude: Int32 = 0
        var longitude: Int32 = 0
        var coordinates: [CLLocationCoordinate2D] = []

        while index < length {
            var byte = 0
            var result: Int32 = 0
            var shift: Int32 = 0

            repeat {
                byte = Int((data as NSData).bytes.load(fromByteOffset: index, as: UInt8.self)) - 63
                index += 1
                result |= Int32(byte & 0x1F) << shift
                shift += 5
            } while byte >= 0x20

            let deltaLat = ((result & 1) != 0) ? ~(result >> 1) : (result >> 1)
            latitude += deltaLat

            shift = 0
            result = 0

            repeat {
                byte = Int((data as NSData).bytes.load(fromByteOffset: index, as: UInt8.self)) - 63
                index += 1
                result |= Int32(byte & 0x1F) << shift
                shift += 5
            } while byte >= 0x20

            let deltaLon = ((result & 1) != 0) ? ~(result >> 1) : (result >> 1)
            longitude += deltaLon

            let lat = Double(latitude) / 1e5
            let lon = Double(longitude) / 1e5
            coordinates.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }

        return coordinates
    }
}

// MARK: - Helper model for chat messages
struct ChatMessage: Identifiable {
    let id = UUID()
    let text: String
    let isFromUser: Bool
}

// MARK: - MESSAGE DRIVER VIEW

struct MessageDriverView: View {
    @State private var messageText: String = ""
    @State private var messages: [ChatMessage] = []

    var body: some View {
        ZStack {
            // Full black background to match Lumo theme
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {

                // Top header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your driver")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)

                    Text("You can send a message while they’re on the way")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.6))
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 12)

                // Messages list
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(messages) { msg in
                            HStack {
                                if msg.isFromUser {
                                    Spacer()
                                    Text(msg.text)
                                        .padding(10)
                                        .background(Color.white)
                                        .foregroundColor(.black)
                                        .clipShape(RoundedRectangle(cornerRadius: 16))
                                } else {
                                    Text(msg.text)
                                        .padding(10)
                                        .background(Color.white.opacity(0.1))
                                        .foregroundColor(.white)
                                        .clipShape(RoundedRectangle(cornerRadius: 16))
                                    Spacer()
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }

                Divider()
                    .background(Color.white.opacity(0.2))

                // Input bar
                HStack(spacing: 10) {
                    ZStack(alignment: .leading) {
                        if messageText.isEmpty {
                            Text("Type a message…")
                                .foregroundColor(.white.opacity(0.6))
                                .padding(.leading, 16)
                        }
                        TextField("", text: $messageText)
                            .foregroundColor(.white)
                            .padding(12)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .disableAutocorrection(true)
                    }

                    Button {
                        let trimmed = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }

                        // Append user's message to the chat
                        messages.append(ChatMessage(text: trimmed, isFromUser: true))
                        messageText = ""
                    } label: {
                        Text("Send")
                            .font(.system(size: 15, weight: .semibold))
                            .padding(.vertical, 10)
                            .padding(.horizontal, 14)
                            .background(Color.white)
                            .foregroundColor(.black)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
            }
        }
        .navigationTitle("Message Driver")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
    }
}

