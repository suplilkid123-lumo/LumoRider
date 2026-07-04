import SwiftUI
import MapKit
import CoreLocation
import Combine

// MARK: - Location (one-shot)
final class OneShotLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var lastLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus

    private let manager: CLLocationManager

    override init() {
        let m = CLLocationManager()
        self.manager = m
        self.authorizationStatus = m.authorizationStatus
        super.init()
        m.delegate = self
        m.desiredAccuracy = kCLLocationAccuracyBest
    }

    func requestPermissionIfNeeded() {
        let status = manager.authorizationStatus
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    func requestOneShotLocation() {
        requestPermissionIfNeeded()
        manager.requestLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        // If user just granted permission, try to fetch immediately.
        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        lastLocation = locations.last
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // No-op; caller can keep UI as-is.
    }
}

// MARK: - Geocoding helpers
@MainActor
private func reverseGeocodeAddress(for location: CLLocation) async -> String? {
    do {
        let placemarks = try await CLGeocoder().reverseGeocodeLocation(location)
        guard let p = placemarks.first else { return nil }

        // Build a readable one-line address.
        var parts: [String] = []
        if let sub = p.subThoroughfare { parts.append(sub) }
        if let thorough = p.thoroughfare { parts.append(thorough) }
        let streetLine = parts.joined(separator: " ")

        var line2Parts: [String] = []
        if let city = p.locality { line2Parts.append(city) }
        if let state = p.administrativeArea { line2Parts.append(state) }
        if let zip = p.postalCode { line2Parts.append(zip) }
        let line2 = line2Parts.joined(separator: ", ")

        let combined = [streetLine, line2].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return combined.isEmpty ? nil : combined.joined(separator: ", ")
    } catch {
        return nil
    }
}

@MainActor
private func geocodeCoordinate(for address: String) async -> CLLocationCoordinate2D? {
    let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    do {
        let placemarks = try await CLGeocoder().geocodeAddressString(trimmed)
        return placemarks.first?.location?.coordinate
    } catch {
        return nil
    }
}

struct ScheduleRideView: View {
    @Environment(\.dismiss) private var dismiss

    // Persisted scheduled-ride state (set elsewhere when a scheduled ride is actually created)
    @AppStorage("lumo_has_scheduled_ride") private var hasScheduledRide: Bool = false
    @AppStorage("lumo_scheduled_ride_id") private var scheduledRideId: String = ""
    @AppStorage("lumo_scheduled_pickup_address") private var scheduledPickupAddress: String = ""
    @AppStorage("lumo_scheduled_dropoff_address") private var scheduledDropoffAddress: String = ""
    @AppStorage("lumo_scheduled_pickup_lat") private var scheduledPickupLat: Double = 0
    @AppStorage("lumo_scheduled_pickup_lng") private var scheduledPickupLng: Double = 0
    @AppStorage("lumo_scheduled_dropoff_lat") private var scheduledDropoffLat: Double = 0
    @AppStorage("lumo_scheduled_dropoff_lng") private var scheduledDropoffLng: Double = 0
    @AppStorage("lumo_scheduled_for_epoch") private var scheduledForEpochPersisted: Double = 0
    @AppStorage("lumo_scheduled_ride_type") private var scheduledRideTypePersisted: String = ""
    @AppStorage("lumo_scheduled_notes") private var scheduledNotesPersisted: String = ""

    // Used to detect when a scheduled ride is newly created while this screen is on the stack
    @State private var initialHasScheduledRide: Bool = false

    // Text fields
    @State private var pickupText: String = "Current location"
    @State private var dropoffText: String = ""

    // Time / type / notes
    @State private var pickupDate: Date = Date()
    @State private var selectedRideType: RideType = .standard
    @State private var notes: String = ""

    // 🔹 Autocomplete for PICKUP + DROPOFF
    @StateObject private var pickupCompleter = AddressSearchCompleter()
    @State private var showPickupSuggestions: Bool = false
    @State private var isSelectingPickupSuggestion: Bool = false

