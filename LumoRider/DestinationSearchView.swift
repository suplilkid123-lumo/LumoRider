import SwiftUI
import MapKit
import CoreLocation
import Combine

// MARK: - Autocomplete helper

@MainActor
class AddressSearchCompleter: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var results: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
    }

    func update(query: String) {
        completer.queryFragment = query
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        results = completer.results
    }
}

@MainActor
final class DestinationPickupLocator: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var coordinate: CLLocationCoordinate2D?
    @Published var currentAddress: String = ""
    @Published var locationFailed: Bool = false

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var didRequestPermission = false
    private var isUpdatingLocation = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func start() {
        let status = manager.authorizationStatus
        print("📍 DestinationPickupLocator auth status:", status.rawValue)

        switch status {
        case .notDetermined:
            if !didRequestPermission {
                didRequestPermission = true
                manager.requestWhenInUseAuthorization()
            }
        case .authorizedAlways, .authorizedWhenInUse:
            if let cachedLocation = manager.location {
                print("📍 DestinationPickupLocator cached coordinate:", cachedLocation.coordinate.latitude, cachedLocation.coordinate.longitude)
                locationFailed = false
                coordinate = cachedLocation.coordinate
                reverseGeocode(cachedLocation)
            }

            guard !isUpdatingLocation else { return }
            isUpdatingLocation = true
            manager.startUpdatingLocation()
            manager.requestLocation()
        case .denied, .restricted:
            locationFailed = true
            print("❌ DestinationPickupLocator permission denied/restricted")
        @unknown default:
            break
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.start()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        Task { @MainActor in
            print("📍 DestinationPickupLocator coordinate:", location.coordinate.latitude, location.coordinate.longitude)
            self.locationFailed = false
            self.isUpdatingLocation = false
            self.coordinate = location.coordinate
            self.reverseGeocode(location)
            self.manager.stopUpdatingLocation()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.isUpdatingLocation = false

            if let cachedLocation = manager.location {
                print("📍 DestinationPickupLocator fallback cached coordinate:", cachedLocation.coordinate.latitude, cachedLocation.coordinate.longitude)
                self.locationFailed = false
                self.coordinate = cachedLocation.coordinate
                self.reverseGeocode(cachedLocation)
                return
            }

            self.locationFailed = true
            print("❌ DestinationPickupLocator location failed:", error.localizedDescription)
        }
    }

    private func reverseGeocode(_ location: CLLocation) {
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            guard let self else { return }

            if let error {
                print("❌ DestinationPickupLocator reverse geocode failed:", error.localizedDescription)
                return
            }

            guard let pm = placemarks?.first else {
                print("❌ DestinationPickupLocator no placemark")
                return
            }

            let parts = [
                pm.name,
                pm.thoroughfare,
                pm.locality,
                pm.administrativeArea,
                pm.postalCode,
                pm.country
            ].compactMap { $0 }.filter { !$0.isEmpty }

            let formatted = parts.joined(separator: ", ")
            guard !formatted.isEmpty else { return }

            Task { @MainActor in
                print("📍 DestinationPickupLocator address:", formatted)
                self.currentAddress = formatted
            }
        }
    }
}

// MARK: - DestinationSearchView

