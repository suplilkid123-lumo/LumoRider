import SwiftUI
import UIKit
import CoreLocation
import GoogleMaps
import Combine
import AudioToolbox

// MARK: - Notification extension for ride cancellation
extension Notification.Name {
    static let RideDidCancel = Notification.Name("RideDidCancel")
}

public struct DriverTrackingView: View {
    public struct DriverProfile: Equatable {
        public var name: String
        public var rating: Double
        public var vehicleMakeModel: String
        public var serviceLevel: String
        public var plate: String
        public var colorName: String
        public var phoneE164: String?
        public var photoURL: String?

        public init(
            name: String,
            rating: Double,
            vehicleMakeModel: String,
            serviceLevel: String,
            plate: String,
            colorName: String,
            phoneE164: String? = nil,
            photoURL: String? = nil
        ) {
            self.name = name
            self.rating = rating
            self.vehicleMakeModel = vehicleMakeModel
            self.serviceLevel = serviceLevel
            self.plate = plate
            self.colorName = colorName
            self.phoneE164 = phoneE164
            self.photoURL = photoURL
        }
    }

    private let rideId: String
    private let supabaseURL: URL
    private let supabaseAnonKey: String
    private let driver: DriverProfile
    private let onChat: (() -> Void)?
    private let localSenderRole: String

    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm: VM
    @State private var isChatPresented: Bool = false
    @State private var showCancelConfirm: Bool = false
    @State private var riderRecenterToken: UUID = UUID()
    // Removed this line as per instructions:
    // @State private var unreadCount: Int = 0

    public init(
        rideId: String,
        driver: DriverProfile = .init(
            name: "Your driver",
            rating: 4.92,
            vehicleMakeModel: "Sedan",
            serviceLevel: "Comfort",
            plate: "—",
            colorName: "Black",
            phoneE164: nil,
            photoURL: nil
        ),
        supabaseURL: URL? = nil,
        supabaseAnonKey: String? = nil,
        onChat: (() -> Void)? = nil,
        localSenderRole: String = "rider"
    ) {
        let normalizedRideId = rideId.trimmingCharacters(in: .whitespacesAndNewlines)
        self.rideId = normalizedRideId
        self.driver = driver
        self.onChat = onChat
        self.localSenderRole = localSenderRole

        let url = supabaseURL
            ?? URL(string: (Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String) ?? "")
            ?? URL(string: "https://rpryqbdodbieioebedjg.supabase.co")!

        let key = supabaseAnonKey
            ?? (Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String)
            ?? "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJwcnlxYmRvZGJpZWlvZWJlZGpnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjUwNjE0MjYsImV4cCI6MjA4MDYzNzQyNn0.8ZTaA1bCyRUKb6U4NNZou6DMfXP3yyE1NeNL8Ljt9as"

        self.supabaseURL = url
        self.supabaseAnonKey = key
        _vm = StateObject(wrappedValue: VM(rideId: normalizedRideId, supabaseURL: url, supabaseAnonKey: key, localSenderRole: localSenderRole))
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            PremiumTrackingMapView(
                driver: $vm.driverState,
                rider: $vm.riderState,
                route: $vm.routeState,
                followMode: $vm.followMode,
                riderRecenterToken: riderRecenterToken,
                mapStyleJSON: vm.mapStyleJSON
            )
            .ignoresSafeArea()

            topChrome

            BottomSheet(
                isExpanded: $vm.sheetExpanded,
                collapsedHeight: 148,
                expandedHeight: 286
            ) {
                sheetContent
            }
        }
        .confirmationDialog(
            "Cancel this ride?",
            isPresented: $showCancelConfirm,
            titleVisibility: .visible
        ) {
            Button("Cancel ride", role: .destructive) {
                Task { await vm.riderCancelAndExit() }
            }
            Button("Keep ride", role: .cancel) {
                showCancelConfirm = false
            }
        } message: {
            Text("Are you sure you want to cancel? The driver will be notified and the ride will end immediately.")
        }
        .onAppear {
            vm.start()
        }
        .onDisappear {
            vm.stop()
        }
        .onChange(of: vm.shouldExit) { _, shouldExit in
            if shouldExit { dismissToHome() }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(false)
        .alert("Trip cancelled", isPresented: $vm.showCancelAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(vm.cancelAlertMessage)
        }
        .fullScreenCover(isPresented: $isChatPresented) {
            RideChatView(
                rideId: self.rideId,
                supabaseURL: supabaseURL,
                supabaseAnonKey: supabaseAnonKey,
                localSender: localSenderRole
            )
        }
        .onChange(of: isChatPresented) { _, presented in
            vm.isChatPresented = presented
            if !presented {
                Task { await vm.markMessagesRead() }
            }
        }
    }
      
    private var topChrome: some View {
        VStack {
            HStack(spacing: 10) {
                Spacer()

                CircleButton(systemName: "location.fill", background: UIColor.systemBlue) {
                    // Recenter to the rider's location only.
                    vm.followMode = .free
                    riderRecenterToken = UUID()
                }

                SegmentedPill(
                    leftTitle: "Follow",
                    rightTitle: "Free",
                    isLeftSelected: vm.followMode == .follow
                ) { leftSelected in
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
                        vm.followMode = leftSelected ? .follow : .free
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            Spacer()
        }
    }

    private var sheetContent: some View {
        let d = vm.driverProfile ?? driver
        return VStack(spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                DriverAvatar(name: d.name, photoURL: d.photoURL)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(d.name)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)

                        RatingBadge(rating: d.rating)
                    }

                    Text("\(d.vehicleMakeModel) • \(d.serviceLevel) • \(d.colorName)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.72))

                    Text(d.plate)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.92))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.white.opacity(0.10), lineWidth: 1)
                        )
                }

                Spacer()
            }

            HStack(spacing: 10) {
                InfoPill(
                    title: "ETA",
                    value: vm.etaText,
                    icon: "clock"
                )

                InfoPill(
                    title: "Distance",
                    value: vm.distanceText,
                    icon: "location.north.line"
                )
            }

            Button {
                if let onChat {
                    onChat()
                } else {
                    isChatPresented = true
                    Task { await vm.markMessagesRead() }
                }
            } label: {
                ZStack(alignment: .topTrailing) {
                    HStack(spacing: 10) {
                        Image(systemName: "message.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Chat")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.0), lineWidth: 1)
                    )

                    if vm.unreadCount > 0 {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 12, height: 12)
                            .offset(x: -10, y: 8)
                            .transition(.scale)
                    }
                }
            }

            Button {
                showCancelConfirm = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Cancel trip")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.red)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            if vm.sheetExpanded {
                HStack(spacing: 10) {
                    StatusChip(text: vm.connectionText, kind: vm.connectionKind)
                    Spacer()
                    StatusChip(text: vm.driverSpeedText, kind: .neutral)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 14)
    }
    @MainActor
    private func dismissToHome() {
        dismiss()
        if let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first,
           let root = scene.windows.first?.rootViewController,
           root.presentedViewController != nil {
            root.dismiss(animated: true)
        }
    }
}

private final class VM: ObservableObject {
    enum FollowMode { case follow, free }

    enum UnitSystem: String {
        case imperial
        case metric

        var isImperial: Bool { self == .imperial }
    }

    struct DriverState {
        var coord: CLLocationCoordinate2D?
        var headingDeg: Double?
        var speedMps: Double?
        var updatedAt: Date?
    }

    struct RiderState {
        var coord: CLLocationCoordinate2D?
        var updatedAt: Date?
    }

    struct RouteState {
        var points: [CLLocationCoordinate2D] = []
        var updatedAt: Date?
        var etaSeconds: Int?
        var distanceMeters: Double?
    }
    @Published var showCancelAlert: Bool = false
    @Published var cancelAlertMessage: String = ""
    @Published var errorText: String? = nil
    private var statusPollTask: Task<Void, Never>?
    @Published var driverState: DriverState = .init()
    @Published var riderState: RiderState = .init()
    @Published var routeState: RouteState = .init()
    @Published var followMode: FollowMode = .follow
    @Published var sheetExpanded: Bool = false
    @Published var driverProfile: DriverTrackingView.DriverProfile? = nil
    @Published var shouldExit: Bool = false
    @Published var isChatPresented: Bool = false

    @Published var unreadCount: Int = 0
    private var lastSeenMessageAt: Date? = nil
    private var messagePollTask: Task<Void, Never>? = nil
    private var lastNotifiedUnreadCount: Int = 0

    let localSenderRole: String

    @Published var unitSystem: UnitSystem = {
        let raw = UserDefaults.standard.string(forKey: "tracking_unitSystem")
        return UnitSystem(rawValue: raw ?? "imperial") ?? .imperial
    }() {
        didSet {
            UserDefaults.standard.set(unitSystem.rawValue, forKey: "tracking_unitSystem")
        }
    }

    let rideId: String
    let supabaseURL: URL
    let supabaseAnonKey: String

    private let riderLocation = RiderLocationSource()
    private var realtime: SupabaseRealtimeLite?
    private var routeTask: Task<Void, Never>?
    private var driverRefreshTask: Task<Void, Never>?
    private var lastRouteRequestAt: Date = .distantPast
    private var pickupCoord: CLLocationCoordinate2D?

    // MARK: - Derived telemetry (fallbacks)
    private var lastDriverCoordForSpeed: CLLocationCoordinate2D?
    private var lastDriverSpeedAt: Date?

    var mapStyleJSON: String? {
        Bundle.main.path(forResource: "LumoMapStyle", ofType: "json").flatMap { try? String(contentsOfFile: $0, encoding: .utf8) }
    }

    init(rideId: String, supabaseURL: URL, supabaseAnonKey: String, localSenderRole: String) {
        self.rideId = rideId
        self.supabaseURL = supabaseURL
        self.supabaseAnonKey = supabaseAnonKey
        self.localSenderRole = localSenderRole
    }

    func start() {
        riderLocation.onUpdate = { [weak self] coord in
            guard let self else { return }
            Task { @MainActor in
                self.riderState.coord = coord
                self.riderState.updatedAt = Date()
                self.scheduleRouteUpdate()
            }
        }
        riderLocation.start()

        prefillDriverFromRESTIfNeeded()
        prefillPickupFromRESTIfNeeded()
        fetchDriverProfileForRide(force: true)

        if realtime == nil {
            realtime = SupabaseRealtimeLite(
                supabaseURL: supabaseURL,
                anonKey: supabaseAnonKey
            )
            realtime?.onDriverUpdate = { [weak self] update in
                guard let self else { return }
                Task { @MainActor in
                    let now = Date()
                    self.driverState.coord = update.coord
                    self.driverState.headingDeg = update.headingDeg
                    self.driverState.updatedAt = now
                    print("[LIVE TRACKING] Driver update:", update.coord.latitude, update.coord.longitude)

                    // Prefer backend speed, but derive it if missing.
                    if let s = update.speedMps, s.isFinite, s > 0 {
                        self.driverState.speedMps = s
                        self.lastDriverCoordForSpeed = update.coord
                        self.lastDriverSpeedAt = now
                    } else {
                        let derived = self.estimateSpeedMpsIfNeeded(newCoord: update.coord, updatedAt: now)
                        if let derived { self.driverState.speedMps = derived }
                    }

                    self.scheduleRouteUpdate()
                }
            }
            realtime?.onConnectionState = { [weak self] state in
                guard let self else { return }
                Task { @MainActor in
                    self._connectionState = state
                }
            }
        }

        realtime?.start(rideId: rideId)
        print("[REALTIME] Subscribed to rides updates for ride:", rideId)
        // Prefill driver marker immediately (so it shows even before first realtime event)
        prefillDriverFromRESTIfNeeded()
        startDriverRefreshLoop()
        startStatusMonitoring()
        startMessagePolling()
        registerLifecycle()
    }

    func stop() {
        unregisterLifecycle()
        riderLocation.stop()
        realtime?.stop()
        routeTask?.cancel()
        routeTask = nil
        driverRefreshTask?.cancel()
        driverRefreshTask = nil
        messagePollTask?.cancel()
        messagePollTask = nil
    }

    func cancelTripAndExit() async {
        await cancelRideInSupabase()
        stop()
        await MainActor.run {
            self.shouldExit = true
        }
    }

