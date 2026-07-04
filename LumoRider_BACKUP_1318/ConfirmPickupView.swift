import SwiftUI
import CoreLocation
import GoogleMaps

// MARK: - Main Confirm Pickup View

struct ConfirmPickupView: View {
    let pickupAddress: String
    let pickupCoordinate: CLLocationCoordinate2D

    // Map center (moves as user pans)
    @State private var centerCoordinate: CLLocationCoordinate2D

    // Controls showing the payment screen
    @State private var showAddPayment: Bool = false

    // Simple “recommended spots” list
    struct Spot: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String
    }

    private let spots: [Spot] = [
        Spot(title: "Spot 1", subtitle: "Near pickup"),
        Spot(title: "Spot 2", subtitle: "Across the street"),
        Spot(title: "Spot 3", subtitle: "Around the corner")
    ]

    // Live-updating address text
    @State private var currentAddress: String

    // Geocoder
    private let geocoder = CLGeocoder()

    // Init so we can seed the state from incoming pickup
    init(pickupAddress: String, pickupCoordinate: CLLocationCoordinate2D) {
        self.pickupAddress = pickupAddress
        self.pickupCoordinate = pickupCoordinate

        _centerCoordinate = State(initialValue: pickupCoordinate)
        _currentAddress = State(initialValue: pickupAddress)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // MAP + Center pin
                ZStack {
                    ConfirmPickupMapView(centerCoordinate: $centerCoordinate)
                        .frame(height: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .padding(.horizontal, 16)
                        .padding(.top, 12)

                    // Center pin overlay (Uber-style)
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.red)
                        .shadow(radius: 4)
                        .offset(y: 4)
                }

                VStack(alignment: .leading, spacing: 16) {
                    Text("Confirm the pickup spot")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.top, 24)

                    // 🔴 Live address here
                    Text(currentAddress)
                        .font(.system(size: 17))
                        .foregroundColor(.white.opacity(0.9))

                    Text("3 recommended nearby")
                        .font(.system(size: 14))
                        .foregroundColor(.gray.opacity(0.8))

                    // Recommended spots (tap just updates the address line)
                    VStack(spacing: 10) {
                        ForEach(spots) { spot in
                            Button {
                                currentAddress = spot.title
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(spot.title)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(.white)

                                    Text(spot.subtitle)
                                        .font(.system(size: 13))
                                        .foregroundColor(.white.opacity(0.7))
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(Color.white.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                                )
                            }
                        }
                    }

                    Spacer()

                    // ✅ Confirm button → payment screen
                    Button {
                        showAddPayment = true
                    } label: {
                        Text("Confirm pickup")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.white)
                            .foregroundColor(.black)
                            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    }
                    .padding(.bottom, 24)
                }
                .padding(.horizontal, 20)
            }
        }
        // First geocode when screen appears
        .onAppear {
            reverseGeocodeCenterIfNeeded()
        }
        // 🔁 Re-geocode whenever the map center moves
        .onChange(of: centerCoordinate.latitude) { _ in
            reverseGeocodeCenterIfNeeded()
        }
        .onChange(of: centerCoordinate.longitude) { _ in
            reverseGeocodeCenterIfNeeded()
        }
        // Payment sheet (unchanged)
        .fullScreenCover(isPresented: $showAddPayment) {
            AddPaymentView()
        }
    }

    // MARK: - Reverse geocoding for centerCoordinate

    private func reverseGeocodeCenterIfNeeded() {
        let location = CLLocation(
            latitude: centerCoordinate.latitude,
            longitude: centerCoordinate.longitude
        )

        // Optional: cancel previous request so we don't spam
        if geocoder.isGeocoding {
            geocoder.cancelGeocode()
        }

        geocoder.reverseGeocodeLocation(location) { placemarks, error in
            guard error == nil, let place = placemarks?.first else { return }

            var parts: [String] = []
            if let name = place.name { parts.append(name) }
            if let locality = place.locality { parts.append(locality) }
            if let admin = place.administrativeArea { parts.append(admin) }

            let joined = parts.joined(separator: ", ")

            DispatchQueue.main.async {
                if !joined.isEmpty {
                    self.currentAddress = joined
                }
            }
        }
    }
}

// MARK: - Google Maps View for Confirm Pickup

struct ConfirmPickupMapView: UIViewRepresentable {
    @Binding var centerCoordinate: CLLocationCoordinate2D

    func makeUIView(context: Context) -> GMSMapView {
        let camera = GMSCameraPosition(
            latitude: centerCoordinate.latitude,
            longitude: centerCoordinate.longitude,
            zoom: 16
        )

        let mapView = GMSMapView(frame: .zero, camera: camera)
        mapView.isMyLocationEnabled = false
        mapView.settings.myLocationButton = false
        mapView.settings.compassButton = false

        mapView.delegate = context.coordinator

        // Apply your custom dark style
        mapView.applyLumoStyle()

        return mapView
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, GMSMapViewDelegate {
        var parent: ConfirmPickupMapView

        init(_ parent: ConfirmPickupMapView) {
            self.parent = parent
        }

        func mapView(_ mapView: GMSMapView, idleAt position: GMSCameraPosition) {
            parent.centerCoordinate = position.target
        }

        func mapView(_ mapView: GMSMapView, didChange position: GMSCameraPosition) {
            parent.centerCoordinate = position.target
        }
    }

    func updateUIView(_ mapView: GMSMapView, context: Context) {
        let camera = GMSCameraPosition(
            latitude: centerCoordinate.latitude,
            longitude: centerCoordinate.longitude,
            zoom: mapView.camera.zoom
        )
        mapView.animate(to: camera)

        // keep style applied in case Google resets it
        mapView.applyLumoStyle()
    }
}