struct DestinationSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var locationManager: LumoLocationManager
    @StateObject private var completer = AddressSearchCompleter()
    @StateObject private var pickupLocator = DestinationPickupLocator()

    @State private var pickupText: String = ""
    @State private var destinationText: String = ""

    @FocusState private var pickupFocused: Bool
    @FocusState private var destinationFocused: Bool

    @State private var isSelectingSuggestion: Bool = false
    @State private var pickupUserEdited: Bool = false
    @State private var isAutoFillingPickup: Bool = false
    @State private var isReverseGeocodingPickup: Bool = false

    @State private var showRideOptions: Bool = false   // 👈 new
    @State private var showingPickupSuggestions: Bool = false

    // Resolved coordinates for reliable pickup/destination
    @State private var pickupCoordinateOverride: CLLocationCoordinate2D? = nil
    @State private var destinationCoordinate: CLLocationCoordinate2D? = nil
    @State private var isResolvingContinue: Bool = false

    @State private var recentPlaces: [String] = []
    private let recentPlacesKey = "lumo_recent_places"

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 20) {

                // Grabber
                Capsule()
                    .fill(Color.white.opacity(0.4))
                    .frame(width: 40, height: 5)
                    .padding(.top, 14)

                // Top bar
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.down")
                            .foregroundColor(.white)
                            .padding(8)
                            .background(Color.white.opacity(0.2))
                            .clipShape(Circle())
                    }

                    Spacer()

                    Text("Set your trip")
                        .foregroundColor(.white)
                        .font(.system(size: 17, weight: .semibold))

                    Spacer().frame(width: 32)
                }
                .padding(.horizontal, 24)

                // Card with pickup + destination
                VStack(spacing: 0) {

                    // Pickup
                    HStack(spacing: 12) {
                        Image(systemName: "smallcircle.filled.circle.fill")
                            .foregroundColor(.green)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Pickup")
                                .font(.system(size: 13))
                                .foregroundColor(.gray)

                            TextField("Enter pickup", text: $pickupText)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.black)
                                .textInputAutocapitalization(.words)
                                .disableAutocorrection(true)
                                .focused($pickupFocused)
                                .onChange(of: pickupText) { _ in
                                    // Once the user manually edits pickup, keep their choice until they explicitly
                                    // reset it with "Use current location".
                                    if !isAutoFillingPickup {
                                        pickupUserEdited = true
                                    }
                                }
                                .onChange(of: pickupText) { newValue in
                                    guard pickupFocused else { return }
                                    guard pickupUserEdited else { return }

                                    let trimmed = newValue.trimmingCharacters(in: .whitespaces)
                                    if trimmed.isEmpty {
                                        showingPickupSuggestions = false
                                        completer.results = []
                                    } else {
                                        showingPickupSuggestions = true
                                        completer.update(query: trimmed)
                                    }
                                }

                            Button {
                                // Force-reset to current location (even if address isn't ready yet)
                                pickupUserEdited = false
                                showingPickupSuggestions = false
                                completer.results = []
                                fillPickupFromCurrentLocation(force: true)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "location.fill")
                                        .font(.system(size: 12, weight: .semibold))
                                    Text("Use current location")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .foregroundColor(.black.opacity(0.8))
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 2)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                    .padding(.bottom, 12)

                    Divider().padding(.horizontal, 18)

                    // Destination
                    HStack(spacing: 12) {
                        Image(systemName: "mappin.circle.fill")
                            .foregroundColor(.black)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Destination")
                                .font(.system(size: 13))
                                .foregroundColor(.gray)

                            TextField("Where to?", text: $destinationText)
                                .font(.system(size: 16))
                                .foregroundColor(.black)
                                .focused($destinationFocused)
                                .onChange(of: destinationText) { newValue in
                                    // Ignore programmatic changes from selection
                                    if isSelectingSuggestion {
                                        isSelectingSuggestion = false
                                        return
                                    }

                                    guard destinationFocused else { return }
                                    destinationCoordinate = nil

                                    let trimmed = newValue.trimmingCharacters(in: .whitespaces)
                                    if trimmed.isEmpty {
                                        completer.results = []
                                    } else {
                                        completer.update(query: trimmed)
                                    }
                                }
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                }
                .background(Color.white)
                .cornerRadius(20)
                .padding(.horizontal, 16)

                // Recent places
                if completer.results.isEmpty && !recentPlaces.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Recent places")
                            .foregroundColor(.white.opacity(0.8))
                            .font(.system(size: 14, weight: .semibold))
                            .padding(.horizontal, 24)

                        ForEach(recentPlaces, id: \.self) { place in
                            Button {
                                if pickupFocused {
                                    pickupText = place
                                    pickupUserEdited = true
                                } else {
                                    destinationText = place
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "clock")
                                        .foregroundColor(.white.opacity(0.7))

                                    Text(place)
                                        .foregroundColor(.white)
                                        .font(.system(size: 16))

                                    Spacer()
                                }
                                .padding(.horizontal, 24)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Pickup address suggestions
                if showingPickupSuggestions && !completer.results.isEmpty {
                    ScrollView {
                        VStack(spacing: 14) {
                            ForEach(completer.results, id: \.self) { item in
                                Button {
                                    isSelectingSuggestion = true
                                    pickupFocused = false
                                    pickupUserEdited = true
                                    showingPickupSuggestions = false
                                    completer.results = []

                                    resolveCompletion(item) { resolvedAddress, coord in
                                        DispatchQueue.main.async {
                                            self.pickupText = resolvedAddress
                                            if let coord { self.pickupCoordinateOverride = coord }

                                            if !self.recentPlaces.contains(resolvedAddress) {
                                                self.recentPlaces.insert(resolvedAddress, at: 0)
                                                self.recentPlaces = Array(self.recentPlaces.prefix(5))
                                                self.saveRecentPlaces()
                                            }
                                        }
                                    }
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.title)
                                            .foregroundColor(.white)
                                            .font(.system(size: 16, weight: .medium))

                                        if !item.subtitle.isEmpty {
                                            Text(item.subtitle)
                                                .foregroundColor(.white.opacity(0.7))
                                                .font(.system(size: 13))
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)

                                Divider().background(Color.white.opacity(0.2))
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                }

                // Suggestions
                if !completer.results.isEmpty && !showingPickupSuggestions {
                    ScrollView {
                        VStack(spacing: 14) {
                            ForEach(completer.results, id: \.self) { item in
                                Button {
                                    isSelectingSuggestion = true
                                    destinationFocused = false
                                    completer.results = []

                                    resolveCompletion(item) { resolvedAddress, coord in
                                        DispatchQueue.main.async {
                                            self.destinationText = resolvedAddress
                                            if let coord { self.destinationCoordinate = coord }

                                            if !self.recentPlaces.contains(resolvedAddress) {
                                                self.recentPlaces.insert(resolvedAddress, at: 0)
                                                self.recentPlaces = Array(self.recentPlaces.prefix(5))
                                                self.saveRecentPlaces()
                                            }
                                        }
                                    }
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.title)
                                            .foregroundColor(.white)
                                            .font(.system(size: 16, weight: .medium))

                                        if !item.subtitle.isEmpty {
                                            Text(item.subtitle)
                                                .foregroundColor(.white.opacity(0.7))
                                                .font(.system(size: 13))
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)

                                Divider().background(Color.white.opacity(0.2))
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                }

                Spacer()

                // Continue button at the bottom
                Button {
                    // Resolve pickup/destination to real coordinates before continuing.
                    guard !isResolvingContinue else { return }
                    isResolvingContinue = true

                    let needsPickupResolve = pickupUserEdited && pickupCoordinateOverride == nil && !pickupText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    let needsDestinationResolve = destinationCoordinate == nil && !destinationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

                    func finishAndShow() {
                        DispatchQueue.main.async {
                            self.isResolvingContinue = false
                            self.showRideOptions = true
                        }
                    }

                    func resolveDestinationThenFinish() {
                        if needsDestinationResolve {
                            resolveQuery(destinationText) { resolvedAddress, coord in
                                DispatchQueue.main.async {
                                    self.destinationText = resolvedAddress
                                    self.destinationCoordinate = coord
                                }
                                finishAndShow()
                            } onFail: {
                                DispatchQueue.main.async { self.isResolvingContinue = false }
                            }
                        } else {
                            finishAndShow()
                        }
                    }

                    if needsPickupResolve {
                        resolveQuery(pickupText) { resolvedAddress, coord in
                            DispatchQueue.main.async {
                                self.pickupText = resolvedAddress
                                self.pickupCoordinateOverride = coord
                            }
                            resolveDestinationThenFinish()
                        } onFail: {
                            // Even if pickup resolve fails, still try destination resolve.
                            resolveDestinationThenFinish()
                        }
                    } else {
                        resolveDestinationThenFinish()
                    }
                } label: {
                    Text("Continue")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background((destinationText.isEmpty || isResolvingContinue) ? Color.white.opacity(0.3) : Color.white)
                        .foregroundColor(.black)
                        .cornerRadius(30)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .disabled(destinationText.isEmpty || isResolvingContinue)
            }
        }
        .onAppear {
            loadRecentPlaces()
            pickupLocator.start()
            // Initial autofill from the user's current location. Try a few times because
            // location/currentAddress may arrive after this sheet appears.
            fillPickupFromCurrentLocation(force: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                pickupLocator.start()
                fillPickupFromCurrentLocation(force: false)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                pickupLocator.start()
                fillPickupFromCurrentLocation(force: false)
            }
        }
        .onChange(of: locationManager.currentAddress) { _ in
            fillPickupFromCurrentLocation(force: false)
        }
        .onChange(of: pickupLocator.currentAddress) { _ in
            fillPickupFromCurrentLocation(force: false)
        }
        .onChange(of: pickupLocator.locationFailed) { failed in
            guard failed else { return }
            if pickupText == "Finding your location..." || pickupText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                isAutoFillingPickup = true
                pickupText = "Location unavailable"
                isAutoFillingPickup = false
            }
        }
        .onChange(of: locationManager.coordinate?.latitude ?? 0) { _ in
            // If address is still empty but coordinate updates, try again.
            fillPickupFromCurrentLocation(force: false)
        }
        .onChange(of: locationManager.coordinate?.longitude ?? 0) { _ in
            // Longitude can update separately from latitude.
            fillPickupFromCurrentLocation(force: false)
        }
        .onChange(of: pickupLocator.coordinate?.latitude ?? 0) { _ in
            fillPickupFromCurrentLocation(force: false)
        }
        .onChange(of: pickupLocator.coordinate?.longitude ?? 0) { _ in
            fillPickupFromCurrentLocation(force: false)
        }
        .sheet(isPresented: $showRideOptions) {
            let pickupCoord =
                pickupCoordinateOverride
                ?? locationManager.coordinate
                ?? pickupLocator.coordinate
                ?? CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)

            RideOptionsView(
                pickupAddress: pickupText.isEmpty ? locationManager.currentAddress : pickupText,
                destinationAddress: destinationText,
                pickupCoordinate: pickupCoord
            )
        }
    }
    private func resolveCompletion(_ completion: MKLocalSearchCompletion,
                                   onResolved: @escaping (_ address: String, _ coordinate: CLLocationCoordinate2D?) -> Void) {
        let request = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: request)
        search.start { response, error in
            guard error == nil, let item = response?.mapItems.first else {
                let fallback = completion.subtitle.isEmpty ? completion.title : "\(completion.title), \(completion.subtitle)"
                onResolved(fallback, nil)
                return
            }
            let coord = item.placemark.coordinate
            let formatted = item.placemark.title ?? (completion.subtitle.isEmpty ? completion.title : "\(completion.title), \(completion.subtitle)")
            onResolved(formatted, coord)
        }
    }

    private func resolveQuery(_ query: String,
                              onResolved: @escaping (_ address: String, _ coordinate: CLLocationCoordinate2D) -> Void,
                              onFail: @escaping () -> Void) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { onFail(); return }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        let search = MKLocalSearch(request: request)
        search.start { response, error in
            guard error == nil, let item = response?.mapItems.first else {
                onFail()
                return
            }
            let coord = item.placemark.coordinate
            let formatted = item.placemark.title ?? trimmed
            onResolved(formatted, coord)
        }
    }

    // MARK: - Current location autofill
    private func fillPickupFromCurrentLocation(force: Bool) {
        if force {
            pickupUserEdited = false
            showingPickupSuggestions = false
            completer.results = []
            pickupLocator.start()
        } else {
            // Only overwrite pickup if user hasn't edited, unless forced by the button.
            guard !pickupUserEdited else { return }
        }

        let trimmedPickup = pickupText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !force && !trimmedPickup.isEmpty && trimmedPickup != "Finding your location..." {
            return
        }

        // Prefer the already-computed readable address.
        let primaryAddress = locationManager.currentAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackAddress = pickupLocator.currentAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let addr = !primaryAddress.isEmpty ? primaryAddress : fallbackAddress
        if !addr.isEmpty {
            isAutoFillingPickup = true
            pickupText = addr
            pickupCoordinateOverride = locationManager.coordinate ?? pickupLocator.coordinate
            isAutoFillingPickup = false
            return
        }

        // Fallback: reverse geocode the current coordinate if address is not ready yet.
        guard let coord = locationManager.coordinate ?? pickupLocator.coordinate else {
            pickupLocator.start()

            if pickupLocator.locationFailed {
                isAutoFillingPickup = true
                pickupText = "Location unavailable"
                isAutoFillingPickup = false
                return
            }

            if force && pickupText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                isAutoFillingPickup = true
                pickupText = "Finding your location..."
                isAutoFillingPickup = false
            }

            // Try one more time shortly because location permission/location may arrive after tapping.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                guard self.pickupText == "Finding your location..." || self.pickupText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                self.pickupLocator.start()
                self.fillPickupFromCurrentLocation(force: false)
            }
            return
        }

        pickupCoordinateOverride = coord

        guard !isReverseGeocodingPickup else { return }
        isReverseGeocodingPickup = true

        let loc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        CLGeocoder().reverseGeocodeLocation(loc) { placemarks, _ in
            DispatchQueue.main.async {
                self.isReverseGeocodingPickup = false
            }

            guard let pm = placemarks?.first else {
                DispatchQueue.main.async {
                    if force || self.pickupText == "Finding your location..." || self.pickupText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        self.isAutoFillingPickup = true
                        self.pickupText = String(format: "Current location (%.5f, %.5f)", coord.latitude, coord.longitude)
                        self.isAutoFillingPickup = false
                    }
                }
                return
            }

            let parts = [
                pm.name,
                pm.thoroughfare,
                pm.locality,
                pm.administrativeArea,
                pm.postalCode,
                pm.country
            ].compactMap { $0 }.filter { !$0.isEmpty }

            let formatted = parts.joined(separator: ", ")
            guard !formatted.isEmpty else { return }

            DispatchQueue.main.async {
                // Ignore stale autofill callbacks after the user has manually edited pickup.
                if !force {
                    guard !self.pickupUserEdited else { return }
                    let current = self.pickupText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard current.isEmpty || current == "Finding your location..." else { return }
                }

                self.isAutoFillingPickup = true
                self.pickupText = formatted
                self.pickupCoordinateOverride = coord
                self.isAutoFillingPickup = false
            }
        }
    }

    // MARK: - Persistence helpers
    private func loadRecentPlaces() {
        if let saved = UserDefaults.standard.array(forKey: recentPlacesKey) as? [String] {
            recentPlaces = saved
        }
    }

    private func saveRecentPlaces() {
        UserDefaults.standard.set(recentPlaces, forKey: recentPlacesKey)
    }
}

#Preview {
    DestinationSearchView(locationManager: LumoLocationManager())
}