    func riderCancelAndExit() async {
        await riderCancelRide()
        stop()
        await MainActor.run {
            cancelAlertMessage = "Trip cancelled"
            showCancelAlert = true
            shouldExit = true
        }
    }
    
    private func startStatusMonitoring() {
        statusPollTask?.cancel()
        statusPollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.checkRideStatus()
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }
    }

    private func cleanupAndExit() {
        stop()
        shouldExit = true
    }


private func checkRideStatus() async {
    guard let url = rideRowURL() else { return }

    var req = URLRequest(url: url)
    req.httpMethod = "GET"
    req.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
    req.setValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
    req.setValue("application/json", forHTTPHeaderField: "Accept")

    do {
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }

        // If the ride row is gone (deleted), treat it as cancelled and exit.
        guard let row = arr.first else {
            await MainActor.run {
                cancelAlertMessage = "Trip cancelled"
                showCancelAlert = true
                cleanupAndExit()
            }
            return
        }

        let status = row["status"] as? String
        if let status {
            handleRideStatusChange(status)
        }
    } catch {
        // ignore network errors
    }
}

    private func cancelRideInSupabase() async {
        var comps = URLComponents(url: supabaseURL.appendingPathComponent("rest/v1/rides"), resolvingAgainstBaseURL: false)
        comps?.queryItems = [
            URLQueryItem(name: "id", value: "eq.\(rideId)")
        ]
        guard let url = comps?.url else { return }

        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("return=representation", forHTTPHeaderField: "Prefer")
        req.timeoutInterval = 12

        let payload: [String: Any] = [
            "status": "cancelled_by_rider",
            "cancelled_by": "rider",
            "cancelled_at": ISO8601DateFormatter().string(from: Date())
        ]

        do {
            req.httpBody = try JSONSerialization.data(withJSONObject: payload)
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                if let http = resp as? HTTPURLResponse {
                    print("[DriverTrackingView] cancelTrip PATCH failed status=\(http.statusCode) body=\(String(data: data, encoding: .utf8) ?? "")")
                }
                return
            }
        } catch {
            print("[DriverTrackingView] cancelTrip error: \(error)")
        }
    }

    private func registerLifecycle() {
        NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appWillResignActive), name: UIApplication.willResignActiveNotification, object: nil)
    }

    private func unregisterLifecycle() {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func appDidBecomeActive() {
        realtime?.resume()
        // Re-prefill after background/foreground in case marker was cleared or no realtime events yet
        prefillDriverFromRESTIfNeeded(force: true)
        fetchDriverProfileForRide(force: true)
        startDriverRefreshLoop()
    }

    @objc private func appWillResignActive() {
        realtime?.pause()
        driverRefreshTask?.cancel()
        driverRefreshTask = nil
    }

    private func scheduleRouteUpdate() {
        guard let r = riderState.coord else { return }

        // If we don't have a real driver yet, still compute UI metrics using a placeholder.
        // This keeps ETA/Distance from showing "—" while we wait for realtime/REST.
        guard let origin = pickupCoord ?? driverState.coord else { return };        let now = Date()
        if now.timeIntervalSince(lastRouteRequestAt) < 5.0 { return }
        lastRouteRequestAt = now

        routeTask?.cancel()
        routeTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            let route = await GoogleDirectionsLite.fetchRoute(
                from: origin,
                to: r,
                apiKey: Self.googleAPIKey()
            )
            guard !Task.isCancelled else { return }
            await MainActor.run {
                let now = Date()
                if let route {
                    self.routeState.points = route.points
                    self.routeState.etaSeconds = route.durationSeconds
                    self.routeState.distanceMeters = route.distanceMeters
                    self.routeState.updatedAt = now
                } else {
                    // Fallback: straight-line distance + assumed speed, but still draw a simple line.
                    self.routeState.points = [origin, r]

                    let meters = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
                        .distance(from: CLLocation(latitude: r.latitude, longitude: r.longitude))
                    self.routeState.distanceMeters = meters.isFinite ? meters : nil

                    let mps = max(6.0, (self.driverState.speedMps ?? 11.0))
                    let seconds = Int(max(60, (meters.isFinite ? meters : 0) / mps))
                    self.routeState.etaSeconds = seconds

                    self.routeState.updatedAt = now
                }
            }
        }
    }

    private func estimateSpeedMpsIfNeeded(newCoord: CLLocationCoordinate2D, updatedAt: Date) -> Double? {
        // If backend already provides speed, don't override it.
        if let s = driverState.speedMps, s.isFinite, s > 0 { return s }

        guard let prev = lastDriverCoordForSpeed, let prevAt = lastDriverSpeedAt else {
            lastDriverCoordForSpeed = newCoord
            lastDriverSpeedAt = updatedAt
            return nil
        }

        let dt = updatedAt.timeIntervalSince(prevAt)
        guard dt >= 0.8, dt.isFinite else {
            lastDriverCoordForSpeed = newCoord
            lastDriverSpeedAt = updatedAt
            return nil
        }

        let meters = CLLocation(latitude: prev.latitude, longitude: prev.longitude)
            .distance(from: CLLocation(latitude: newCoord.latitude, longitude: newCoord.longitude))

        // Ignore tiny jitter.
        guard meters.isFinite, meters >= 1.5 else {
            lastDriverCoordForSpeed = newCoord
            lastDriverSpeedAt = updatedAt
            return nil
        }

        let mps = meters / dt
        // Clamp to sane range (0..60 m/s ~ 134 mph)
        let clamped = max(0, min(60, mps))

        lastDriverCoordForSpeed = newCoord
        lastDriverSpeedAt = updatedAt
        return clamped
    }

    // MARK: - Driver Profile (REST)
    private func fetchDriverProfileForRide(force: Bool = false) {
        if !force, driverProfile != nil { return }
        Task { [weak self] in
            guard let self else { return }
            await self.fetchAndApplyDriverProfile()
        }
    }

    private func fetchAndApplyDriverProfile() async {
        guard let url = rideRowURL() else { return }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 12

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return }

            guard let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  let row = arr.first
            else { return }

            // ✅ Prefer nested driver snapshot from the rides row (written by Driver app on accept).
            // Supabase jsonb may arrive as a dictionary or a JSON string depending on encoding.
            let snapshotAny: Any? = row["driver_snapshot"] ?? row["driverSnapshot"]
            let snapshot: [String: Any]? = {
                if let d = snapshotAny as? [String: Any] { return d }
                if let s = snapshotAny as? String, let jd = s.data(using: .utf8) {
                    return (try? JSONSerialization.jsonObject(with: jd)) as? [String: Any]
                }
                return nil
            }()

            if let snap = snapshot {
                let name = snap.stringAny("name", "full_name", "fullName", "display_name", "displayName")
                let rating = snap.doubleAnyOptional("rating", "driver_rating", "driverRating") ?? 4.92
                let vehicle = snap.stringAny("vehicle_make_model", "vehicleMakeModel", "vehicleMakeModel", "vehicleMake", "vehicleModel", "vehicle")
                let service = snap.stringAny("service_level", "serviceLevel", "class", "ride_class", "rideClass", "category")
                let plate = snap.stringAny("plate", "license_plate", "licensePlate")
                let color = snap.stringAny("color", "color_name", "colorName", "vehicle_color", "vehicleColor")
                let phone = snap.stringAnyOptional("phone", "phone_e164", "phoneE164")
                let photo = snap.stringAnyOptional("photo_url", "photoURL", "avatar_url", "avatarURL", "image_url", "imageURL")

                await MainActor.run {
                    self.driverProfile = DriverTrackingView.DriverProfile(
                        name: name.isEmpty ? (self.driverProfile?.name ?? "Your driver") : name,
                        rating: rating,
                        vehicleMakeModel: vehicle.isEmpty ? (self.driverProfile?.vehicleMakeModel ?? "Sedan") : vehicle,
                        serviceLevel: service.isEmpty ? (self.driverProfile?.serviceLevel ?? "Comfort") : service,
                        plate: plate.isEmpty ? (self.driverProfile?.plate ?? "—") : plate,
                        colorName: color.isEmpty ? (self.driverProfile?.colorName ?? "Black") : color,
                        phoneE164: phone ?? self.driverProfile?.phoneE164,
                        photoURL: photo ?? self.driverProfile?.photoURL
                    )
                }

                // If snapshot has enough info, stop here (no need to query other tables).
                if !name.isEmpty || !vehicle.isEmpty || !plate.isEmpty || photo != nil {
                    return
                }
            }

            // If the rides row already includes driver metadata, use it immediately (fast path).
            let rideName = row.stringAny("driver_name", "driverName", "driver_full_name", "driverFullName", "driver_display_name", "driverDisplayName")
            let rideRating = row.doubleAnyOptional("driver_rating", "driverRating", "driver_driver_rating", "driverDriverRating")
            let rideVehicle = row.stringAny("driver_vehicle_make_model", "driverVehicleMakeModel", "driver_vehicle", "driverVehicle", "vehicle_make_model", "vehicleMakeModel", "vehicle", "car")
            let rideService = row.stringAny("driver_service_level", "driverServiceLevel", "service_level", "serviceLevel", "class", "ride_class", "rideClass", "category")
            let ridePlate = row.stringAny("driver_plate", "driverPlate", "plate", "license_plate", "licensePlate")
            let rideColor = row.stringAny("driver_color", "driverColor", "color", "color_name", "colorName", "vehicle_color")
            let ridePhone = row.stringAnyOptional("driver_phone", "driverPhone", "phone", "phone_e164", "phoneE164")
            let ridePhoto = row.stringAnyOptional("driver_photo_url", "driverPhotoURL", "photo_url", "photoURL", "avatar_url", "avatarURL", "image_url", "imageURL")

            if !rideName.isEmpty || !rideVehicle.isEmpty || !ridePlate.isEmpty || ridePhoto != nil {
                await MainActor.run {
                    self.driverProfile = DriverTrackingView.DriverProfile(
                        name: rideName.isEmpty ? (self.driverProfile?.name ?? "Your driver") : rideName,
                        rating: rideRating ?? (self.driverProfile?.rating ?? 4.92),
                        vehicleMakeModel: rideVehicle.isEmpty ? (self.driverProfile?.vehicleMakeModel ?? "Sedan") : rideVehicle,
                        serviceLevel: rideService.isEmpty ? (self.driverProfile?.serviceLevel ?? "Comfort") : rideService,
                        plate: ridePlate.isEmpty ? (self.driverProfile?.plate ?? "—") : ridePlate,
                        colorName: rideColor.isEmpty ? (self.driverProfile?.colorName ?? "Black") : rideColor,
                        phoneE164: ridePhone ?? self.driverProfile?.phoneE164,
                        photoURL: ridePhoto ?? self.driverProfile?.photoURL
                    )
                }
            }

            let driverId = row.stringAny("driver_id", "driverId").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !driverId.isEmpty else { return }

            // Try a few common tables + column keys. This supports either UUID ids or phone/uid-based ids.
            let tablesToTry = ["drivers", "driver_profiles", "profiles", "users"]
            var p: [String: Any]? = nil
            for t in tablesToTry {
                if let row = await fetchProfileRow(fromTable: t, id: driverId) {
                    p = row
                    break
                }
            }

            guard let p else { return }

            let name = p.stringAny("name", "full_name", "fullName", "display_name", "displayName")
            let rating = p.doubleAnyOptional("rating", "driver_rating", "driverRating") ?? 4.92
            let vehicle = p.stringAny("vehicle_make_model", "vehicleMakeModel", "vehicle", "car", "car_model", "carModel")
            let service = p.stringAny("service_level", "serviceLevel", "class", "ride_class", "rideClass", "category")
            let plate = p.stringAny("plate", "license_plate", "licensePlate")
            let color = p.stringAny("color", "color_name", "colorName", "vehicle_color")
            let phone = p.stringAnyOptional("phone", "phone_e164", "phoneE164")
            let photo = p.stringAnyOptional("photo_url", "photoURL", "avatar_url", "avatarURL", "image_url", "imageURL")

            await MainActor.run {
                self.driverProfile = DriverTrackingView.DriverProfile(
                    name: name.isEmpty ? (self.driverProfile?.name ?? "Your driver") : name,
                    rating: rating,
                    vehicleMakeModel: vehicle.isEmpty ? (self.driverProfile?.vehicleMakeModel ?? "Sedan") : vehicle,
                    serviceLevel: service.isEmpty ? (self.driverProfile?.serviceLevel ?? "Comfort") : service,
                    plate: plate.isEmpty ? (self.driverProfile?.plate ?? "—") : plate,
                    colorName: color.isEmpty ? (self.driverProfile?.colorName ?? "Black") : color,
                    phoneE164: phone ?? self.driverProfile?.phoneE164,
                    photoURL: photo ?? self.driverProfile?.photoURL
                )
            }
        } catch {
            // ignore
        }
    }

    private func prefillPickupFromRESTIfNeeded(force: Bool = false) {
        if !force, pickupCoord != nil { return }
        Task { [weak self] in
            await self?.fetchAndApplyPickupCoord()
        }
    }

    private func fetchAndApplyPickupCoord() async {
        guard let url = rideRowURL() else { return }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 12

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return }
            guard let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  let row = arr.first
            else { return }

            let pLat = row.doubleAny("pickup_lat", "pickupLat")
            let pLng = row.doubleAny("pickup_lng", "pickupLng")
            if !isValidLatLng(lat: pLat, lng: pLng) { return }

            await MainActor.run {
                self.pickupCoord = CLLocationCoordinate2D(latitude: pLat, longitude: pLng)
            }
        } catch {
            // ignore
        }
    }

    private func messagesGETURL() -> URL? {
        var comps = URLComponents(url: supabaseURL.appendingPathComponent("rest/v1/messages"), resolvingAgainstBaseURL: false)
        comps?.queryItems = [
            URLQueryItem(name: "select", value: "id,sender,created_at"),
            URLQueryItem(name: "ride_id", value: "eq.\(rideId)"),
            URLQueryItem(name: "order", value: "created_at.asc"),
            URLQueryItem(name: "limit", value: "200")
        ]
        return comps?.url
    }

    private func startMessagePolling() {
        messagePollTask?.cancel()
        messagePollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.updateUnreadCount()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private func updateUnreadCount() async {
        guard let url = messagesGETURL() else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 12
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return }
            guard let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }

            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

            var lastDate: Date? = nil
            var countSinceSeen: Int = 0
            var lastSender: String? = nil
            for row in arr {
                let createdAt: Date? = {
                    if let s = row["created_at"] as? String {
                        return iso.date(from: s) ?? ISO8601DateFormatter().date(from: s)
                    }
                    return nil
                }()
                if let d = createdAt {
                    lastDate = max(lastDate ?? d, d)
                    if let seen = lastSeenMessageAt {
                        if d > seen {
                            countSinceSeen += 1
                            if let sender = row["sender"] as? String {
                                lastSender = sender
                            }
                        }
                    } else {
                        countSinceSeen += 1
                        if let sender = row["sender"] as? String {
                            lastSender = sender
                        }
                    }
                }
            }

            await MainActor.run {
                let oldUnread = self.unreadCount
                self.unreadCount = countSinceSeen
                if self.unreadCount > oldUnread,
                   let s = lastSender?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !s.isEmpty,
                   s.lowercased() != self.localSenderRole.lowercased(),
                   self.isChatPresented == false {
                    Self.playDing()
                }
                self.lastNotifiedUnreadCount = self.unreadCount
                // Update last message timestamp cache
                if let lastDate { /* keep for use when marking read */ }
            }
        } catch { /* ignore */ }
    }

    func markMessagesRead() async {
        // Mark all current messages as read by setting lastSeenMessageAt to latest message timestamp.
        guard let url = messagesGETURL() else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 12
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return }
            guard let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var newest: Date? = nil
            for row in arr {
                if let s = row["created_at"] as? String, let d = iso.date(from: s) ?? ISO8601DateFormatter().date(from: s) {
                    newest = max(newest ?? d, d)
                }
            }
            await MainActor.run {
                self.lastSeenMessageAt = newest
                self.unreadCount = 0
                self.lastNotifiedUnreadCount = 0
            }
        } catch { /* ignore */ }
    }

    private func rideRowURL() -> URL? {
        // /rest/v1/rides?select=*&id=eq.<rideId>&limit=1
        var comps = URLComponents(url: supabaseURL.appendingPathComponent("rest/v1/rides"), resolvingAgainstBaseURL: false)
        comps?.queryItems = [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "id", value: "eq.\(rideId)"),
            URLQueryItem(name: "limit", value: "1")
        ]
        return comps?.url
    }

    // MARK: - Rider cancel (notify driver + cancel ride)
    func riderCancelRide() async {
        // 1) Best-effort: send a system note to the driver (shows in driver chat if they are polling messages)
        await postCancelSystemMessageBestEffort()

        // 2) Cancel the ride request. We use DELETE because your rides.status CHECK constraint (23514)
        // has been rejecting status updates.
        do {
            try await deleteRideRow()
        } catch {
            // If DELETE fails (e.g., FK or policy), surface a readable error.
            await MainActor.run {
                // If this VM already has an error string, prefer that; otherwise set a generic one.
                // Many UIs in this file show errors via a published `errorText` / `toastText` / etc.
                if self.errorText == nil {
                    self.errorText = "Cancel failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func postCancelSystemMessageBestEffort() async {
        guard let url = messagesPOSTURLForCancel() else { return }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let payload: [[String: Any]] = [[
            "id": UUID().uuidString,
            "ride_id": rideId,
            "sender": "system",
            "sender_id": "system",
            "sender_role": "system",
            "body": "Rider canceled the ride.",
            "created_at": iso.string(from: Date())
        ]]

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("public", forHTTPHeaderField: "Accept-Profile")
        req.setValue("public", forHTTPHeaderField: "Content-Profile")
        req.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        req.timeoutInterval = 12

        do {
            req.httpBody = try JSONSerialization.data(withJSONObject: payload)
            let (_, resp) = try await URLSession.shared.data(for: req)
            // Ignore failures here (best-effort). The ride cancel will still proceed.
            _ = resp
        } catch {
            // ignore
        }
    }

    private func deleteRideRow() async throws {
        var comps = URLComponents(url: supabaseURL.appendingPathComponent("rest/v1/rides"), resolvingAgainstBaseURL: false)
        comps?.queryItems = [
            URLQueryItem(name: "id", value: "eq.\(rideId)"),
            URLQueryItem(name: "select", value: "id")
        ]
        guard let url = comps?.url else { throw URLError(.badURL) }

        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        req.timeoutInterval = 12

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw PostgRESTHTTPError(statusCode: http.statusCode, body: body)
        }
    }

    private func messagesPOSTURLForCancel() -> URL? {
        var comps = URLComponents(url: supabaseURL.appendingPathComponent("rest/v1/messages"), resolvingAgainstBaseURL: false)
        comps?.queryItems = [
            URLQueryItem(name: "select", value: "id")
        ]
        return comps?.url
    }

    private func fetchProfileRow(fromTable table: String, id: String) async -> [String: Any]? {
        // Try multiple common identifier columns because projects vary.
        let filterColumns = [
            "id",
            "user_id",
            "uid",
            "driver_id",
            "firebase_uid",
            "firebaseUid",
            "phone_e164",
            "phone",
            "phoneNumber"
        ]

        for col in filterColumns {
            var comps = URLComponents(url: supabaseURL.appendingPathComponent("rest/v1/\(table)"), resolvingAgainstBaseURL: false)
            comps?.queryItems = [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: col, value: "eq.\(id)"),
                URLQueryItem(name: "limit", value: "1")
            ]
            guard let url = comps?.url else { continue }

            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            req.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
            req.setValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.timeoutInterval = 12

            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else { continue }
                guard let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]], let row = arr.first else { continue }
                return row
            } catch {
                continue
            }
        }

        return nil
    }

    // MARK: - Driver Prefill/Refresh (REST)
    private func prefillDriverFromRESTIfNeeded(force: Bool = false) {
        if !force, driverState.coord != nil { return }
        Task { [weak self] in
            await self?.fetchAndApplyLatestDriverLocation()
        }
    }

    private func handleRideStatusChange(_ status: String) {
        guard status == "cancelled_by_driver" || status == "cancelled_by_rider" || status == "cancelled" else { return }

        Task { @MainActor in
            if status == "cancelled_by_driver" {
                cancelAlertMessage = "Driver cancelled the trip."
            } else if status == "cancelled_by_rider" {
                cancelAlertMessage = "Rider cancelled the trip."
            } else {
                cancelAlertMessage = "Trip cancelled."
            }
            showCancelAlert = true
            cleanupAndExit()
        }
    }


    private func startDriverRefreshLoop() {
        driverRefreshTask?.cancel()
        driverRefreshTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                // Update continuously while tracking (keeps UI "live" even if driver doesn't move)
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                guard !Task.isCancelled else { break }
                await self.fetchAndApplyLatestDriverLocation()
            }
        }
    }

    private func fetchAndApplyLatestDriverLocation() async {
        guard let url = latestDriverLocationURL() else { return }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 12

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return }

            guard let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  let row = arr.first
            else { return }


            let lat = row.doubleAny("lat", "latitude", "driver_lat", "driverLat")
            let lng = row.doubleAny("lng", "lon", "longitude", "driver_lng", "driverLng")
            if !isValidLatLng(lat: lat, lng: lng) { return }

            let heading = row.doubleAnyOptional("driver_heading", "heading", "bearing", "course")
            let speed = row.doubleAnyOptional("driver_speed_mps", "speed", "speed_mps", "speedMps")

            await MainActor.run {
                let now = Date()
                driverState.coord = CLLocationCoordinate2D(latitude: lat, longitude: lng)
                driverState.headingDeg = heading
                driverState.updatedAt = now

                if let s = speed, s.isFinite, s > 0 {
                    driverState.speedMps = s
                    lastDriverCoordForSpeed = driverState.coord
                    lastDriverSpeedAt = now
                } else if let coord = driverState.coord {
                    let derived = estimateSpeedMpsIfNeeded(newCoord: coord, updatedAt: now)
                    if let derived { driverState.speedMps = derived }
                }

                scheduleRouteUpdate()
            }
        } catch {
            // ignore
        }
    }

    private func latestDriverLocationURL() -> URL? {
        // Pull driver coords from the rides row (Driver app PATCHes rides.driver_lat/driver_lng)
        // /rest/v1/rides?select=driver_lat,driver_lng,driver_heading,driver_speed_mps,updated_at&id=eq.<rideId>&limit=1
        var comps = URLComponents(url: supabaseURL.appendingPathComponent("rest/v1/rides"), resolvingAgainstBaseURL: false)
        comps?.queryItems = [
            URLQueryItem(name: "select", value: "driver_lat,driver_lng,driver_heading,driver_speed_mps,updated_at"),
            URLQueryItem(name: "id", value: "eq.\(rideId)"),
            URLQueryItem(name: "limit", value: "1")
        ]
        return comps?.url
    }

    private func isValidLatLng(lat: Double, lng: Double) -> Bool {
        if lat.isNaN || lng.isNaN { return false }
        if lat < -90 || lat > 90 { return false }
        if lng < -180 || lng > 180 { return false }
        if abs(lat) < 0.000001 && abs(lng) < 0.000001 { return false }
        return true
    }

    private static func googleAPIKey() -> String? {
        (Bundle.main.object(forInfoDictionaryKey: "GOOGLE_DIRECTIONS_API_KEY") as? String)
            ?? (Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String)
            ?? (Bundle.main.object(forInfoDictionaryKey: "GOOGLE_MAPS_API_KEY") as? String)
    }

    var distanceText: String {
        let meters: Double? = {
            if let m = routeState.distanceMeters { return m }
            guard let d = driverState.coord, let r = riderState.coord else { return nil }
            return CLLocation(latitude: d.latitude, longitude: d.longitude)
                .distance(from: CLLocation(latitude: r.latitude, longitude: r.longitude))
        }()

        guard let m = meters else { return "—" }
        return DistanceFormatter.pretty(meters: m, unitSystem: unitSystem)
    }

    var etaText: String {
        if let s = routeState.etaSeconds {
            return TimeFormatter.pretty(seconds: s)
        }
        guard let d = driverState.coord, let r = riderState.coord else { return "—" }
        let meters = CLLocation(latitude: d.latitude, longitude: d.longitude)
            .distance(from: CLLocation(latitude: r.latitude, longitude: r.longitude))
        let mps = max(6.0, (driverState.speedMps ?? 11.0))
        let seconds = Int(max(60, meters / mps))
        return TimeFormatter.pretty(seconds: seconds)
    }

    fileprivate enum ConnState { case connecting, connected, reconnecting, offline }
    @Published private var _connectionState: ConnState = .connecting

    var connectionText: String {
        switch _connectionState {
        case .connecting: return "Connecting"
        case .connected: return "Live"
        case .reconnecting: return "Reconnecting"
        case .offline: return "Offline"
        }
    }

    var connectionKind: StatusChip.Kind {
        switch _connectionState {
        case .connected: return .good
        case .connecting, .reconnecting: return .warning
        case .offline: return .bad
        }
    }

    var driverSpeedText: String {
        guard let s = driverState.speedMps, s.isFinite, s > 0 else { return "Speed —" }
        if unitSystem.isImperial {
            let mph = s * 2.2369362920544
            return String(format: "Speed %.0f mph", mph)
        } else {
            let kmh = s * 3.6
            return String(format: "Speed %.0f km/h", kmh)
        }
    }

    var driverSubtitleText: String {
        let v = driverProfile?.vehicleMakeModel.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let s = driverProfile?.serviceLevel.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let c = driverProfile?.colorName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let a = v.isEmpty ? "Sedan" : v
        let b = s.isEmpty ? "Comfort" : s
        let d = c.isEmpty ? "Black" : c
        return "\(a) • \(b) • \(d)"
    }

    private static func playDing() {
        AudioServicesPlaySystemSound(1057)
    }

    private func notifyOtherPartyPush(messageText: String) async {
        // Best-effort, never block UI.
        let senderLower = localSenderRole.lowercased()
        let toUserId: String?
        if senderLower == "driver" {
            toUserId = await fetchRiderIdForRide()
        } else if senderLower == "rider" {
            // Replaced local function with call site per instructions:
            let driverId = await fetchDriverIdForRide()
            toUserId = driverId
        } else {
            toUserId = nil
        }
        guard let toUserId, !toUserId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard let url = notifyFunctionURL() else { return }

        let payload: [String: Any] = [
            "to_user_id": toUserId,
            "title": "New message",
            "body": messageText,
            "data": [
                "type": "chat",
                "ride_id": rideId,
                "sender": localSenderRole
            ]
        ]

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 12

        do {
            req.httpBody = try JSONSerialization.data(withJSONObject: payload)
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { return }
            guard (200...299).contains(http.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? ""
                print("[RideChatView] notify push failed status=\(http.statusCode) body=\(body)")
                return
            }
        } catch {
            print("[RideChatView] notify push error: \(error)")
        }
    }

    private func fetchDriverIdForRide() async -> String? {
        var comps = URLComponents(url: supabaseURL.appendingPathComponent("rest/v1/rides"), resolvingAgainstBaseURL: false)
        comps?.queryItems = [
            URLQueryItem(name: "select", value: "driver_id"),
            URLQueryItem(name: "id", value: "eq.\(rideId)")
        ]
        guard let url = comps?.url else { return nil }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 12

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }
            guard let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  let row = arr.first,
                  let driverId = row["driver_id"] as? String,
                  !driverId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return nil }
            return driverId
        } catch {
            return nil
        }
    }

    private func fetchRiderIdForRide() async -> String? {
        // /rest/v1/rides?select=rider_id&id=eq.<rideId>&limit=1
        var comps = URLComponents(url: supabaseURL.appendingPathComponent("rest/v1/rides"), resolvingAgainstBaseURL: false)
        comps?.queryItems = [
            URLQueryItem(name: "select", value: "rider_id"),
            URLQueryItem(name: "id", value: "eq.\(rideId)")
        ]
        guard let url = comps?.url else { return nil }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 12

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }
            guard let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  let row = arr.first,
                  let riderId = row["rider_id"] as? String,
                  !riderId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return nil }
            return riderId
        } catch {
            return nil
        }
    }

    private func notifyFunctionURL() -> URL? {
        // Supabase Edge Function: /functions/v1/notify-new-message
        supabaseURL.appendingPathComponent("functions/v1/notify-new-message")
    }

    private func messagesPOSTURL() -> URL? {
        var comps = URLComponents(url: supabaseURL.appendingPathComponent("rest/v1/messages"), resolvingAgainstBaseURL: false)
        comps?.queryItems = [
            URLQueryItem(name: "select", value: "id,sender,sender_id,body,created_at")
        ]
        return comps?.url
    }
}

