import SwiftUI
import GoogleMaps
import CoreLocation
import MapKit
import UIKit

// MARK: - Route Map (pickup → destination) using Google Maps

struct RouteMapView: UIViewRepresentable {
    let pickupCoordinate: CLLocationCoordinate2D
    let destinationCoordinate: CLLocationCoordinate2D
    let routeCoordinates: [CLLocationCoordinate2D]?

    // Coordinator holds state that must live longer than a single update
    class Coordinator {
        var carMarker: GMSMarker?
        var animationTimer: Timer?
        var route: [CLLocationCoordinate2D] = []
        var currentIndex: Int = 0

        func stopAnimation() {
            animationTimer?.invalidate()
            animationTimer = nil
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> GMSMapView {
        let camera = GMSCameraPosition(
            latitude: pickupCoordinate.latitude,
            longitude: pickupCoordinate.longitude,
            zoom: 13
        )
        let mapView = GMSMapView(frame: .zero, camera: camera)
        mapView.isUserInteractionEnabled = false
        mapView.isMyLocationEnabled = false
        mapView.settings.myLocationButton = false
        mapView.settings.compassButton = false

        // Lumo style
        mapView.applyLumoStyle()

        // Create the driver marker but don't position it yet
        let car = GMSMarker()
        car.icon = UIImage(systemName: "car.fill")?
            .withTintColor(.white, renderingMode: .alwaysOriginal)
        car.map = mapView
        context.coordinator.carMarker = car

        return mapView
    }

    func updateUIView(_ mapView: GMSMapView, context: Context) {
        mapView.clear()

        // keep style
        mapView.applyLumoStyle()

        // Custom black pin with white center
        let pinImage = makePinImage()

        let pickupMarker = GMSMarker(position: pickupCoordinate)
        pickupMarker.icon = pinImage
        pickupMarker.map = mapView

        let destMarker = GMSMarker(position: destinationCoordinate)
        destMarker.icon = pinImage
        destMarker.map = mapView

        // Draw full route polyline if we have it
        if let coords = routeCoordinates, coords.count > 1 {
            let path = GMSMutablePath()
            coords.forEach { path.add($0) }

            let polyline = GMSPolyline(path: path)
            polyline.strokeWidth = 4
            polyline.strokeColor = .white
            polyline.map = mapView

            // Update coordinator route + start / restart animation
            context.coordinator.route = coords
            startDriverAnimation(on: mapView, coordinator: context.coordinator)
        } else {
            // No route yet → stop animation and just keep the car at pickup
            context.coordinator.stopAnimation()
            context.coordinator.carMarker?.position = pickupCoordinate
            context.coordinator.carMarker?.map = mapView
        }

        // Fit camera to show both pins (regardless of route)
        var bounds = GMSCoordinateBounds()
        bounds = bounds.includingCoordinate(pickupCoordinate)
        bounds = bounds.includingCoordinate(destinationCoordinate)
        let update = GMSCameraUpdate.fit(bounds, withPadding: 40)
        mapView.moveCamera(update)
    }

    // MARK: - Start / maintain driver animation

    private func startDriverAnimation(on mapView: GMSMapView, coordinator: Coordinator) {
        guard coordinator.route.count > 1 else { return }

        // Restart from the beginning each time we get a new route
        coordinator.stopAnimation()
        coordinator.currentIndex = 0

        // Ensure marker exists and is on the map
        if coordinator.carMarker == nil {
            let car = GMSMarker()
            car.icon = UIImage(systemName: "car.fill")?
                .withTintColor(.white, renderingMode: .alwaysOriginal)
            car.map = mapView
            coordinator.carMarker = car
        }
        coordinator.carMarker?.position = coordinator.route.first!
        coordinator.carMarker?.map = mapView

        // Animate along the route forever (loops)
        coordinator.animationTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak coordinator, weak mapView] _ in
            guard
                let coord = coordinator,
                let map = mapView,
                !coord.route.isEmpty
            else { return }

            coord.currentIndex += 1
            if coord.currentIndex >= coord.route.count {
                // Loop back to start so the motion never "dies"
                coord.currentIndex = 0
            }

            let newPosition = coord.route[coord.currentIndex]

            DispatchQueue.main.async {
                if let car = coord.carMarker {
                    car.position = newPosition
                    car.map = map
                }
            }
        }

        if let timer = coordinator.animationTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    // MARK: - Custom pin image (black circle, white dot)

    private func makePinImage() -> UIImage {
        let pinSize: CGFloat = 28
        let dotSize: CGFloat = 10

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: pinSize, height: pinSize))
        return renderer.image { ctx in
            let rect = CGRect(x: 0, y: 0, width: pinSize, height: pinSize)

            // Outer black circle
            ctx.cgContext.setFillColor(UIColor.black.cgColor)
            ctx.cgContext.fillEllipse(in: rect)

            // Inner white dot
            let dotRect = CGRect(
                x: (pinSize - dotSize) / 2,
                y: (pinSize - dotSize) / 2,
                width: dotSize,
                height: dotSize
            )
            ctx.cgContext.setFillColor(UIColor.white.cgColor)
            ctx.cgContext.fillEllipse(in: dotRect)
        }
    }
}

// MARK: - Model for ride options

struct RideOption: Identifiable {
    let id = UUID()
    let name: String
    let subtitle: String
    let eta: String
    let price: String
    let crossedOutPrice: String?
    let isRecommended: Bool
}

// MARK: - Main View

struct RideOptionsView: View {
    let pickupAddress: String
    let destinationAddress: String
    let pickupCoordinate: CLLocationCoordinate2D

    @Environment(\.dismiss) private var dismiss   // 🔹 for back arrow