    @StateObject private var dropoffCompleter = AddressSearchCompleter()
    @State private var showDropoffSuggestions: Bool = false
    @State private var isSelectingDropoffSuggestion: Bool = false

    // 🔹 Live location
    @StateObject private var locationManager = OneShotLocationManager()
    @State private var pickupLat: Double? = nil
    @State private var pickupLng: Double? = nil
    @State private var dropoffLat: Double? = nil
    @State private var dropoffLng: Double? = nil
    @State private var isResolvingLocation: Bool = false

    // 🔹 Navigation to PAYMENT METHODS screen
    @State private var goToPayment: Bool = false

    // Tracks whether we pushed into the payment flow so we can detect when the user returns.
    @State private var didEnterPaymentFlow: Bool = false

    // 🔹 Scheduled-ride metadata (used by payment/request flow)
    @State private var scheduledForEpochToPass: Double = 0

    // Dispatch lead time (how long before pickup time the backend should start matching)
    private let dispatchLeadMinutes: Double = 0
    private let scheduledPaymentDoneKey = "lumo_scheduled_payment_done"
    @AppStorage("lumo_scheduled_payment_done") private var scheduledPaymentDoneFlag: Bool = false

    enum RideType: String, CaseIterable {
        case standard = "Standard"
        case xl = "XL"
        case comfort = "Comfort"
        case luxury = "Luxury"
    }