private final class RiderLocationSource: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var onUpdate: ((CLLocationCoordinate2D) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 2
        manager.activityType = .automotiveNavigation
        manager.pausesLocationUpdatesAutomatically = true
    }

    func start() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        manager.startUpdatingLocation()
    }

    func stop() {
        manager.stopUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        onUpdate?(last.coordinate)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }
}

private struct PremiumTrackingMapView: UIViewRepresentable {
    @Binding var driver: VM.DriverState
    @Binding var rider: VM.RiderState
    @Binding var route: VM.RouteState
    @Binding var followMode: VM.FollowMode

    let riderRecenterToken: UUID
    let mapStyleJSON: String?

    func makeUIView(context: Context) -> GMSMapView {
        let startTarget: CLLocationCoordinate2D = {
            if let d = driver.coord { return d }
            if let r = rider.coord { return r }
            return CLLocationCoordinate2D(latitude: 33.3152, longitude: 44.3661)
        }()
        let camera = GMSCameraPosition(target: startTarget, zoom: 14)
        let map = GMSMapView(frame: .zero, camera: camera)
        map.delegate = context.coordinator
        map.isMyLocationEnabled = false
        map.settings.rotateGestures = true
        map.settings.tiltGestures = true
        map.settings.compassButton = false
        map.settings.myLocationButton = false
        map.padding = UIEdgeInsets(top: 80, left: 0, bottom: 220, right: 0)

        if let styleJSON = mapStyleJSON, let style = try? GMSMapStyle(jsonString: styleJSON) {
            map.mapStyle = style
        }

        context.coordinator.install(on: map)
        return map
    }

