import SwiftUI
import GoogleMaps
import CoreLocation
import MapKit
import UIKit
import Foundation

// MARK: - Iraq Fare Calculator (local fallback to fix scope issues)
struct IraqAutoFareCalculator {
    static func calculate(
        distanceMeters: Double,
        durationSeconds: Int
    ) -> Int {

        let baseFareIQD = 850        // 1000 * 0.85
        let perKmIQD = 383           // 450 * 0.85 ≈ 383
        let perMinuteIQD = 51        // 60 * 0.85 = 51
        let minimumFareIQD = 2500
        let roundingIQD = 250

        let km = distanceMeters / 1000.0
        let minutes = Double(durationSeconds) / 60.0

        let fare =
            Double(baseFareIQD) +
            (km * Double(perKmIQD)) +
            (minutes * Double(perMinuteIQD))

        let rounded =
            Int((fare / Double(roundingIQD)).rounded()) * roundingIQD

        return max(rounded, minimumFareIQD)
    }
}

// MARK: - US Fare Calculator
struct USAutoFareCalculator {
    static func calculate(
        distanceMeters: Double,
        durationSeconds: Int
    ) -> Double {

        let baseFareUSD = 3.00
        let perMileUSD = 1.25
        let perMinuteUSD = 0.35

        let miles = distanceMeters / 1609.34
        let minutes = Double(durationSeconds) / 60.0

        let fare =
            baseFareUSD +
            (miles * perMileUSD) +
            (minutes * perMinuteUSD)

        return (fare * 100).rounded() / 100
    }
}