    // MARK: - Scheduled Ride Summary helpers
    private static let summaryDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = .current
        f.dateStyle = .full
        f.timeStyle = .short
        return f
    }()

    private var isScheduledFuture: Bool {
        pickupDate.timeIntervalSince(Date()) > 0
    }

    private var scheduledSummaryTimeText: String {
        Self.summaryDateFormatter.string(from: pickupDate)
    }

    private var pickupSummaryText: String {
        let t = pickupText.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "Current location" : t
    }

    private var dropoffSummaryText: String {
        dropoffText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var notesSummaryText: String {
        notes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func cancelSchedulingAndDismiss() {
        clearPersistedScheduledRide()
        dismiss()
    }

    private func persistScheduledRideDraft() {
        scheduledPickupAddress = pickupSummaryText
        scheduledDropoffAddress = dropoffSummaryText

        scheduledPickupLat = pickupLat ?? 0
        scheduledPickupLng = pickupLng ?? 0
        scheduledDropoffLat = dropoffLat ?? 0
        scheduledDropoffLng = dropoffLng ?? 0

        scheduledForEpochPersisted = scheduledForEpochToPass
        scheduledRideTypePersisted = selectedRideType.rawValue
        scheduledNotesPersisted = notesSummaryText

        // Keep compatibility with existing reads
        UserDefaults.standard.set(scheduledForEpochToPass, forKey: "lumo_scheduled_for_epoch")

        // ✅ Extra compatibility keys for HomeView “Ride scheduled” pill
        // Some screens read the pickup time using different UserDefaults keys.
        let epochToStore = (scheduledForEpochToPass > 0) ? scheduledForEpochToPass : pickupDate.timeIntervalSince1970
        let pickupDateObj = Date(timeIntervalSince1970: epochToStore)

        UserDefaults.standard.set(epochToStore, forKey: "lumo_scheduled_pickup_epoch")
        UserDefaults.standard.set(epochToStore, forKey: "lumo_scheduled_pickup_time_epoch")
        UserDefaults.standard.set(epochToStore, forKey: "lumo_scheduledPickupTimestamp")
        UserDefaults.standard.set(pickupDateObj, forKey: "lumo_scheduledPickupDate")

        // Optional formatted strings (safe for UI fallback)
        UserDefaults.standard.set(Self.summaryDateFormatter.string(from: pickupDateObj), forKey: "lumo_scheduledPickupTimeString")
        UserDefaults.standard.set(ISO8601DateFormatter().string(from: pickupDateObj), forKey: "lumo_scheduledPickupISO")
    }

    private func clearPersistedScheduledRide() {
        hasScheduledRide = false
        scheduledRideId = ""
        scheduledPickupAddress = ""
        scheduledDropoffAddress = ""
        scheduledPickupLat = 0
        scheduledPickupLng = 0
        scheduledDropoffLat = 0
        scheduledDropoffLng = 0
        scheduledForEpochPersisted = 0
        scheduledRideTypePersisted = ""
        scheduledNotesPersisted = ""
        UserDefaults.standard.removeObject(forKey: "lumo_scheduled_for_epoch")
        UserDefaults.standard.removeObject(forKey: "lumo_scheduled_pickup_epoch")
        UserDefaults.standard.removeObject(forKey: "lumo_scheduled_pickup_time_epoch")
        UserDefaults.standard.removeObject(forKey: "lumo_scheduledPickupTimestamp")
        UserDefaults.standard.removeObject(forKey: "lumo_scheduledPickupDate")
        UserDefaults.standard.removeObject(forKey: "lumo_scheduledPickupTimeString")
        UserDefaults.standard.removeObject(forKey: "lumo_scheduledPickupISO")
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()


            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // TOP BAR
                    HStack {
                        Button { dismiss() } label: {
                            Circle()
                                .fill(Color.white.opacity(0.12))
                                .frame(width: 34, height: 34)
                                .overlay(
                                    Image(systemName: "chevron.left")
                                        .foregroundColor(.white)
                                )
                        }

                        Spacer()
                    }
                    .padding(.top, 8)

                    Text("Schedule a ride")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)

                    // PICKUP / DROPOFF CARD
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(spacing: 6) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 8, height: 8)

                                Rectangle()
                                    .fill(Color.white.opacity(0.4))
                                    .frame(width: 2, height: 18)

                                Image(systemName: "diamond.fill")
                                    .font(.system(size: 7))
                                    .foregroundColor(.white.opacity(0.7))
                            }

                            VStack(alignment: .leading, spacing: 12) {
                                // Pickup
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Pickup")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.white.opacity(0.6))
                                    
                                    ZStack(alignment: .leading) {
                                        if pickupText.isEmpty {
                                            Text("Enter pickup")
                                                .foregroundColor(Color.white.opacity(0.35))
                                                .padding(.horizontal, 16)
                                                .padding(.vertical, 12)
                                        }

                                        TextField("", text: $pickupText)
                                            .foregroundColor(.white)
                                            .tint(.white)
                                            .padding(10)
                                            .onChange(of: pickupText) { newValue in
                                                if isSelectingPickupSuggestion {
                                                    isSelectingPickupSuggestion = false
                                                    return
                                                }

                                                // If user manually edits pickup, clear any previously locked coordinates.
                                                pickupLat = nil
                                                pickupLng = nil

                                                let trimmed = newValue.trimmingCharacters(in: .whitespaces)
                                                if trimmed.isEmpty {
                                                    showPickupSuggestions = false
                                                    pickupCompleter.results = []
                                                } else {
                                                    showPickupSuggestions = true
                                                    pickupCompleter.update(query: trimmed)
                                                }
                                            }
                                    }
                                    .background(Color.white.opacity(0.06))
                                    .cornerRadius(10)

                                    Button {
                                        isResolvingLocation = true
                                        locationManager.requestOneShotLocation()
                                    } label: {
                                        HStack(spacing: 8) {
                                            Image(systemName: isResolvingLocation ? "location.fill" : "location")
                                                .foregroundColor(.white)
                                            Text(isResolvingLocation ? "Using current location…" : "Use current location")
                                                .font(.system(size: 13, weight: .semibold))
                                                .foregroundColor(.white)
                                            Spacer()
                                        }
                                        .padding(.vertical, 10)
                                        .padding(.horizontal, 12)
                                        .background(Color.white.opacity(0.08))
                                        .cornerRadius(12)
                                    }
                                    .buttonStyle(.plain)
                                }

                                // Dropoff
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Dropoff")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.white.opacity(0.6))

                                    ZStack(alignment: .leading) {
                                        if dropoffText.isEmpty {
                                            Text("Enter destination")
                                                .foregroundColor(Color.white.opacity(0.35))
                                                .padding(.horizontal, 16)
                                                .padding(.vertical, 12)
                                        }

                                        TextField("", text: $dropoffText)
                                            .foregroundColor(.white)
                                            .tint(.white)
                                            .padding(10)
                                            .onChange(of: dropoffText) { newValue in
                                                if isSelectingDropoffSuggestion {
                                                    isSelectingDropoffSuggestion = false
                                                    return
                                                }

                                                let trimmed = newValue.trimmingCharacters(in: .whitespaces)
                                                if trimmed.isEmpty {
                                                    showDropoffSuggestions = false
                                                    dropoffCompleter.results = []
                                                } else {
                                                    showDropoffSuggestions = true
                                                    dropoffCompleter.update(query: trimmed)
                                                }
                                            }
                                    }
                                    .background(Color.white.opacity(0.06))
                                    .cornerRadius(10)
                                }
                            }
                        }
                        // 🔽 Suggestions list for PICK-UP
                        if showPickupSuggestions && !pickupCompleter.results.isEmpty {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(pickupCompleter.results.indices, id: \.self) { index in
                                    let item = pickupCompleter.results[index]
                                    Button {
                                        let full = item.title +
                                            (item.subtitle.isEmpty ? "" : ", \(item.subtitle)")

                                        // 👇 Mark this as a programmatic update so onChange ignores it
                                        isSelectingPickupSuggestion = true
                                        pickupText = full

                                        // Clear any previously set coordinates; we'll geocode on Continue.
                                        pickupLat = nil
                                        pickupLng = nil

                                        showPickupSuggestions = false
                                        pickupCompleter.results = []
                                    } label: {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.title)
                                                .font(.system(size: 14, weight: .medium))
                                                .foregroundColor(.white)

                                            if !item.subtitle.isEmpty {
                                                Text(item.subtitle)
                                                    .font(.system(size: 12))
                                                    .foregroundColor(.white.opacity(0.7))
                                            }
                                        }
                                        .padding(.vertical, 8)
                                        .padding(.horizontal, 8)
                                    }
                                    .buttonStyle(.plain)

                                    if index != pickupCompleter.results.indices.last {
                                        Divider()
                                            .background(Color.white.opacity(0.15))
                                    }
                                }
                            }
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(12)
                        }
                        // 🔽 Suggestions list for DROP-OFF
                        if showDropoffSuggestions && !dropoffCompleter.results.isEmpty {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(dropoffCompleter.results.indices, id: \.self) { index in
                                    let item = dropoffCompleter.results[index]
                                    Button {
                                        let full = item.title +
                                            (item.subtitle.isEmpty ? "" : ", \(item.subtitle)")

                                        // 👇 Mark this as a programmatic update so onChange ignores it
                                        isSelectingDropoffSuggestion = true
                                        dropoffText = full

                                        showDropoffSuggestions = false
                                        dropoffCompleter.results = []
                                    } label: {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.title)
                                                .font(.system(size: 14, weight: .medium))
                                                .foregroundColor(.white)

                                            if !item.subtitle.isEmpty {
                                                Text(item.subtitle)
                                                    .font(.system(size: 12))
                                                    .foregroundColor(.white.opacity(0.7))
                                            }
                                        }
                                        .padding(.vertical, 8)
                                        .padding(.horizontal, 8)
                                    }
                                    .buttonStyle(.plain)

                                    if index != dropoffCompleter.results.indices.last {
                                        Divider()
                                            .background(Color.white.opacity(0.15))
                                    }
                                }
                            }
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(12)
                        }
                    }
                    .padding(16)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(20)

                    // PICKUP TIME
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Pickup time")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.white)

                        DatePicker(
                            "",
                            selection: $pickupDate,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .labelsHidden()
                        .colorScheme(.dark)

                        Text(
                            dispatchLeadMinutes <= 0
                            ? "Scheduled rides will be requested at your pickup time."
                            : "Scheduled rides will be requested about \(Int(dispatchLeadMinutes)) minutes before your pickup time."
                        )
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.6))
                    }

                    // RIDE TYPE
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ride type")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.white)

                        HStack(spacing: 8) {
                            ForEach(RideType.allCases, id: \.self) { type in
                                Button {
                                    selectedRideType = type
                                } label: {
                                    Text(type.rawValue)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(
                                            selectedRideType == type ? .black : .white.opacity(0.7)
                                        )
                                        .padding(.vertical, 8)
                                        .padding(.horizontal, 14)
                                        .background(
                                            selectedRideType == type
                                            ? Color.white
                                            : Color.white.opacity(0.08)
                                        )
                                        .cornerRadius(16)
                                }
                            }
                        }
                    }

                    // NOTES
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notes for driver (optional)")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.white)

                        ZStack(alignment: .topLeading) {
                            if notes.isEmpty {
                                Text("E.g. “I have luggage” or “Pick me up from side entrance”")
                                    .foregroundColor(Color.white.opacity(0.35))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 14)
                            }

                            TextField(
                                "",
                                text: $notes,
                                axis: .vertical
                            )
                            .foregroundColor(.white)
                            .tint(.white)
                            .padding(10)
                        }
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(14)
                    }

                    // SCHEDULED RIDE SUMMARY (shows the user exactly what they booked)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Text(isScheduledFuture ? "Scheduled ride" : "Ride details")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)

                            Spacer()

                            if isScheduledFuture {
                                Text("Scheduled")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.black)
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 10)
                                    .background(Color.white)
                                    .cornerRadius(999)
                            }
                        }

                        // Time
                        HStack {
                            Text("Pickup time")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white.opacity(0.65))
                            Spacer()
                            Text(scheduledSummaryTimeText)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                                .multilineTextAlignment(.trailing)
                        }

                        // From / To
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top, spacing: 10) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 8, height: 8)
                                    .padding(.top, 4)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("From")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.white.opacity(0.6))
                                    Text(pickupSummaryText)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.white)
                                        .lineLimit(2)
                                }
                                Spacer(minLength: 0)
                            }

                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "diamond.fill")
                                    .font(.system(size: 8))
                                    .foregroundColor(.white.opacity(0.7))
                                    .padding(.top, 5)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("To")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.white.opacity(0.6))
                                    Text(dropoffSummaryText.isEmpty ? "Enter destination" : dropoffSummaryText)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.white)
                                        .lineLimit(2)
                                }
                                Spacer(minLength: 0)
                            }
                        }

                        // Ride type
                        HStack {
                            Text("Ride type")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white.opacity(0.65))
                            Spacer()
                            Text(selectedRideType.rawValue)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                        }

                        // Notes (optional)
                        if !notesSummaryText.isEmpty {
                            Text("Notes: \(notesSummaryText)")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.7))
                                .lineLimit(3)
                        }

                        // Small hint
                        if isScheduledFuture {
                            Text("We’ll start looking for a driver near your pickup time.")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }
                    .padding(16)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(20)

                    // FARE / PAYMENT SUMMARY
                    VStack(spacing: 8) {
                        HStack {
                            Text("Estimated fare")
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.7))
                            Spacer()
                            Text("$18–24")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                        }

                        HStack {
                            Text("Payment")
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.7))
                            Spacer()
                            Text("•••• 3942 · Visa")
                                .font(.system(size: 15))
                                .foregroundColor(.white)
                        }
                    }
                    .padding(14)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(18)

                    // CONFIRM BUTTON
                    Button {
                        Task { @MainActor in
                            // Resolve coordinates (pickup)
                            if pickupLat == nil || pickupLng == nil {
                                if let coord = await geocodeCoordinate(for: pickupText.isEmpty ? "Current location" : pickupText) {
                                    pickupLat = coord.latitude
                                    pickupLng = coord.longitude
                                }
                            }

                            // Resolve coordinates (dropoff)
                            if dropoffLat == nil || dropoffLng == nil {
                                if let coord = await geocodeCoordinate(for: dropoffText) {
                                    dropoffLat = coord.latitude
                                    dropoffLng = coord.longitude
                                }
                            }

                            // Persist scheduled-ride intent so the payment/request flow can create a true scheduled ride.
                            // Treat ANY pickup time in the future as a scheduled ride.
                            let now = Date()
                            let isFuture = pickupDate.timeIntervalSince(now) > 0

                            scheduledForEpochToPass = isFuture ? pickupDate.timeIntervalSince1970 : 0

                            // IMPORTANT: Do NOT persist scheduled ride draft yet.
                            // We only persist AFTER payment succeeds (like Uber/Lyft).

                            didEnterPaymentFlow = true
                            goToPayment = true   // opens AddPaymentView with the current values
                        }
                    } label: {
                        Text("Continue")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.white)
                            .foregroundColor(.black)
                            .cornerRadius(28)
                    }
                    .padding(.top, 4)

                    // CANCELLATION BUTTON
                    Button(role: .destructive) {
                        cancelSchedulingAndDismiss()
                    } label: {
                        Text("Cancel")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.red.opacity(0.9))
                            .foregroundColor(.white)
                            .cornerRadius(28)
                    }
                    .padding(.top, 8)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .navigationBarBackButtonHidden(true)
        .onChange(of: scheduledPaymentDoneFlag) { didComplete in
            // ✅ Success path:
            // ScheduleRide -> Payment -> Ride scheduled -> Done
            // Done sets lumo_scheduled_payment_done=true.
            // We persist the scheduled draft, close the payment modal, then return to Home.
            guard didComplete else { return }

            // Persist scheduled ride ONLY after successful completion.
            if scheduledForEpochToPass > 0 {
                hasScheduledRide = true
                if scheduledRideId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    scheduledRideId = UUID().uuidString
                }

                UserDefaults.standard.set(scheduledForEpochToPass, forKey: "lumo_scheduled_for_epoch")
                persistScheduledRideDraft()
            }

            // Close the payment modal if it's open.
            if goToPayment {
                goToPayment = false
            }

            didEnterPaymentFlow = false

            // Reset so it doesn't re-trigger later.
            scheduledPaymentDoneFlag = false

            // Return to Home.
            DispatchQueue.main.async {
                dismiss()
            }
        }
        .onChange(of: goToPayment) { isActive in
            // If the user closes the payment flow WITHOUT completing, stay on this screen.
            if didEnterPaymentFlow && !isActive {
                didEnterPaymentFlow = false
            }
        }
        // (onAppear block removed)
        // (onChange(of: hasScheduledRide) block removed)
        .onReceive(locationManager.$lastLocation) { loc in
            guard let loc else { return }
            // Only auto-fill when the user tapped "Use current location"
            guard isResolvingLocation else { return }

            // Lock coordinates from GPS
            pickupLat = loc.coordinate.latitude
            pickupLng = loc.coordinate.longitude

            // Hide pickup suggestions
            showPickupSuggestions = false
            pickupCompleter.results = []

            Task { @MainActor in
                if let addr = await reverseGeocodeAddress(for: loc) {
                    isSelectingPickupSuggestion = true
                    pickupText = addr
                } else {
                    isSelectingPickupSuggestion = true
                    pickupText = "Current location"
                }
                isResolvingLocation = false
            }
        }
        .fullScreenCover(isPresented: $goToPayment) {
            NavigationStack {
                AddPaymentView(
                    pickupAddress: pickupText.isEmpty ? "Current location" : pickupText,
                    dropoffAddress: dropoffText,
                    pickupLat: pickupLat ?? 41.8781,
                    pickupLng: pickupLng ?? -87.6298,
                    dropoffLat: dropoffLat ?? 41.8781,
                    dropoffLng: dropoffLng ?? -87.6298,
                    scheduledForEpoch: scheduledForEpochToPass
                )
            }
        }
    }
}

#Preview {
    NavigationStack {
        ScheduleRideView()
    }
}