    func updateUIView(_ mapView: GMSMapView, context: Context) {
        context.coordinator.applyFollowMode(followMode)

        if let r = rider.coord {
            context.coordinator.setRider(coord: r)
        }

        if let d = driver.coord {
            context.coordinator.setDriver(coord: d, heading: driver.headingDeg)
        }

        context.coordinator.setRoute(points: route.points)
        context.coordinator.handleRiderRecenterIfNeeded(token: riderRecenterToken, riderCoord: rider.coord)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(followMode: $followMode)
    }

    final class Coordinator: NSObject, GMSMapViewDelegate {
        private let followModeBinding: Binding<VM.FollowMode>
        private var followMode: VM.FollowMode = .follow

        private weak var map: GMSMapView?

        private let driverMarker = GMSMarker()
        private let riderMarker = GMSMarker()
        private let routeLine = GMSPolyline()
        private var latestRoutePoints: [CLLocationCoordinate2D] = []
        private var routePreferredHeading: Double? = nil
        private func headingAlongRoute(near coord: CLLocationCoordinate2D, points: [CLLocationCoordinate2D]) -> Double? {
            guard points.count >= 2 else { return nil }

            // Find the closest segment i -> i+1 to the coordinate.
            var bestIndex = 0
            var bestScore = Double.greatestFiniteMagnitude

            let latScale = 111_000.0
            let lngScale = cos(coord.latitude * .pi / 180) * 111_000.0

            for i in 0..<(points.count - 1) {
                let p = points[i]
                let dx = (p.longitude - coord.longitude) * lngScale
                let dy = (p.latitude - coord.latitude) * latScale
                let score = dx*dx + dy*dy
                if score < bestScore {
                    bestScore = score
                    bestIndex = i
                }
            }

            let a = points[bestIndex]
            let b = points[min(bestIndex + 1, points.count - 1)]
            let h = bearingDeg(from: a, to: b)
            return h.isFinite ? normalizeDegrees(h) : nil
        }

        private var carView = PremiumCarMarkerView()
        private var hasCenteredOnce = false
        private var lastRiderRecenterToken: UUID?

        private var currentDriver: CLLocationCoordinate2D?
        private var targetDriver: CLLocationCoordinate2D?
        private var currentHeading: Double = 0
        private var targetHeading: Double = 0

        private var displayLink: CADisplayLink?
        private var interpStartTime: CFTimeInterval = 0
        private var interpDuration: CFTimeInterval = 1.15
        private var startCoord: CLLocationCoordinate2D?
        private var endCoord: CLLocationCoordinate2D?
        private var lastCameraTick: CFTimeInterval = 0

        private var zoomScale: CGFloat = 1.0

        init(followMode: Binding<VM.FollowMode>) {
            self.followModeBinding = followMode
        }

        func applyFollowMode(_ mode: VM.FollowMode) {
            followMode = mode
            // If the user switches back to Follow, immediately snap back to the driver.
            if mode == .follow {
                snapCameraToDriver()
            }
        }

        func handleRiderRecenterIfNeeded(token: UUID, riderCoord: CLLocationCoordinate2D?) {
            guard let map, let r = riderCoord else { return }
            if lastRiderRecenterToken != token {
                lastRiderRecenterToken = token
                let camera = GMSCameraPosition(
                    target: r,
                    zoom: max(map.camera.zoom, 15.8),
                    bearing: 0,
                    viewingAngle: 30
                )
                map.animate(with: GMSCameraUpdate.setCamera(camera))
            }
        }

        func install(on map: GMSMapView) {
            self.map = map

            driverMarker.groundAnchor = CGPoint(x: 0.5, y: 0.5)
            driverMarker.isFlat = true
            driverMarker.iconView = carView
            driverMarker.zIndex = 999
            driverMarker.tracksViewChanges = true
            carView.setScale(1.0)

            riderMarker.groundAnchor = CGPoint(x: 0.5, y: 0.5)
            riderMarker.icon = PremiumRiderIcon.make()
            riderMarker.zIndex = 50
            riderMarker.map = map

            routeLine.strokeWidth = 6.0
            routeLine.strokeColor = UIColor.white.withAlphaComponent(0.95)
            routeLine.spans = nil
            routeLine.geodesic = false
            routeLine.zIndex = 10

            // Always show the 3D car marker. If we don't have a real driver yet, we'll pin it to the rider location.
            driverMarker.position = map.camera.target
            driverMarker.opacity = 1.0
            driverMarker.map = map

            // Show rider marker.
            riderMarker.map = map

            routeLine.map = map

            startDisplayLinkIfNeeded()
        }

        func setRider(coord: CLLocationCoordinate2D) {
            riderMarker.position = coord
            if riderMarker.map == nil, let map { riderMarker.map = map }

            // If we don't have a real driver yet, pin the car to the rider so the UI still looks correct.
            if currentDriver == nil {
                driverMarker.position = coord
                driverMarker.rotation = 0
                driverMarker.opacity = 1.0
                driverMarker.tracksViewChanges = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                    self?.driverMarker.tracksViewChanges = false
                }
            }

            // Center once on the rider so we don't sit in Baghdad by default.
            if !hasCenteredOnce, currentDriver == nil, let map {
                hasCenteredOnce = true
                let camera = GMSCameraPosition(target: coord, zoom: 15.8, bearing: 0, viewingAngle: 30)
                map.moveCamera(GMSCameraUpdate.setCamera(camera))
            }
        }

        func setDriver(coord: CLLocationCoordinate2D, heading: Double?) {
            let newHeading: Double = {
                // 1) Uber-style: face the road/route direction whenever we have route points.
                if let h = routePreferredHeading, h.isFinite { return normalizeDegrees(h) }

                // 2) Fallback: use reported heading if valid.
                if let h = heading, h.isFinite { return normalizeDegrees(h) }

                // 3) Fallback: face movement direction.
                if let cur = currentDriver { return bearingDeg(from: cur, to: coord) }

                return currentHeading
            }()

            if currentDriver == nil {
                currentDriver = coord
                targetDriver = coord
                startCoord = coord
                endCoord = coord
                currentHeading = newHeading
                targetHeading = newHeading
                driverMarker.position = coord
                driverMarker.rotation = newHeading
                driverMarker.tracksViewChanges = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                    self?.driverMarker.tracksViewChanges = false
                }
                driverMarker.opacity = 1.0
                // Always snap to driver on first driver fix.
                snapCameraToDriver()
                return
            }

            targetDriver = coord
            targetHeading = newHeading