// MARK: - Supabase Config (move to its own file later if you want)
enum SupabaseConfig {
    static let url = "https://rpryqbdodbieioebedjg.supabase.co"
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJwcnlxYmRvZGJpZWlvZWJlZGpnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjUwNjE0MjYsImV4cCI6MjA4MDYzNzQyNn0.8ZTaA1bCyRUKb6U4NNZou6DMfXP3yyE1NeNL8Ljt9as"
}

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
    let id: String
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

    // Freeze the exact strings the user selected so they never get overwritten by async work
    @State private var frozenPickupAddress: String = ""
    @State private var frozenDropoffAddress: String = ""

    @Environment(\.dismiss) private var dismiss   // 🔹 for back arrow

    @State private var destinationCoordinate: CLLocationCoordinate2D?
    @State private var routeCoordinates: [CLLocationCoordinate2D]? = nil

    @State private var routeDistanceMeters: Double = 0
    @State private var routeDurationSeconds: Int = 0
    @State private var calculatedFareIQD: Int = 0
    @State private var calculatedFareUSD: Double = 0
    @State private var isFareLocked: Bool = false

    @State private var selectedOptionID: String?

    // 🔹 Scheduled ride support (set by ScheduleRideView)
    @AppStorage("lumo_scheduled_for_epoch") private var scheduledForEpoch: Double = 0
    @State private var showPaymentForScheduled = false
    @State private var showConfirmPickup = false

    @State private var detectedCountryCode: String? = nil

    // 🔹 Silent price recovery (fix: sometimes fare stays blank)
    @State private var fareRecoveryTimer: Timer? = nil
    @State private var fareRecoveryAttempts: Int = 0
    private let maxFareRecoveryAttempts: Int = 20
    private let fareRecoveryInterval: TimeInterval = 0.8

    private let geocoder = CLGeocoder()

    private var pickupAddressFinal: String {
        pickupAddress.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var dropoffAddressFinal: String {
        destinationAddress.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var resolvedPickupAddress: String {
        let v = (frozenPickupAddress.isEmpty ? pickupAddressFinal : frozenPickupAddress)
        let trimmed = v.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Current location" : trimmed
    }

    private var resolvedDropoffAddress: String {
        let v = (frozenDropoffAddress.isEmpty ? dropoffAddressFinal : frozenDropoffAddress)
        let trimmed = v.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Destination" : trimmed
    }

    private var resolvedDestinationCoordinate: CLLocationCoordinate2D? {
        if let dest = destinationCoordinate, CLLocationCoordinate2DIsValid(dest) {
            return dest
        }
        if let route = routeCoordinates, route.count > 1 {
            let last = route.last!
            if CLLocationCoordinate2DIsValid(last) { return last }
        }
        return nil
    }

    private var addressesReady: Bool {
        // We always have a pickup coordinate, so don't block the flow if the human-readable address is still loading.
        return CLLocationCoordinate2DIsValid(pickupCoordinate)
    }

    private var isSamePickupAndDropoffAddress: Bool {
        let pickup = resolvedPickupAddress
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let dropoff = resolvedDropoffAddress
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        return !pickup.isEmpty && !dropoff.isEmpty && pickup == dropoff
    }

    private var isMinimumSamePlaceFareActive: Bool {
        detectedCountryCode == "US" && calculatedFareUSD == 0.50 && routeDistanceMeters == 0
    }

    private func lockSamePlaceMinimumFare() {
        destinationCoordinate = pickupCoordinate
        routeCoordinates = [pickupCoordinate, pickupCoordinate]
        routeDistanceMeters = 0
        routeDurationSeconds = 0
        detectedCountryCode = "US"
        calculatedFareUSD = 0.50
        calculatedFareIQD = 0
        isFareLocked = true
        stopFareRecoveryLoop()
    }

    // MARK: - Currency
    private func formattedFareText() -> String {
        if detectedCountryCode == "US" {
            return String(format: "$%.2f", calculatedFareUSD)
        } else {
            return "\(calculatedFareIQD) IQD"
        }
    }

    private var isFareReady: Bool {
        if detectedCountryCode == "US" {
            return calculatedFareUSD > 0
        }
        // If country is unknown, we will resolve it during calculation and still consider fare ready once either is set.
        return calculatedFareIQD > 0 || calculatedFareUSD > 0
    }

    private var canProceed: Bool {
        guard addressesReady && isFareReady else { return false }
        if isScheduledRideSelected { return true }
        return resolvedDestinationCoordinate != nil
    }

    // fallback dest coord until geocoding + routing finishes
    private var destinationCoordinateForMap: CLLocationCoordinate2D {
        destinationCoordinate ?? CLLocationCoordinate2D(
            latitude: pickupCoordinate.latitude + 0.02,
            longitude: pickupCoordinate.longitude + 0.02
        )
    }

    private var isScheduledRideSelected: Bool {
        guard scheduledForEpoch > 0 else { return false }
        let d = Date(timeIntervalSince1970: scheduledForEpoch)
        return d.timeIntervalSince(Date()) > 60
    }

    private var options: [RideOption] {
        // Base fare from route (IQD or USD). If not ready yet, show placeholders.
        let baseIQD = calculatedFareIQD
        let baseUSD = calculatedFareUSD
        let isUS = detectedCountryCode == "US"

        // Multipliers for different products
        let saverIQD = baseIQD
        let lumoxIQD = Int(Double(baseIQD) * 1.20)
        let lumoxlIQD = Int(Double(baseIQD) * 1.45)
        let saverUSD = baseUSD
        let lumoxUSD = isMinimumSamePlaceFareActive ? baseUSD : baseUSD * 1.20
        let lumoxlUSD = isMinimumSamePlaceFareActive ? baseUSD : baseUSD * 1.45

        // Show placeholder until fare is ready
        let saverText = isUS
            ? (baseUSD > 0 ? String(format: "$%.2f", saverUSD) : "…")
            : (baseIQD > 0 ? "\(saverIQD) IQD" : "…")
        let lumoxText = isUS
            ? (baseUSD > 0 ? String(format: "$%.2f", lumoxUSD) : "…")
            : (baseIQD > 0 ? "\(lumoxIQD) IQD" : "…")
        let lumoxlText = isUS
            ? (baseUSD > 0 ? String(format: "$%.2f", lumoxlUSD) : "…")
            : (baseIQD > 0 ? "\(lumoxlIQD) IQD" : "…")

        // Optional crossed-out price for Saver (show higher "original" price)
        let saverOriginalText: String? = isUS
            ? (baseUSD > 0 ? String(format: "$%.2f", saverUSD * 1.35) : nil)
            : (baseIQD > 0 ? "\(Int(Double(saverIQD) * 1.35)) IQD" : nil)

        return [
            RideOption(
                id: "saver",
                name: "Saver",
                subtitle: "More affordable, shared route",
                eta: "6:15 PM · 8–17 min",
                price: saverText,
                crossedOutPrice: saverOriginalText,
                isRecommended: true
            ),
            RideOption(
                id: "lumox",
                name: "LumoX",
                subtitle: "Standard ride for up to 4",
                eta: "6:03 PM · 7 min",
                price: lumoxText,
                crossedOutPrice: nil,
                isRecommended: false
            ),
            RideOption(
                id: "lumoxl",
                name: "LumoXL",
                subtitle: "Larger car, up to 6",
                eta: "6:05 PM · 8 min",
                price: lumoxlText,
                crossedOutPrice: nil,
                isRecommended: false
            )
        ]
    }

    private var selectedOption: RideOption? {
        guard let selectedOptionID else { return options.first }
        return options.first { $0.id == selectedOptionID }
    }

    private var selectedFareUSD: Double {
        let base = calculatedFareUSD
        if isMinimumSamePlaceFareActive {
            return 0.50
        }
        let optionID = selectedOptionID ?? options.first?.id ?? "saver"

        switch optionID {
        case "lumox":
            return (base * 1.20 * 100).rounded() / 100
        case "lumoxl":
            return (base * 1.45 * 100).rounded() / 100
        default:
            return (base * 100).rounded() / 100
        }
    }

    private var selectedFareIQD: Int {
        let base = calculatedFareIQD
        let optionID = selectedOptionID ?? options.first?.id ?? "saver"

        switch optionID {
        case "lumox":
            return Int(Double(base) * 1.20)
        case "lumoxl":
            return Int(Double(base) * 1.45)
        default:
            return base
        }
    }

    private var selectedFareText: String {
        if detectedCountryCode == "US" {
            return String(format: "$%.2f", selectedFareUSD)
        } else {
            return "\(selectedFareIQD) IQD"
        }
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
                        Text(resolvedPickupAddress)
                            .font(.system(size: 13))
                            .foregroundColor(.gray.opacity(0.8))

                        Text(resolvedDropoffAddress)
                            .font(.system(size: 13))
                            .foregroundColor(.gray.opacity(0.8))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)

                    if (detectedCountryCode == "US" && selectedFareUSD > 0) ||
                        (detectedCountryCode != "US" && selectedFareIQD > 0) {
                        Text(selectedFareText)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.top, 6)
                    }

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

                    // Choose button
                    Button {
                        if detectedCountryCode == "US" {
                            guard selectedFareUSD > 0 else { return }
                        } else {
                            guard selectedFareIQD > 0 else { return }
                        }

                        // ✅ Scheduled ride: go to payment so AddPaymentView can create status = "scheduled"
                        // and show the RideScheduledView confirmation screen.
                        if isScheduledRideSelected {
                            showPaymentForScheduled = true
                            return
                        }

                        // ✅ Immediate ride: payment owns the single ride creation.
                        guard let dest = resolvedDestinationCoordinate else { return }
                        destinationCoordinate = dest
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
                    .disabled(!canProceed)
                    .opacity(canProceed ? 1.0 : 0.55)

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
            // Freeze what the user picked so it never changes later
            frozenPickupAddress = pickupAddressFinal
            frozenDropoffAddress = dropoffAddressFinal

            if isSamePickupAndDropoffAddress {
                lockSamePlaceMinimumFare()
            } else {
                geocodeAndRoute()
                startFareRecoveryLoop()
            }
        }
        .onDisappear {
            stopFareRecoveryLoop()
        }
        .fullScreenCover(isPresented: $showConfirmPickup) {
            ConfirmPickupView(
                pickupAddress: resolvedPickupAddress,
                pickupCoordinate: pickupCoordinate,
                dropoffAddress: resolvedDropoffAddress,
                dropoffCoordinate: destinationCoordinateForMap,
                fareIQD: detectedCountryCode == "US" ? nil : selectedFareIQD,
                fareUSD: detectedCountryCode == "US" ? selectedFareUSD : nil,
                currency: detectedCountryCode == "US" ? "USD" : "IQD",
                rideId: nil,
                rideTypeLabel: selectedOption?.name,
                estimatedFareText: selectedFareText
            )
        }
        .navigationDestination(isPresented: $showPaymentForScheduled) {
            AddPaymentView(
                pickupAddress: resolvedPickupAddress,
                dropoffAddress: resolvedDropoffAddress,
                pickupLat: pickupCoordinate.latitude,
                pickupLng: pickupCoordinate.longitude,
                dropoffLat: destinationCoordinateForMap.latitude,
                dropoffLng: destinationCoordinateForMap.longitude,
                rideTypeLabel: selectedOption?.name,
                estimatedFareText: selectedFareText,
                fareIQD: detectedCountryCode == "US" ? nil : selectedFareIQD,
                fareUSD: detectedCountryCode == "US" ? selectedFareUSD : nil,
                currency: detectedCountryCode == "US" ? "USD" : "IQD",
                scheduledForEpoch: scheduledForEpoch
            )
        }
        .navigationBarBackButtonHidden(true)   // hide system back button
    }

    // MARK: - Geocoding + routing
    private func geocodeAndRoute() {
        // ✅ FIX: use trimmed final dropoff
        geocoder.geocodeAddressString(dropoffAddressFinal) { placemarks, _ in
            guard let location = placemarks?.first?.location else { return }
            DispatchQueue.main.async {
                destinationCoordinate = location.coordinate
                isFareLocked = false
                routeCoordinates = nil
                calculateRouteIfPossible()      // ensure route always draws
                detectCountry(from: pickupCoordinate)
            }
        }
    }

    private func calculateRouteIfPossible() {
        guard
            let dest = destinationCoordinate,
            CLLocationCoordinate2DIsValid(dest)
        else { return }

        if CLLocation(latitude: pickupCoordinate.latitude, longitude: pickupCoordinate.longitude)
            .distance(from: CLLocation(latitude: dest.latitude, longitude: dest.longitude)) <= 25 {
            lockSamePlaceMinimumFare()
            return
        }

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: pickupCoordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: dest))
        request.transportType = .automobile

        let directions = MKDirections(request: request)
        directions.calculate { response, _ in
            guard let route = response?.routes.first else { return }
            // Do not recalculate if fare is already locked
            if isFareLocked { return }

            let polyline = route.polyline

            // SAVE distance + duration
            routeDistanceMeters = route.distance
            routeDurationSeconds = Int(route.expectedTravelTime)

            // CALCULATE fare based on resolved country.
            // If reverse-geocode is slow/fails, fall back to device region so fare still appears and stays stable.
            let resolvedCountry = detectedCountryCode ?? (Locale.current.regionCode ?? "US")

            if resolvedCountry == "US" {
                calculatedFareUSD = USAutoFareCalculator.calculate(
                    distanceMeters: routeDistanceMeters,
                    durationSeconds: routeDurationSeconds
                )
                calculatedFareIQD = 0
            } else {
                calculatedFareIQD = IraqAutoFareCalculator.calculate(
                    distanceMeters: routeDistanceMeters,
                    durationSeconds: routeDurationSeconds
                )
                calculatedFareUSD = 0
            }

            // Ensure UI has a stable country code once we have a fare
            if detectedCountryCode == nil {
                DispatchQueue.main.async {
                    self.detectedCountryCode = resolvedCountry
                }
            }

            // Lock fare after first successful calculation
            isFareLocked = true
            stopFareRecoveryLoop()

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

    private func detectCountry(from coordinate: CLLocationCoordinate2D) {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        CLGeocoder().reverseGeocodeLocation(location) { placemarks, _ in
            let country = placemarks?.first?.isoCountryCode ?? (Locale.current.regionCode ?? "US")
            DispatchQueue.main.async {
                self.detectedCountryCode = country
                calculateRouteIfPossible() // 🔑 trigger route + fare
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
                    LumoRideOptionLogo()
                        .frame(width: 26, height: 26)
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
                .stroke(
                    isSelected ? Color.white : Color.white.opacity(0.15),
                    lineWidth: isSelected ? 2 : 1
                )
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(isSelected ? Color.white.opacity(0.08) : Color.white.opacity(0.04))
                )
        )
    }
}