    @State private var destinationCoordinate: CLLocationCoordinate2D?
    @State private var routeCoordinates: [CLLocationCoordinate2D]? = nil

    @State private var selectedOptionID: UUID?
    @State private var showConfirmPickup = false

    private let geocoder = CLGeocoder()

    // fallback dest coord until geocoding + routing finishes
    private var destinationCoordinateForMap: CLLocationCoordinate2D {
        destinationCoordinate ?? CLLocationCoordinate2D(
            latitude: pickupCoordinate.latitude + 0.02,
            longitude: pickupCoordinate.longitude + 0.02
        )
    }

    private let options: [RideOption] = [
        RideOption(
            name: "Saver",
            subtitle: "More affordable, shared route",
            eta: "6:15 PM · 8–17 min",
            price: "$16.49",
            crossedOutPrice: "$21.90",
            isRecommended: true
        ),
        RideOption(
            name: "LumoX",
            subtitle: "Standard ride for up to 4",
            eta: "6:03 PM · 7 min",
            price: "$19.96",
            crossedOutPrice: nil,
            isRecommended: false
        ),
        RideOption(
            name: "LumoXL",
            subtitle: "Larger car, up to 6",
            eta: "6:05 PM · 8 min",
            price: "$24.98",
            crossedOutPrice: nil,
            isRecommended: false
        )
    ]

    private var selectedOption: RideOption? {
        options.first { $0.id == selectedOptionID } ?? options.first
    }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            // 🔽 main content slightly lowered
            VStack(spacing: 0) {

                // MAP (top) - Google Maps route + animated car
                RouteMapView(
                    pickupCoordinate: pickupCoordinate,
                    destinationCoordinate: destinationCoordinateForMap,
                    routeCoordinates: routeCoordinates
                )
                .frame(height: 260)
                .ignoresSafeArea(edges: .top)

                // BOTTOM SHEET
                VStack(spacing: 12) {

                    Capsule()
                        .fill(Color.white.opacity(0.25))
                        .frame(width: 40, height: 4)
                        .padding(.top, 8)

                    Text("Choose a ride")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.bottom, 4)

                    // Addresses
                    VStack(alignment: .leading, spacing: 4) {
                        Text(pickupAddress)
                            .font(.system(size: 13))
                            .foregroundColor(.gray.opacity(0.8))

                        Text(destinationAddress)
                            .font(.system(size: 13))
                            .foregroundColor(.gray.opacity(0.8))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)

                    // Ride options list
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(options) { option in
                                RideOptionRow(
                                    option: option,
                                    isSelected: option.id == selectedOptionID ||
                                        (selectedOptionID == nil && option.id == options.first?.id)
                                )
                                .onTapGesture {
                                    selectedOptionID = option.id
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    // Apple Pay row
                    HStack {
                        Text("Apple Pay")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )

                    // Choose button
                    Button {
                        showConfirmPickup = true
                    } label: {
                        Text("Choose \(selectedOption?.name ?? "ride")")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.white)
                            .foregroundColor(.black)
                            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .offset(y: -6)
                .ignoresSafeArea(edges: .bottom)
            }
            .padding(.top, 12)   // 👈 lower everything just a bit

            // 🔹 Top-left back arrow overlay
            VStack {
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Circle())
                    }
                    Spacer()
                }
                .padding(.top, 16)
                .padding(.leading, 16)

                Spacer()
            }
        }
        .onAppear {
            if destinationCoordinate == nil {
                geocodeAndRoute()
            } else {
                calculateRouteIfPossible()
            }
        }
        .fullScreenCover(isPresented: $showConfirmPickup) {
            ConfirmPickupView(
                pickupAddress: pickupAddress,
                pickupCoordinate: pickupCoordinate
            )
        }
        .navigationBarBackButtonHidden(true)   // hide system back button
    }

    // MARK: - Geocoding + routing

    private func geocodeAndRoute() {
        geocoder.geocodeAddressString(destinationAddress) { placemarks, _ in
            guard let location = placemarks?.first?.location else { return }
            DispatchQueue.main.async {
                destinationCoordinate = location.coordinate
                calculateRouteIfPossible()
            }
        }
    }

    private func calculateRouteIfPossible() {
        guard let dest = destinationCoordinate else { return }
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: pickupCoordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: dest))
        request.transportType = .automobile

        let directions = MKDirections(request: request)
        directions.calculate { response, _ in
            guard let polyline = response?.routes.first?.polyline else { return }

            var coords = [CLLocationCoordinate2D](
                repeating: kCLLocationCoordinate2DInvalid,
                count: polyline.pointCount
            )
            polyline.getCoordinates(&coords, range: NSRange(location: 0, length: polyline.pointCount))

            DispatchQueue.main.async {
                routeCoordinates = coords
            }
        }
    }
}

// MARK: - Single ride row

struct RideOptionRow: View {
    let option: RideOption
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.08))
                .frame(width: 56, height: 40)
                .overlay(
                    Image(systemName: "car.fill")
                        .foregroundColor(.white)
                )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(option.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)

                    if option.isRecommended {
                        Text("Faster")
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.9))
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                    }
                }

                Text(option.eta)
                    .font(.system(size: 13))
                    .foregroundColor(.gray.opacity(0.8))

                if !option.subtitle.isEmpty {
                    Text(option.subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(.gray.opacity(0.8))
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(option.price)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)

                if let crossed = option.crossedOutPrice {
                    Text(crossed)
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                        .strikethrough()
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isSelected ? Color.white : Color.white.opacity(0.15),
                        lineWidth: isSelected ? 2 : 1)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(isSelected ? Color.white.opacity(0.08) : Color.white.opacity(0.04))
                )
        )
    }
}