            startCoord = currentDriver
            endCoord = coord
            interpStartTime = CACurrentMediaTime()
        }

        func setRoute(points: [CLLocationCoordinate2D]) {
            guard let map else { return }
            latestRoutePoints = points

            if points.count >= 2 {
                let path = GMSMutablePath()
                for p in points { path.add(p) }
                routeLine.path = path

                // Prefer route tangent heading near the driver.
                let anchor = currentDriver ?? driverMarker.position
                if let h = headingAlongRoute(near: anchor, points: points) {
                    routePreferredHeading = h

                    // Smoothly rotate toward route direction even if driver coord isn't changing.
                    if let d = currentDriver {
                        targetHeading = h
                        startCoord = d
                        endCoord = d
                        interpStartTime = CACurrentMediaTime()
                    } else {
                        currentHeading = h
                        targetHeading = h
                        driverMarker.rotation = h
                    }
                }
            } else {
                routeLine.path = nil
                latestRoutePoints = []
                routePreferredHeading = nil
            }

            if !hasCenteredOnce, let d = currentDriver, let r = (riderMarker.map != nil ? riderMarker.position : nil) {
                hasCenteredOnce = true
                let bounds = GMSCoordinateBounds(coordinate: d, coordinate: r)
                map.animate(with: GMSCameraUpdate.fit(bounds, withPadding: 120))
            }
        }

        func mapView(_ mapView: GMSMapView, didChange position: GMSCameraPosition) {
            let z = position.zoom
            let s = max(0.78, min(1.18, CGFloat((z - 13.0) / 6.0 + 0.9)))
            if abs(s - zoomScale) > 0.01 {
                zoomScale = s
                carView.setScale(zoomScale)
            }
        }

        func mapView(_ mapView: GMSMapView, willMove gesture: Bool) {
            if gesture {
                // User panned/gestured: switch to Free and persist that in SwiftUI state.
                if followModeBinding.wrappedValue != .free {
                    followModeBinding.wrappedValue = .free
                }
                followMode = .free
            }
        }

        private func startDisplayLinkIfNeeded() {
            guard displayLink == nil else { return }
            let link = CADisplayLink(target: self, selector: #selector(tick))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
            link.add(to: .main, forMode: .common)
            displayLink = link
        }

        @objc private func tick() {
            guard let start = startCoord, let end = endCoord else { return }
            let now = CACurrentMediaTime()
            let t = clamp((now - interpStartTime) / interpDuration, 0, 1)
            let eased = easeOutCubic(t)

            let lat = start.latitude + (end.latitude - start.latitude) * eased
            let lng = start.longitude + (end.longitude - start.longitude) * eased
            let coord = CLLocationCoordinate2D(latitude: lat, longitude: lng)

            currentDriver = coord
            driverMarker.position = coord

            let heading = shortestAngleDegrees(from: currentHeading, to: targetHeading, t: eased)
            driverMarker.rotation = heading
            driverMarker.tracksViewChanges = true

            if t >= 0.999 {
                currentHeading = targetHeading
                startCoord = coord
                endCoord = coord
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                    self?.driverMarker.tracksViewChanges = false
                }
            }

            if followMode == .follow, let map {
                if now - lastCameraTick > 0.08 {
                    lastCameraTick = now
                    let camera = GMSCameraPosition(
                        target: coord,
                        zoom: max(map.camera.zoom, 15.5),
                        bearing: heading,
                        viewingAngle: 45
                    )
                    map.animate(to: camera)
                }
            }
        }

        private func snapCameraToDriver() {
            guard let map, let d = currentDriver else { return }
            let camera = GMSCameraPosition(target: d, zoom: 15.8, bearing: currentHeading, viewingAngle: 45)
            map.moveCamera(GMSCameraUpdate.setCamera(camera))
        }

        private func bearingDeg(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
            let lat1 = from.latitude * .pi / 180
            let lon1 = from.longitude * .pi / 180
            let lat2 = to.latitude * .pi / 180
            let lon2 = to.longitude * .pi / 180
            let dLon = lon2 - lon1
            let y = sin(dLon) * cos(lat2)
            let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
            let brng = atan2(y, x) * 180 / .pi
            return normalizeDegrees(brng)
        }

        private func normalizeDegrees(_ d: Double) -> Double {
            var x = d.truncatingRemainder(dividingBy: 360)
            if x < 0 { x += 360 }
            return x
        }

        private func clamp(_ v: Double, _ a: Double, _ b: Double) -> Double {
            max(a, min(b, v))
        }

        private func easeOutCubic(_ t: Double) -> Double {
            1 - pow(1 - t, 3)
        }

        private func shortestAngleDegrees(from: Double, to: Double, t: Double) -> Double {
            let delta = ((to - from + 540).truncatingRemainder(dividingBy: 360)) - 180
            return from + delta * t
        }
    }
}

private final class PremiumCarMarkerView: UIView {
    private let container = UIView()
    private let imageView = UIImageView()

private var baseSize: CGFloat = 64
override var intrinsicContentSize: CGSize {
    CGSize(width: baseSize + 10, height: baseSize + 10)
}