private struct LumoRideOptionLogo: View {
    // Try common asset names. Use the first one that exists.
    private let candidateNames = ["LumoLogo", "lumo_logo", "Lumo", "lumo", "speedCar"]

    private var existingAssetName: String? {
        for name in candidateNames {
            if UIImage(named: name) != nil { return name }
        }
        return nil
    }

    var body: some View {
        if let name = existingAssetName {
            Image(name)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundColor(.white)
        } else {
            Image(systemName: "car.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
        }
    }
}

// MARK: - Silent fare recovery (non-visual)
extension RideOptionsView {

    private func startFareRecoveryLoop() {
        // Avoid multiple timers
        if fareRecoveryTimer != nil { return }

        fareRecoveryAttempts = 0
        fareRecoveryTimer = Timer.scheduledTimer(withTimeInterval: fareRecoveryInterval, repeats: true) { _ in
            // Stop if already ready
            if isFareReady {
                stopFareRecoveryLoop()
                return
            }

            fareRecoveryAttempts += 1
            if fareRecoveryAttempts >= maxFareRecoveryAttempts {
                stopFareRecoveryLoop()
                return
            }

            // Retry routing/fare calculation quietly
            DispatchQueue.main.async {
                // If destination is known, try to compute route/fare again.
                calculateRouteIfPossible()

                // If country detection failed, fall back to device region so UI can show a stable currency.
                if detectedCountryCode == nil {
                    detectedCountryCode = Locale.current.regionCode ?? "US"
                }
            }
        }

        if let t = fareRecoveryTimer {
            RunLoop.main.add(t, forMode: .common)
        }
    }

    private func stopFareRecoveryLoop() {
        fareRecoveryTimer?.invalidate()
        fareRecoveryTimer = nil
    }
}