    override init(frame: CGRect) {
        super.init(frame: frame)

        // Google Maps sometimes ignores intrinsicContentSize for iconView; set an explicit size.
        let side = baseSize + 10
        self.frame = CGRect(x: 0, y: 0, width: side, height: side)
        self.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        isUserInteractionEnabled = false
        backgroundColor = .clear

        // No surrounding circle/glow — the car itself should read clearly.
        container.backgroundColor = .clear
        container.layer.cornerRadius = 0
        container.layer.borderWidth = 0
        container.layer.borderColor = nil
        container.layer.shadowColor = UIColor.black.cgColor
        container.layer.shadowOpacity = 0.0
        container.layer.shadowRadius = 0
        container.layer.shadowOffset = .zero

        imageView.contentMode = .scaleAspectFit
        imageView.image = PremiumCarMarkerView.premiumCarImage()
        imageView.tintColor = .white

        // Realistic drop shadow under the car (stronger + softer).
        imageView.layer.shadowColor = UIColor.black.cgColor
        imageView.layer.shadowOpacity = 0.72
        imageView.layer.shadowRadius = 18
        imageView.layer.shadowOffset = CGSize(width: 0, height: 20)

        addSubview(container)
        container.addSubview(imageView)

        container.translatesAutoresizingMaskIntoConstraints = false
        imageView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            container.centerXAnchor.constraint(equalTo: centerXAnchor),
            container.centerYAnchor.constraint(equalTo: centerYAnchor),
            container.widthAnchor.constraint(equalTo: widthAnchor),
            container.heightAnchor.constraint(equalTo: heightAnchor),

            // Make the car fill most of the iconView.
            imageView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            imageView.widthAnchor.constraint(equalTo: container.widthAnchor, multiplier: 0.92),
            imageView.heightAnchor.constraint(equalTo: container.heightAnchor, multiplier: 0.92)
        ])
    }

    required init?(coder: NSCoder) { return nil }


    func setHeading(_ degrees: Double) {
        // Rotation is applied on the GMSMarker (`driverMarker.rotation`).
        // Keep the iconView unrotated to avoid double-rotation artifacts.
        imageView.transform = .identity
    }

    func setScale(_ scale: CGFloat) {
        let s = max(0.75, min(1.22, scale))
        transform = CGAffineTransform(scaleX: s, y: s)
    }

    private static func premiumCarImage() -> UIImage? {
        // 1) Prefer a real top-down 3D asset if you add it to Assets.xcassets.
        if let img = UIImage(named: "car_topdown_3d") {
            return img.withRenderingMode(.alwaysOriginal)
        }

        // 2) Guaranteed fallback: draw a premium top-down car (V2) — angular modern shape, defined hood/trunk.
        let size: CGFloat = 320
        let r = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return r.image { ctx in
            let c = ctx.cgContext
            c.clear(CGRect(x: 0, y: 0, width: size, height: size))
            c.setAllowsAntialiasing(true)
            c.setShouldAntialias(true)

            let space = CGColorSpaceCreateDeviceRGB()

            // --- Ground shadow (separate from the car shape) ---
            c.saveGState()
            c.setShadow(offset: CGSize(width: 0, height: 28), blur: 48, color: UIColor.black.withAlphaComponent(0.44).cgColor)
            UIColor.black.withAlphaComponent(0.18).setFill()
            UIBezierPath(roundedRect: CGRect(x: 76, y: 108, width: 168, height: 166), cornerRadius: 76).fill()
            c.restoreGState()

            // --- Body silhouette (angular, real-car proportions) ---
            let bodyRect = CGRect(x: 74, y: 30, width: 172, height: 260)
            let x0 = bodyRect.minX
            let x1 = bodyRect.maxX
            let y0 = bodyRect.minY
            let y1 = bodyRect.maxY
            let midX = bodyRect.midX

            // Key stations (y)
            let noseY = y0
            let hoodY = y0 + 46
            let aPillarY = y0 + 72
            let cabinTopY = y0 + 86
            let cabinBotY = y1 - 86
            let cPillarY = y1 - 72
            let trunkY = y1 - 46
            let tailY = y1

            // Half-widths (x) at stations — widest at cabin shoulders
            let halfNose: CGFloat = 54
            let halfHood: CGFloat = 64
            let halfCabin: CGFloat = 80
            let halfTrunk: CGFloat = 66

            let body = UIBezierPath()
            // Start at top center
            body.move(to: CGPoint(x: midX, y: noseY))

            // Right side: nose -> hood (taper)
            body.addQuadCurve(to: CGPoint(x: midX + halfHood, y: hoodY), controlPoint: CGPoint(x: midX + halfNose, y: noseY + 8))

            // Hood -> A-pillar (expand to cabin)
            body.addQuadCurve(to: CGPoint(x: midX + halfCabin, y: aPillarY), controlPoint: CGPoint(x: midX + halfHood + 12, y: hoodY + 12))

            // Cabin top shoulder (slightly squared)
            body.addLine(to: CGPoint(x: midX + halfCabin, y: cabinTopY))

            // Mid cabin right side (mostly straight)
            body.addLine(to: CGPoint(x: midX + halfCabin, y: cabinBotY))

            // C-pillar -> trunk (taper)
            body.addLine(to: CGPoint(x: midX + halfCabin, y: cPillarY))
            body.addQuadCurve(to: CGPoint(x: midX + halfTrunk, y: trunkY), controlPoint: CGPoint(x: midX + halfCabin + 10, y: cPillarY + 10))

            // Trunk -> tail (rounded corners)
            body.addQuadCurve(to: CGPoint(x: midX, y: tailY), controlPoint: CGPoint(x: midX + halfTrunk, y: tailY - 10))

            // Left side: tail -> trunk
            body.addQuadCurve(to: CGPoint(x: midX - halfTrunk, y: trunkY), controlPoint: CGPoint(x: midX - halfTrunk, y: tailY - 10))

            // Trunk -> C-pillar
            body.addQuadCurve(to: CGPoint(x: midX - halfCabin, y: cPillarY), controlPoint: CGPoint(x: midX - halfCabin - 10, y: cPillarY + 10))

            // Cabin left side up
            body.addLine(to: CGPoint(x: midX - halfCabin, y: cabinBotY))
            body.addLine(to: CGPoint(x: midX - halfCabin, y: cabinTopY))

            // A-pillar -> hood
            body.addLine(to: CGPoint(x: midX - halfCabin, y: aPillarY))
            body.addQuadCurve(to: CGPoint(x: midX - halfHood, y: hoodY), controlPoint: CGPoint(x: midX - halfHood - 12, y: hoodY + 12))

            // Hood -> nose
            body.addQuadCurve(to: CGPoint(x: midX, y: noseY), controlPoint: CGPoint(x: midX - halfNose, y: noseY + 8))
            body.close()

            // --- Subtle wheel arch shading (no tires) ---
            // Adds realistic fender “cut” without drawing tires.
            let archAlpha: CGFloat = 0.22
            let leftArchX = x0 + 10
            let rightArchX = x1 - 30
            let archW: CGFloat = 20
            let archH: CGFloat = 42
            let frontArchY = y0 + 92
            let rearArchY = y1 - 134

            // --- Paint / body shading inside silhouette ---

            // --- Paint (graphite) with stronger contrast, not a tube ---
            c.saveGState()
            c.addPath(body.cgPath)
            c.clip()

            // Inner occlusion around wheel arches (no tires)
            c.setBlendMode(.multiply)
            UIColor.black.withAlphaComponent(archAlpha).setFill()
            UIBezierPath(roundedRect: CGRect(x: leftArchX, y: frontArchY, width: archW, height: archH), cornerRadius: 10).fill()
            UIBezierPath(roundedRect: CGRect(x: rightArchX, y: frontArchY, width: archW, height: archH), cornerRadius: 10).fill()
            UIBezierPath(roundedRect: CGRect(x: leftArchX, y: rearArchY, width: archW, height: archH), cornerRadius: 10).fill()
            UIBezierPath(roundedRect: CGRect(x: rightArchX, y: rearArchY, width: archW, height: archH), cornerRadius: 10).fill()

            // Hood bulge highlight (gives “real car” hood shape)
            c.setBlendMode(.screen)
            UIColor.white.withAlphaComponent(0.09).setFill()
            UIBezierPath(roundedRect: CGRect(x: x0 + 44, y: y0 + 18, width: bodyRect.width - 88, height: 54), cornerRadius: 18).fill()

            // Trunk deck highlight
            UIColor.white.withAlphaComponent(0.06).setFill()
            UIBezierPath(roundedRect: CGRect(x: x0 + 48, y: y1 - 72, width: bodyRect.width - 96, height: 44), cornerRadius: 16).fill()

            // Base metallic gradient
            let paintColors = [
                UIColor(white: 0.20, alpha: 1).cgColor,
                UIColor(white: 0.06, alpha: 1).cgColor,
                UIColor(white: 0.16, alpha: 1).cgColor,
                UIColor(white: 0.08, alpha: 1).cgColor
            ] as CFArray
            let paintLoc: [CGFloat] = [0.0, 0.40, 0.72, 1.0]
            if let grad = CGGradient(colorsSpace: space, colors: paintColors, locations: paintLoc) {
                c.drawLinearGradient(grad,
                                     start: CGPoint(x: bodyRect.minX, y: bodyRect.minY),
                                     end: CGPoint(x: bodyRect.maxX, y: bodyRect.maxY),
                                     options: [])
            }


            // Clean highlight stripe (modern car highlight)
            c.setBlendMode(.screen)
            UIColor.white.withAlphaComponent(0.10).setFill()
            UIBezierPath(roundedRect: CGRect(x: bodyRect.minX + 26, y: bodyRect.minY + 18, width: 8, height: bodyRect.height - 36), cornerRadius: 4).fill()
            UIColor.white.withAlphaComponent(0.05).setFill()
            UIBezierPath(roundedRect: CGRect(x: bodyRect.maxX - 36, y: bodyRect.minY + 26, width: 6, height: bodyRect.height - 52), cornerRadius: 3).fill()

            c.restoreGState()

            // Body outline
            UIColor.white.withAlphaComponent(0.10).setStroke()
            body.lineWidth = 2.0
            body.stroke()

            // --- Roof + panoramic glass (3 panels like real roof) ---
            let roofOuter = UIBezierPath(roundedRect: CGRect(x: bodyRect.minX + 28, y: bodyRect.minY + 64, width: bodyRect.width - 56, height: bodyRect.height - 128), cornerRadius: 26)
            UIColor.black.withAlphaComponent(0.26).setFill()
            roofOuter.fill()

            let glassRect = CGRect(x: bodyRect.minX + 36, y: bodyRect.minY + 72, width: bodyRect.width - 72, height: bodyRect.height - 144)
            let glass = UIBezierPath(roundedRect: glassRect, cornerRadius: 24)
            c.saveGState()
            c.addPath(glass.cgPath)
            c.clip()

            let glassColors = [
                UIColor(red: 0.58, green: 0.84, blue: 1.00, alpha: 0.26).cgColor,
                UIColor(red: 0.10, green: 0.22, blue: 0.36, alpha: 0.22).cgColor
            ] as CFArray
            let glassLoc: [CGFloat] = [0.0, 1.0]
            if let g = CGGradient(colorsSpace: space, colors: glassColors, locations: glassLoc) {
                c.drawLinearGradient(g,
                                     start: CGPoint(x: glassRect.minX, y: glassRect.minY),
                                     end: CGPoint(x: glassRect.maxX, y: glassRect.maxY),
                                     options: [])
            }

            // Panoramic roof panel dividers (vertical)
            c.setBlendMode(.multiply)
            UIColor.black.withAlphaComponent(0.28).setFill()
            UIBezierPath(roundedRect: CGRect(x: glassRect.minX + glassRect.width * 0.33 - 2, y: glassRect.minY + 6, width: 4, height: glassRect.height - 12), cornerRadius: 2).fill()
            UIBezierPath(roundedRect: CGRect(x: glassRect.minX + glassRect.width * 0.66 - 2, y: glassRect.minY + 6, width: 4, height: glassRect.height - 12), cornerRadius: 2).fill()

            // Reflections
            c.setBlendMode(.screen)
            UIColor.white.withAlphaComponent(0.12).setFill()
            UIBezierPath(roundedRect: CGRect(x: glassRect.minX + 10, y: glassRect.minY + 14, width: 8, height: glassRect.height - 28), cornerRadius: 4).fill()
            UIColor.white.withAlphaComponent(0.06).setFill()
            UIBezierPath(roundedRect: CGRect(x: glassRect.maxX - 16, y: glassRect.minY + 22, width: 6, height: glassRect.height - 44), cornerRadius: 3).fill()

            c.restoreGState()

            // Roof frame stroke
            UIColor.white.withAlphaComponent(0.10).setStroke()
            roofOuter.lineWidth = 1.6
            roofOuter.stroke()

            // --- Hood & trunk seam lines ---
            UIColor.white.withAlphaComponent(0.06).setStroke()
            let hoodLine = UIBezierPath()
            hoodLine.move(to: CGPoint(x: x0 + 26, y: hoodY + 6))
            hoodLine.addLine(to: CGPoint(x: x1 - 26, y: hoodY + 6))
            hoodLine.lineWidth = 1.2
            hoodLine.stroke()

            let trunkLine = UIBezierPath()
            trunkLine.move(to: CGPoint(x: x0 + 26, y: trunkY - 6))
            trunkLine.addLine(to: CGPoint(x: x1 - 26, y: trunkY - 6))
            trunkLine.lineWidth = 1.2
            trunkLine.stroke()


            // --- Lights (more realistic clusters) ---
            // Front DRLs (shorter)
            UIColor.white.withAlphaComponent(0.18).setFill()
            UIBezierPath(roundedRect: CGRect(x: x0 + 34, y: y0 + 10, width: 18, height: 7), cornerRadius: 3.5).fill()
            UIBezierPath(roundedRect: CGRect(x: x1 - 52, y: y0 + 10, width: 18, height: 7), cornerRadius: 3.5).fill()

            // Rear lights (shorter clusters)
            UIColor.red.withAlphaComponent(0.30).setFill()
            UIBezierPath(roundedRect: CGRect(x: x0 + 31, y: y1 - 22, width: 24, height: 11), cornerRadius: 5.5).fill()
            UIBezierPath(roundedRect: CGRect(x: x1 - 55, y: y1 - 22, width: 24, height: 11), cornerRadius: 5.5).fill()

            // Inner cut (shorter)
            c.setBlendMode(.multiply)
            UIColor.black.withAlphaComponent(0.22).setFill()
            UIBezierPath(roundedRect: CGRect(x: x0 + 35, y: y1 - 20, width: 14, height: 7), cornerRadius: 3.5).fill()
            UIBezierPath(roundedRect: CGRect(x: x1 - 49, y: y1 - 20, width: 14, height: 7), cornerRadius: 3.5).fill()

            // Bright rim (shorter)
            c.setBlendMode(.screen)
            UIColor.red.withAlphaComponent(0.18).setFill()
            UIBezierPath(roundedRect: CGRect(x: x0 + 31, y: y1 - 22, width: 24, height: 4), cornerRadius: 2).fill()
            UIBezierPath(roundedRect: CGRect(x: x1 - 55, y: y1 - 22, width: 24, height: 4), cornerRadius: 2).fill()

            // Subtle rear diffuser shadow
            c.saveGState()
            c.addPath(body.cgPath)
            c.clip()
            c.setBlendMode(.multiply)
            UIColor.black.withAlphaComponent(0.22).setFill()
            UIBezierPath(roundedRect: CGRect(x: midX - 36, y: y1 - 34, width: 72, height: 12), cornerRadius: 6).fill()
            c.restoreGState()
        }
    }
}

private enum PremiumPinIcon {
    static func make() -> UIImage? {
        let size: CGFloat = 26
        let pad: CGFloat = 12
        let total = size + pad * 2
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: total, height: total))
        return renderer.image { ctx in
            let c = ctx.cgContext
            c.setFillColor(UIColor.black.withAlphaComponent(0.85).cgColor)
            c.addEllipse(in: CGRect(x: pad, y: pad, width: size, height: size))
            c.fillPath()

            c.setFillColor(UIColor.white.cgColor)
            c.addEllipse(in: CGRect(x: pad + size * 0.33, y: pad + size * 0.33, width: size * 0.34, height: size * 0.34))
            c.fillPath()

            c.setShadow(offset: CGSize(width: 0, height: 8), blur: 14, color: UIColor.black.withAlphaComponent(0.35).cgColor)
        }
    }
}

private enum PremiumRiderIcon {
    static func make() -> UIImage? {
        let size: CGFloat = 34
        let pad: CGFloat = 12
        let total = size + pad * 2
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: total, height: total))
        return renderer.image { _ in
            // Outer glow ring
            let ring = UIBezierPath(ovalIn: CGRect(x: pad - 3, y: pad - 3, width: size + 6, height: size + 6))
            UIColor.systemPink.withAlphaComponent(0.55).setFill()
            ring.fill()

            // Inner dark disc
            let disc = UIBezierPath(ovalIn: CGRect(x: pad, y: pad, width: size, height: size))
            UIColor.black.withAlphaComponent(0.82).setFill()
            disc.fill()

            // Person glyph
            let glyphConfig = UIImage.SymbolConfiguration(pointSize: 16, weight: .bold)
            let glyph = UIImage(systemName: "person.fill", withConfiguration: glyphConfig)?.withRenderingMode(.alwaysOriginal)
            glyph?.withTintColor(.white, renderingMode: .alwaysOriginal)
                .draw(in: CGRect(x: (total - 18) / 2, y: (total - 18) / 2, width: 18, height: 18))
        }
    }
}

private final class SupabaseRealtimeLite {
    struct DriverUpdate {
        var coord: CLLocationCoordinate2D
        var headingDeg: Double?
        var speedMps: Double?
    }

    private let supabaseURL: URL
    private let anonKey: String

    private var socket: URLSessionWebSocketTask?
    private var session: URLSession = URLSession(configuration: .default)

    private var heartbeatTimer: Timer?
    private var reconnectTimer: Timer?
    private var isPaused: Bool = false

    private var refCounter: Int = 1
    private var joinRef: String?
    private var rideId: String?

    var onDriverUpdate: ((DriverUpdate) -> Void)?
    var onConnectionState: ((VM.ConnState) -> Void)?

    init(supabaseURL: URL, anonKey: String) {
        self.supabaseURL = supabaseURL
        self.anonKey = anonKey
    }

    func start(rideId: String) {
        self.rideId = rideId
        connect()
    }

    func stop() {
        rideId = nil
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        onConnectionState?(.offline)
    }

    func pause() {
        isPaused = true
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        onConnectionState?(.offline)
    }

    func resume() {
        guard isPaused else { return }
        isPaused = false
        guard let rideId else { return }
        start(rideId: rideId)
    }

    private func connect() {
        guard !isPaused, let rideId else { return }
        onConnectionState?(.connecting)

        let host = supabaseURL.host ?? ""
        var comps = URLComponents()
        comps.scheme = "wss"
        comps.host = host
        comps.path = "/realtime/v1/websocket"
        comps.queryItems = [
            URLQueryItem(name: "apikey", value: anonKey),
            URLQueryItem(name: "vsn", value: "1.0.0")
        ]

        guard let url = comps.url else {
            onConnectionState?(.offline)
            return
        }

        let task = session.webSocketTask(with: url)
        socket = task
        task.resume()

        startHeartbeat()
        sendJoin(rideId: rideId)
        listen()

        reconnectTimer?.invalidate()
        reconnectTimer = nil
    }

    private func startHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 25.0, repeats: true) { [weak self] _ in
            self?.sendHeartbeat()
        }
        RunLoop.main.add(heartbeatTimer!, forMode: .common)
    }

    private func scheduleReconnect() {
        guard reconnectTimer == nil, !isPaused else { return }
        onConnectionState?(.reconnecting)
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: false) { [weak self] _ in
            self?.reconnectTimer = nil
            self?.connect()
        }
        RunLoop.main.add(reconnectTimer!, forMode: .common)
    }

    private func sendJoin(rideId: String) {
        let topic = "realtime:public:rides"
        let payload: [String: Any] = [
            "config": [
                "broadcast": ["ack": false],
                "presence": ["key": ""],
                "postgres_changes": [[
                    "event": "UPDATE",
                    "schema": "public",
                    "table": "rides",
                    "filter": "id=eq.\(rideId)"
                ]]
            ]
        ]
        let ref = nextRef()
        joinRef = ref
        send(
            topic: topic,
            event: "phx_join",
            payload: payload,
            ref: ref
        )
    }

    private func sendHeartbeat() {
        send(topic: "phoenix", event: "heartbeat", payload: [:], ref: nextRef())
    }

    private func listen() {
        socket?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure:
                self.onConnectionState?(.offline)
                self.scheduleReconnect()
            case .success(let msg):
                switch msg {
                case .string(let text):
                    self.handleIncoming(text)
                default:
                    break
                }
                self.listen()
            }
        }
    }

    private func handleIncoming(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let event = json["event"] as? String
        else { return }

        if event == "phx_reply" {
            if let ref = json["ref"] as? String, ref == joinRef,
               let payload = json["payload"] as? [String: Any],
               let status = payload["status"] as? String,
               status == "ok" {
                onConnectionState?(.connected)
            }
            return
        }

        if event == "postgres_changes" {
            guard let payload = json["payload"] as? [String: Any] else { return }

            // Supabase Realtime payload shape differs across versions.
            // Try common locations for the row record.
            let record: [String: Any]? = {
                if let r = payload["record"] as? [String: Any] { return r }
                if let data = payload["data"] as? [String: Any] {
                    if let r = data["record"] as? [String: Any] { return r }
                    if let r = data["new"] as? [String: Any] { return r }
                    if let r = data["new_record"] as? [String: Any] { return r }
                }
                if let r = payload["new"] as? [String: Any] { return r }
                if let r = payload["new_record"] as? [String: Any] { return r }
                return nil
            }()

            guard let record else { return }

            let lat = record.doubleAnyOptional("driver_lat", "driverLat")
            let lng = record.doubleAnyOptional("driver_lng", "driverLng")
            guard let lat, let lng, isValid(lat: lat, lng: lng) else { return }
            // Match your schema: heading, speed.
            let heading = record.doubleAnyOptional("driver_heading", "heading", "bearing", "course")
            let speed = record.doubleAnyOptional("driver_speed_mps", "speed", "speed_mps", "speedMps")

            onDriverUpdate?(DriverUpdate(
                coord: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                headingDeg: heading,
                speedMps: speed
            ))
        }
    }

    private func send(topic: String, event: String, payload: [String: Any], ref: String) {
        guard let socket else { return }
        let frame: [String: Any] = [
            "topic": topic,
            "event": event,
            "payload": payload,
            "ref": ref
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: frame),
              let text = String(data: data, encoding: .utf8) else { return }
        socket.send(.string(text)) { [weak self] err in
            if err != nil {
                self?.onConnectionState?(.offline)
                self?.scheduleReconnect()
            }
        }
    }

    private func nextRef() -> String {
        refCounter += 1
        return String(refCounter)
    }

    private func isValid(lat: Double, lng: Double) -> Bool {
        if lat.isNaN || lng.isNaN { return false }
        if lat < -90 || lat > 90 { return false }
        if lng < -180 || lng > 180 { return false }
        if abs(lat) < 0.000001 && abs(lng) < 0.000001 { return false }
        return true
    }
}

private enum GoogleDirectionsLite {
    struct Result {
        var points: [CLLocationCoordinate2D]
        var distanceMeters: Double?
        var durationSeconds: Int?
    }

    static func fetchRoute(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D, apiKey: String?) async -> Result? {
        guard let apiKey, !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("[Directions] missing apiKey")
            return nil
        }

        let origin = "\(from.latitude),\(from.longitude)"
        let dest = "\(to.latitude),\(to.longitude)"

        guard let url = URL(string: "https://maps.googleapis.com/maps/api/directions/json?origin=\(origin)&destination=\(dest)&mode=driving&key=\(apiKey)") else {
            print("[Directions] bad url")
            return nil
        }

        do {
            let (data, resp) = try await URLSession.shared.data(from: url)
            guard let http = resp as? HTTPURLResponse else {
                print("[Directions] no HTTPURLResponse")
                return nil
            }
            guard (200...299).contains(http.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? ""
                print("[Directions] http=\(http.statusCode) body=\(body)")
                return nil
            }

            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("[Directions] json parse failed")
                return nil
            }

            let status = (obj["status"] as? String) ?? ""
            if status != "OK" {
                let err = (obj["error_message"] as? String) ?? ""
                print("[Directions] status=\(status) err=\(err)")
                return nil
            }

            guard let routes = obj["routes"] as? [[String: Any]], let first = routes.first else {
                print("[Directions] no routes")
                return nil
            }

            var coords: [CLLocationCoordinate2D] = []
            if let overview = first["overview_polyline"] as? [String: Any],
               let points = overview["points"] as? String {
                coords = Polyline.decode(points)
            }

            var dist: Double?
            var dur: Int?
            if let legs = first["legs"] as? [[String: Any]], let leg = legs.first {
                if let d = leg["distance"] as? [String: Any], let v = d["value"] as? Double { dist = v }
                if let t = leg["duration"] as? [String: Any], let v = t["value"] as? Int { dur = v }
            }

            if coords.count >= 2 {
                return Result(points: coords, distanceMeters: dist, durationSeconds: dur)
            } else {
                print("[Directions] decoded polyline too short")
                return nil
            }
        } catch {
            print("[Directions] error: \(error)")
            return nil
        }
    }
}

private enum Polyline {
    static func decode(_ encoded: String) -> [CLLocationCoordinate2D] {
        var coords: [CLLocationCoordinate2D] = []
        let bytes = Array(encoded.utf8)
        var idx = 0
        var lat = 0
        var lng = 0

        while idx < bytes.count {
            var b = 0
            var shift = 0
            var result = 0

            repeat {
                b = Int(bytes[idx]) - 63
                idx += 1
                result |= (b & 0x1F) << shift
                shift += 5
            } while b >= 0x20 && idx < bytes.count

            let dlat = ((result & 1) != 0) ? ~(result >> 1) : (result >> 1)
            lat += dlat

            shift = 0
            result = 0

            repeat {
                b = Int(bytes[idx]) - 63
                idx += 1
                result |= (b & 0x1F) << shift
                shift += 5
            } while b >= 0x20 && idx < bytes.count

            let dlng = ((result & 1) != 0) ? ~(result >> 1) : (result >> 1)
            lng += dlng

            let clat = Double(lat) / 1e5
            let clng = Double(lng) / 1e5
            coords.append(CLLocationCoordinate2D(latitude: clat, longitude: clng))
        }
        return coords
    }
}

private enum DistanceFormatter {
    static func pretty(meters: Double, unitSystem: VM.UnitSystem) -> String {
        let m = max(0, meters)

        if unitSystem.isImperial {
            let miles = m / 1609.344
            if miles >= 0.2 { return String(format: "%.1f mi", miles) }
            let feet = m * 3.280839895
            return "\(Int(feet.rounded())) ft"
        } else {
            if m >= 1000 { return String(format: "%.1f km", m / 1000.0) }
            return "\(Int(m.rounded())) m"
        }
    }
}

private enum TimeFormatter {
    static func pretty(seconds: Int) -> String {
        let s = max(0, seconds)
        let m = s / 60
        if m < 60 {
            return "\(max(1, m)) min"
        }
        let h = m / 60
        let rm = m % 60
        return "\(h)h \(rm)m"
    }
}

private extension Dictionary where Key == String, Value == Any {
    func doubleAny(_ keys: String...) -> Double {
        for k in keys {
            if let v = self[k] as? Double { return v }
            if let v = self[k] as? Int { return Double(v) }
            if let v = self[k] as? String, let d = Double(v) { return d }
        }
        return 0
    }

    func doubleAnyOptional(_ keys: String...) -> Double? {
        for k in keys {
            if let v = self[k] as? Double, v.isFinite { return v }
            if let v = self[k] as? Int { return Double(v) }
            if let v = self[k] as? String, let d = Double(v), d.isFinite { return d }
        }
        return nil
    }

    func stringAny(_ keys: String...) -> String {
        for k in keys {
            if let v = self[k] as? String { return v }
            if let v = self[k] as? Int { return String(v) }
            if let v = self[k] as? Double { return String(v) }
        }
        return ""
    }

    func stringAnyOptional(_ keys: String...) -> String? {
        for k in keys {
            if let v = self[k] as? String { return v.isEmpty ? nil : v }
            if let v = self[k] as? Int { return String(v) }
            if let v = self[k] as? Double { return String(v) }
        }
        return nil
    }
}

private struct BottomSheet<Content: View>: View {
    @Binding var isExpanded: Bool
    let collapsedHeight: CGFloat
    let expandedHeight: CGFloat
    let content: Content

    @State private var dragY: CGFloat = 0

    init(
        isExpanded: Binding<Bool>,
        collapsedHeight: CGFloat,
        expandedHeight: CGFloat,
        @ViewBuilder content: () -> Content
    ) {
        _isExpanded = isExpanded
        self.collapsedHeight = collapsedHeight
        self.expandedHeight = expandedHeight
        self.content = content()
    }

    var body: some View {
        let height = isExpanded ? expandedHeight : collapsedHeight
        VStack(spacing: 0) {
            Grabber()
                .padding(.top, 10)
                .padding(.bottom, 8)

            content
        }
        .frame(maxWidth: .infinity)
        .background(BlurView(style: .systemUltraThinMaterialDark))
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.55), radius: 26, x: 0, y: 18)
        .offset(y: max(0, (expandedHeight - height)) + dragY)
        .gesture(
            DragGesture(minimumDistance: 4, coordinateSpace: .global)
                .onChanged { v in
                    dragY = max(-18, v.translation.height)
                }
                .onEnded { v in
                    let dy = v.translation.height
                    let shouldExpand = dy < -30
                    let shouldCollapse = dy > 30
                    withAnimation(.spring(response: 0.33, dampingFraction: 0.9)) {
                        if shouldExpand { isExpanded = true }
                        else if shouldCollapse { isExpanded = false }
                        dragY = 0
                    }
                }
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
        .animation(.spring(response: 0.33, dampingFraction: 0.9), value: isExpanded)
    }
}

private struct Grabber: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 999, style: .continuous)
            .fill(Color.white.opacity(0.22))
            .frame(width: 44, height: 5)
    }
}

private struct BlurView: UIViewRepresentable {
    let style: UIBlurEffect.Style
    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: style))
    }
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}
}

private struct CircleButton: View {
    let systemName: String
    let background: UIColor
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 42, height: 42)
                .background(Color(background))
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.10), lineWidth: 1))
                .shadow(color: .black.opacity(0.4), radius: 14, x: 0, y: 10)
        }
        .buttonStyle(.plain)
    }
}

private struct SegmentedPill: View {
    let leftTitle: String
    let rightTitle: String
    let isLeftSelected: Bool
    let onChange: (Bool) -> Void

    var body: some View {
        HStack(spacing: 0) {
            segment(title: leftTitle, selected: isLeftSelected) { onChange(true) }
            segment(title: rightTitle, selected: !isLeftSelected) { onChange(false) }
        }
        .padding(4)
        .background(Color.black.opacity(0.35))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 18, x: 0, y: 12)
    }

    private func segment(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(selected ? .black : .white.opacity(0.85))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(minWidth: 64)
                .background(
                    Group {
                        if selected {
                            Color.white
                                .clipShape(Capsule())
                        } else {
                            Color.clear
                        }
                    }
                )
        }
        .buttonStyle(.plain)
    }
}

private struct DriverAvatar: View {
    let name: String
    let photoURL: String?

    var body: some View {
        let initials = name.split(separator: " ").prefix(2).map { $0.prefix(1) }.joined()
        let fallback = initials.isEmpty ? "D" : String(initials)

        ZStack {
            Circle()
                .fill(Color.white.opacity(0.08))
                .overlay(Circle().stroke(Color.white.opacity(0.10), lineWidth: 1))

            if let s = photoURL, let url = URL(string: s) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    default:
                        Text(fallback)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .clipShape(Circle())
            } else {
                Text(fallback)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
            }
        }
        .frame(width: 48, height: 48)
        .clipped()
    }
}

private struct RatingBadge: View {
    let rating: Double
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "star.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.yellow)
            Text(String(format: "%.2f", rating))
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.08))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1))
    }
}

private struct InfoPill: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.09))
                    .overlay(Circle().stroke(Color.white.opacity(0.10), lineWidth: 1))
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.92))
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                Text(value)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }
}

private struct ActionButton: View {
    enum Style { case primary, secondary }
    let title: String
    let systemName: String
    let style: Style
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemName)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundColor(style == .primary ? .black : .white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(style == .primary ? Color.white : Color.white.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(style == .primary ? 0.0 : 0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct StatusChip: View {
    enum Kind { case good, warning, bad, neutral }
    let text: String
    let kind: Kind

    var body: some View {
        let c: Color = {
            switch kind {
            case .good: return Color.green.opacity(0.9)
            case .warning: return Color.orange.opacity(0.95)
            case .bad: return Color.red.opacity(0.95)
            case .neutral: return Color.white.opacity(0.7)
            }
        }()
        HStack(spacing: 8) {
            Circle().fill(c).frame(width: 7, height: 7)
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.07))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1))
    }
}


private struct RideChatView: View {
    struct Message: Identifiable, Equatable {
        let id: String
        let sender: String
        let body: String
        let createdAt: Date?

        var isLocal: Bool { sender.lowercased() == localSender.lowercased() }

        // Local sender is injected via outer view (captured through static var below)
        private static var localSender: String = "rider"
        static func setLocalSender(_ s: String) { localSender = s }
        private var localSender: String { Self.localSender }
    }

    let rideId: String
    let supabaseURL: URL
    let supabaseAnonKey: String
    let localSender: String

    private var rideIdNormalized: String { rideId.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var rideIdUUID: UUID? { UUID(uuidString: rideIdNormalized) }

    @Environment(\.dismiss) private var dismiss

    @State private var messages: [Message] = []
    @State private var composing: String = ""
    @State private var isSending: Bool = false
    @State private var pollTask: Task<Void, Never>?
    @State private var errorText: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider().opacity(0.2)

            messagesList

            Divider().opacity(0.2)

            composer
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            Message.setLocalSender(localSender)
            startPolling()
        }
        .onDisappear {
            pollTask?.cancel()
            pollTask = nil
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 42, height: 42)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Text("Chat")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)

                Spacer()
            }

            if let errorText {
                Text(errorText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.red.opacity(0.95))
                    .lineLimit(6)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(messages) { m in
                        messageRow(m)
                            .id(m.id)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .onChange(of: messages) { _, newValue in
                guard let last = newValue.last else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private func messageRow(_ m: Message) -> some View {
        HStack {
            if m.isLocal { Spacer(minLength: 40) }

            Text(m.body)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(m.isLocal ? Color.white.opacity(0.18) : Color.white.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )

            if !m.isLocal { Spacer(minLength: 40) }
        }
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("Message…", text: $composing, axis: .vertical)
                .textInputAutocapitalization(.sentences)
                .disableAutocorrection(false)
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )

            Button {
                Task { await send() }
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white)
                    if isSending {
                        ProgressView()
                            .tint(.black)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.black)
                    }
                }
                .frame(width: 52, height: 44)
            }
            .buttonStyle(.plain)
            .disabled(isSending || composing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity((isSending || composing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ? 0.55 : 1.0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                await fetchMessages()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private func fetchMessages() async {
        guard let url = messagesGETURL() else { return }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 12

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return }
            guard let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }

            let parsed: [Message] = arr.compactMap { row in
                guard let id = row["id"] as? String else { return nil }
                let sender = (row["sender"] as? String) ?? ""
                let body = (row["body"] as? String) ?? ""
                let createdAt: Date? = {
                    if let s = row["created_at"] as? String {
                        let f = ISO8601DateFormatter()
                        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                        return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
                    }
                    return nil
                }()
                return Message(id: id, sender: sender, body: body, createdAt: createdAt)
            }

            await MainActor.run {
                if parsed != self.messages {
                    self.messages = parsed
                }
            }
        } catch {
            // ignore
        }
    }

    private func parsePostgrestError(_ data: Data) -> String {
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return String(data: data, encoding: .utf8) ?? ""
        }
        let code = (obj["code"] as? String) ?? ""
        let msg = (obj["message"] as? String) ?? ""
        let details = (obj["details"] as? String) ?? ""
        let hint = (obj["hint"] as? String) ?? ""

        var parts: [String] = []
        if !code.isEmpty { parts.append("code=\(code)") }
        if !msg.isEmpty { parts.append(msg) }
        if !details.isEmpty { parts.append(details) }
        if !hint.isEmpty { parts.append("hint: \(hint)") }
        return parts.joined(separator: " • ")
    }

    private func send() async {
        let text = composing.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard let url = messagesPOSTURL() else { return }

        await MainActor.run {
            isSending = true
            errorText = nil
        }

        guard rideIdUUID != nil else {
            await MainActor.run {
                isSending = false
                errorText = "Ride ID is not a UUID. Pass Supabase rides.id (uuid) into DriverTrackingView."
            }
            return
        }

        let newId = UUID().uuidString
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let createdAt = iso.string(from: Date())

        let payload: [[String: Any]] = [[
            "id": newId,
            "ride_id": rideIdNormalized,
            "sender": localSender,
            "sender_id": localSender,
            "sender_role": localSender,
            "body": text,
            "created_at": createdAt
        ]]

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        // Be explicit about schema (helps on some setups)
        req.setValue("public", forHTTPHeaderField: "Accept-Profile")
        req.setValue("public", forHTTPHeaderField: "Content-Profile")
        // Ask PostgREST to return inserted row(s)
        req.setValue("return=representation", forHTTPHeaderField: "Prefer")
        req.timeoutInterval = 12

        do {
            req.httpBody = try JSONSerialization.data(withJSONObject: payload)
            let (data, resp) = try await URLSession.shared.data(for: req)

            guard let http = resp as? HTTPURLResponse else {
                await MainActor.run {
                    isSending = false
                    errorText = "Send failed (no HTTP response)"
                }
                return
            }

            guard (200...299).contains(http.statusCode) else {
                let parsed = parsePostgrestError(data)
                print("[RideChatView] send failed status=\(http.statusCode) body=\(String(data: data, encoding: .utf8) ?? "")")

                await MainActor.run {
                    isSending = false
                    if http.statusCode == 401 {
                        errorText = "Not authorized (401). \(parsed)"
                    } else if http.statusCode == 403 {
                        errorText = "Blocked by RLS/policy (403). \(parsed)"
                    } else if http.statusCode == 400 {
                        errorText = "Bad request (400). \(parsed)"
                    } else {
                        errorText = "Send failed (\(http.statusCode)). \(parsed)"
                    }
                }
                return
            }

            // Parse returned row (if present) and append immediately.
            if let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]],
               let row = arr.first {

                let id = (row["id"] as? String) ?? newId
                let sender = (row["sender"] as? String) ?? localSender
                let body = (row["body"] as? String) ?? text
                let createdAt: Date? = {
                    if let s = row["created_at"] as? String {
                        let f = ISO8601DateFormatter()
                        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                        return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
                    }
                    return nil
                }()

                await MainActor.run {
                    composing = ""
                    isSending = false
                    if !messages.contains(where: { $0.id == id }) {
                        messages.append(Message(id: id, sender: sender, body: body, createdAt: createdAt))
                    }
                }
            } else {
                await MainActor.run {
                    composing = ""
                    isSending = false
                }
            }

            // Push notify the other party (best-effort). Works for rider -> driver and driver -> rider.
            let msgText = text
            Task {
                await notifyOtherPartyPush(messageText: msgText)
            }

            // Sync.
            await fetchMessages()
        } catch {
            print("[RideChatView] send error: \(error)")
            await MainActor.run {
                isSending = false
                errorText = "Send error: \(String(describing: error))"
            }
        }
    }

    // MARK: - URLs
    private func messagesGETURL() -> URL? {
        // /rest/v1/messages?select=id,sender,body,created_at&ride_id=eq.<rideId>&order=created_at.asc&limit=200
        var comps = URLComponents(url: supabaseURL.appendingPathComponent("rest/v1/messages"), resolvingAgainstBaseURL: false)
        comps?.queryItems = [
            URLQueryItem(name: "select", value: "id,sender,body,created_at"),
            URLQueryItem(name: "ride_id", value: "eq.\(rideIdNormalized)"),
            URLQueryItem(name: "order", value: "created_at.asc"),
            URLQueryItem(name: "limit", value: "200")
        ]
        return comps?.url
    }

    private func messagesPOSTURL() -> URL? {
        // /rest/v1/messages?select=id
        var comps = URLComponents(url: supabaseURL.appendingPathComponent("rest/v1/messages"), resolvingAgainstBaseURL: false)
        comps?.queryItems = [
            URLQueryItem(name: "select", value: "id")
        ]
        return comps?.url
    }

    private func notifyFunctionURL() -> URL {
        // /functions/v1/notify-new-message
        supabaseURL.appendingPathComponent("functions/v1/notify-new-message")
    }

    // MARK: - Push notify the other party (best-effort)
    private func notifyOtherPartyPush(messageText: String) async {
        // Determine who to notify.
        let senderLower = localSender.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let toUserId: String?
        if senderLower == "driver" {
            toUserId = await fetchRiderIdForRide()
        } else if senderLower == "rider" {
            toUserId = await fetchDriverIdForRide()
        } else {
            toUserId = nil
        }

        guard let toUserId, !toUserId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        var req = URLRequest(url: notifyFunctionURL())
        req.httpMethod = "POST"
        req.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 12

        let payload: [String: Any] = [
            "to_user_id": toUserId,
            "title": "New message",
            "body": messageText,
            "data": [
                "type": "chat",
                "ride_id": rideIdNormalized,
                "sender": localSender
            ]
        ]

        do {
            req.httpBody = try JSONSerialization.data(withJSONObject: payload)
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? ""
                print("[RideChatView] notify push failed status=\((resp as? HTTPURLResponse)?.statusCode ?? -1) body=\(body)")
                return
            }
        } catch {
            print("[RideChatView] notify push error: \(error)")
        }
    }

    private func fetchDriverIdForRide() async -> String? {
        // /rest/v1/rides?select=driver_id&id=eq.<rideId>&limit=1
        var comps = URLComponents(url: supabaseURL.appendingPathComponent("rest/v1/rides"), resolvingAgainstBaseURL: false)
        comps?.queryItems = [
            URLQueryItem(name: "select", value: "driver_id"),
            URLQueryItem(name: "id", value: "eq.\(rideIdNormalized)"),
            URLQueryItem(name: "limit", value: "1")
        ]
        guard let url = comps?.url else { return nil }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 12

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }
            guard let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  let row = arr.first,
                  let driverId = row["driver_id"] as? String,
                  !driverId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return nil }
            return driverId
        } catch {
            return nil
        }
    }

    private func fetchRiderIdForRide() async -> String? {
        // /rest/v1/rides?select=rider_id&id=eq.<rideId>&limit=1
        var comps = URLComponents(url: supabaseURL.appendingPathComponent("rest/v1/rides"), resolvingAgainstBaseURL: false)
        comps?.queryItems = [
            URLQueryItem(name: "select", value: "rider_id"),
            URLQueryItem(name: "id", value: "eq.\(rideIdNormalized)"),
            URLQueryItem(name: "limit", value: "1")
        ]
        guard let url = comps?.url else { return nil }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 12

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }
            guard let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  let row = arr.first,
                  let riderId = row["rider_id"] as? String,
                  !riderId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return nil }
            return riderId
        } catch {
            return nil
        }
    }
}

