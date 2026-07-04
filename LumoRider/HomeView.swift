import SwiftUI
import MapKit
import CoreLocation
import Combine
import PhotosUI
import UIKit
import FirebaseAuth
import Stripe
import SafariServices
import FirebaseFirestore

struct HomeView: View {
    @StateObject private var rideService = SupabaseRideService.shared
    @State private var isNow: Bool = true
    

    // Scheduled-ride indicator (set when a scheduled ride is created)
    @AppStorage("lumo_has_scheduled_ride") private var hasScheduledRide: Bool = false
    @AppStorage("lumo_scheduled_ride_id") private var scheduledRideId: String = ""

    // Active ride id (set by SupabaseRideService.beginObservingRideStatus)
    // Passing this into GoogleMapView ensures the rider map subscribes to driver_locations for the active ride
    @AppStorage("lumo_active_ride_id") private var activeRideId: String = ""

    // Scheduled-ride details (persisted so the pill can open the exact trip)
    @AppStorage("lumo_scheduled_pickup_address") private var scheduledPickupAddress: String = ""
    @AppStorage("lumo_scheduled_dropoff_address") private var scheduledDropoffAddress: String = ""
    @AppStorage("lumo_scheduled_pickup_lat") private var scheduledPickupLat: Double = 0
    @AppStorage("lumo_scheduled_pickup_lng") private var scheduledPickupLng: Double = 0
    @AppStorage("lumo_scheduled_dropoff_lat") private var scheduledDropoffLat: Double = 0
    @AppStorage("lumo_scheduled_dropoff_lng") private var scheduledDropoffLng: Double = 0
    @AppStorage("lumo_scheduled_for_epoch") private var scheduledForEpoch: Double = 0
    @AppStorage("lumo_scheduled_ride_type") private var scheduledRideType: String = ""
    @AppStorage("lumo_scheduled_notes") private var scheduledNotes: String = ""

    @State private var showScheduledRideFromPill: Bool = false
    @State private var navigateToActiveTrip: Bool = false

    // MARK: - Scheduled pill display text
    private var scheduledPillTimeText: String {
        guard scheduledForEpoch > 0 else { return "Not set" }
        let d = Date(timeIntervalSince1970: scheduledForEpoch)
        let f = DateFormatter()
        f.locale = .current
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: d)
    }

    private var scheduledPillFromText: String {
        let t = scheduledPickupAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "Current location" : t
    }

    private var scheduledPillToText: String {
        let t = scheduledDropoffAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "Enter destination" : t
    }

    // Center of the map (for Google Maps)
    @State private var mapCenter = CLLocationCoordinate2D(latitude: 41.8781, longitude: -87.6298)
    @State private var mapRefreshID = UUID()

    @StateObject private var locationManager = LumoLocationManager()
    @State private var hasCenteredOnce = false
    @State private var showDestinationSearch = false
    @State private var isMapFullScreen = false
    @State private var showProfileMenu = false
    @State private var logoutTriggered: Bool = false


    var body: some View {
        ZStack {

            Color.black.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 28) {

                    // MARK: — TOP BAR
                    HStack {
                        Text("Lumo")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(.white)

                        Spacer()

                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                showProfileMenu.toggle()
                            }
                        } label: {
                            Circle()
                                .fill(Color.white.opacity(0.15))
                                .frame(width: 38, height: 38)
                                .overlay(
                                    Image(systemName: "person.fill")
                                        .foregroundColor(.white)
                                        .font(.system(size: 18, weight: .medium))
                                )
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 12)

                    // MARK: — SCHEDULED RIDE PILL
                    if hasScheduledRide && !scheduledRideId.isEmpty {
                        Button {
                            // Jump to the scheduled-ride screen
                            showScheduledRideFromPill = true
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "calendar.badge.clock")
                                    .font(.system(size: 13, weight: .semibold))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Ride scheduled")
                                        .font(.system(size: 13, weight: .semibold))

                                    Text(scheduledPillTimeText)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.white.opacity(0.80))
                                        .lineLimit(1)

                                    Text("From: \(scheduledPillFromText)")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.white.opacity(0.70))
                                        .lineLimit(1)

                                    Text("To: \(scheduledPillToText)")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.white.opacity(0.70))
                                        .lineLimit(1)
                                }

                                Spacer(minLength: 0)

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.55))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity)
                            .background(Color.white.opacity(0.10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 24)
                        .padding(.top, -10)
                    }

                    // MARK: — SEARCH BAR
                    Button { showDestinationSearch = true } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 17))
                                .foregroundColor(.gray.opacity(0.8))

                            Text("Where are you going?")
                                .foregroundColor(.gray.opacity(0.9))
                                .font(.system(size: 16))

                            Spacer()
                        }
                        .padding(.horizontal, 18)
                        .frame(height: 54)
                        .background(Color.white)
                        .cornerRadius(28)
                        .shadow(color: Color.white.opacity(0.05), radius: 12, x: 0, y: 4)
                        .padding(.horizontal, 24)
                    }

                    // MARK: — NOW / SCHEDULE SWITCH
                    HStack(spacing: 14) {
                        Button {
                            isNow = true
                        } label: {
                            Text("Now")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(isNow ? .black : .white)
                                .padding(.vertical, 10)
                                .padding(.horizontal, 22)
                                .background(
                                    isNow ? Color.white : Color.white.opacity(0.1)
                                )
                                .cornerRadius(20)
                        }

                        NavigationLink {
                            ScheduleRideView()
                        } label: {
                            Text("Schedule")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(!isNow ? .black : .white)
                                .padding(.vertical, 10)
                                .padding(.horizontal, 22)
                                .background(
                                    !isNow ? Color.white : Color.white.opacity(0.1)
                                )
                                .cornerRadius(20)
                        }
                        .buttonStyle(.plain)
                        .simultaneousGesture(TapGesture().onEnded {
                            isNow = false
                        })

                        Spacer()
                    }
                    .padding(.horizontal, 24)

                    // MARK: — PLAN YOUR RIDE CARD
                    VStack(alignment: .leading, spacing: 20) {

                        Text("Plan your ride")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.black)

                        // PICKUP
                        NavigationLink {
                            DestinationSearchView(locationManager: locationManager)
                        } label: {
                            HStack(spacing: 14) {
                                Circle()
                                    .fill(Color.black)
                                    .frame(width: 10, height: 10)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Pickup")
                                        .font(.system(size: 13))
                                        .foregroundColor(.gray)

                                    Text("Where from?")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.black)
                                }

                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)

                        Divider().background(Color.black.opacity(0.1))

                        // DROPOFF
                        NavigationLink {
                            DestinationSearchView(locationManager: locationManager)
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(.black)
                                    .font(.system(size: 18))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Dropoff")
                                        .font(.system(size: 13))
                                        .foregroundColor(.gray)

                                    Text("Where to?")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.black)
                                }

                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)

                    }
                    .padding(22)
                    .background(Color.white)
                    .cornerRadius(26)
                    .shadow(color: Color.white.opacity(0.05), radius: 20, x: 0, y: 6)
                    .padding(.horizontal, 24)

                    // MARK: — MAP SECTION
                    ZStack(alignment: .topTrailing) {
                        GoogleMapView(centerCoordinate: mapCenter, rideId: activeRideId.isEmpty ? nil : activeRideId)
                            .id(mapRefreshID)
                            .frame(height: 400)
                            .clipShape(RoundedRectangle(cornerRadius: 34))
                            .shadow(color: Color.white.opacity(0.08), radius: 20, x: 0, y: 6)

                        VStack(spacing: 10) {

                            Button { recenter() } label: {
                                Image(systemName: "location.fill")
                                    .font(.system(size: 18))
                                    .foregroundColor(.black)
                                    .padding(12)
                                    .background(Color.white)
                                    .clipShape(Circle())
                            }

                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    isMapFullScreen = true
                                }
                            } label: {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.system(size: 18))
                                    .foregroundColor(.black)
                                    .padding(12)
                                    .background(Color.white)
                                    .clipShape(Circle())
                            }
                        }
                        .padding(.top, 18)
                        .padding(.trailing, 20)
                    }
                    .padding(.horizontal, 24)

                    Spacer(minLength: 40)
                }
            }
            .scrollDisabled(true)

            // MARK: - SIDE ACCOUNT SHEET
            if showProfileMenu {
                ZStack {
                    // Dim background, tap to dismiss
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                showProfileMenu = false
                            }
                        }

                    HStack(spacing: 0) {
                        Spacer()

                        VStack(alignment: .leading, spacing: 18) {

                            Text("Account")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.bottom, 4)

                            // ✅ UPDATED: pass binding into ProfileView
                            NavigationLink {
                                ProfileView(logoutTriggered: $logoutTriggered)
                            } label: {
                                Text("Profile")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .simultaneousGesture(TapGesture().onEnded {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    showProfileMenu = false
                                }
                            })

                            NavigationLink {
                                LanguageSettingsView()
                            } label: {
                                Text("Language")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .simultaneousGesture(TapGesture().onEnded {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    showProfileMenu = false
                                }
                            })

                            NavigationLink {
                                PrivacyView()
                            } label: {
                                Text("Privacy")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .simultaneousGesture(TapGesture().onEnded {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    showProfileMenu = false
                                }
                            })

                            NavigationLink {
                                RideHistoryView()
                            } label: {
                                Text("Ride history")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .simultaneousGesture(TapGesture().onEnded {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    showProfileMenu = false
                                }
                            })

                            NavigationLink {
                                DeliveryRootView()
                            } label: {
                                Text("Delivery")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .simultaneousGesture(TapGesture().onEnded {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    showProfileMenu = false
                                }
                            })
                            
                            NavigationLink {
                                NotificationsView()
                            } label: {
                                Text("Notifications")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .simultaneousGesture(TapGesture().onEnded {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    showProfileMenu = false
                                }
                            })

                            NavigationLink {
                                SupportView()
                            } label: {
                                Text("Support")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .simultaneousGesture(TapGesture().onEnded {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    showProfileMenu = false
                                }
                            })

                            NavigationLink {
                                LegalView()
                            } label: {
                                Text("Legal")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .simultaneousGesture(TapGesture().onEnded {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    showProfileMenu = false
                                }
                            })

                            // MARK: - Log out button in side menu
                            Button {
                                do {
                                    try Auth.auth().signOut()

                                    // 👇 trigger navigation to GetStartedView with NO animation
                                    withAnimation(.none) {
                                        logoutTriggered = true
                                    }
                                } catch {
                                    print("Error signing out: \(error)")
                                }

                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    showProfileMenu = false
                                }
                            } label: {
                                Text("Log out")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(.red)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            Spacer()
                        }
                        .padding(.top, 60)
                        .padding(.horizontal, 24)
                        .frame(maxWidth: 220, maxHeight: .infinity, alignment: .topLeading)
                        .background(Color.black)
                        .ignoresSafeArea()
                    }
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
                .zIndex(1)
            }
        }
        .sheet(isPresented: $showDestinationSearch) {
            DestinationSearchView(locationManager: locationManager)
        }
        .overlay(fullScreenMapOverlay)
        .onAppear {
            reconcileScheduledRideState()

            if !scheduledRideId.isEmpty {
                rideService.fetchActiveRideStatus(rideId: scheduledRideId)
            }
            // Auto-resume if a ride is in progress
            if rideService.activeRideStatus == "started" {
                navigateToActiveTrip = true
            }
        }
        .onChange(of: scheduledForEpoch) { _ in
            reconcileScheduledRideState()
        }
        .onChange(of: scheduledPickupAddress) { _ in
            reconcileScheduledRideState()
        }
        .onChange(of: scheduledDropoffAddress) { _ in
            reconcileScheduledRideState()
        }
        .onChange(of: scheduledRideId) { _ in
            reconcileScheduledRideState()
        }
        .onReceive(locationManager.$coordinate.compactMap { $0 }) { coord in
            guard !hasCenteredOnce else { return }
            mapCenter = coord
            hasCenteredOnce = true
        }
        .onReceive(rideService.$activeRideStatus.compactMap { $0 }) { status in
            if status == "started" {
                navigateToActiveTrip = true
            }

            if status == "completed" {
                navigateToActiveTrip = false
                hasScheduledRide = false
                scheduledRideId = ""
                scheduledPickupAddress = ""
                scheduledDropoffAddress = ""
                scheduledPickupLat = 0
                scheduledPickupLng = 0
                scheduledDropoffLat = 0
                scheduledDropoffLng = 0
                scheduledForEpoch = 0
                scheduledRideType = ""
                scheduledNotes = ""
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $logoutTriggered) {
            GetStartedView()
        }
        .navigationDestination(isPresented: $showScheduledRideFromPill) {
            ScheduledRideDetailsView(
                hasScheduledRide: $hasScheduledRide,
                scheduledRideId: $scheduledRideId,
                scheduledPickupAddress: $scheduledPickupAddress,
                scheduledDropoffAddress: $scheduledDropoffAddress,
                scheduledPickupLat: $scheduledPickupLat,
                scheduledPickupLng: $scheduledPickupLng,
                scheduledDropoffLat: $scheduledDropoffLat,
                scheduledDropoffLng: $scheduledDropoffLng,
                scheduledForEpoch: $scheduledForEpoch,
                scheduledRideType: $scheduledRideType,
                scheduledNotes: $scheduledNotes
            )
        }
        .navigationDestination(isPresented: $navigateToActiveTrip) {
            if rideService.activeRideStatus == "started" {
                DriverTrackingView(rideId: scheduledRideId)
            } else {
                // Defensive: if something toggled this early, close it immediately.
                Color.clear.onAppear {
                    navigateToActiveTrip = false
                }
            }
        }
    }

    // MARK: — FULL SCREEN MAP OVERLAY
    private var fullScreenMapOverlay: some View {
        Group {
            if isMapFullScreen {
                ZStack {
                    GoogleMapView(centerCoordinate: mapCenter, rideId: activeRideId.isEmpty ? nil : activeRideId)
                        .id(mapRefreshID)
                        .ignoresSafeArea()

                    VStack {
                        HStack {
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    isMapFullScreen = false
                                }
                            } label: {
                                Image(systemName: "xmark")
                                    .foregroundColor(.black)
                                    .padding(12)
                                    .background(Color.white)
                                    .clipShape(Circle())
                            }

                            Spacer()

                            Button { recenter() } label: {
                                Image(systemName: "location.fill")
                                    .foregroundColor(.black)
                                    .padding(12)
                                    .background(Color.white)
                                    .clipShape(Circle())
                            }
                        }
                        .padding(.top, 50)
                        .padding(.horizontal, 24)

                        Spacer()
                    }
                }
            }
        }
    }

    // MARK: - Scheduled ride reconciliation
    // Some flows may persist scheduled details but forget to set `lumo_has_scheduled_ride` / `lumo_scheduled_ride_id`.
    // This keeps the Home pill consistent.
    private func reconcileScheduledRideState() {
        let hasAnyScheduledData =
            scheduledForEpoch > 0 ||
            !scheduledPickupAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !scheduledDropoffAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if hasAnyScheduledData {
            if scheduledRideId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                scheduledRideId = UUID().uuidString
            }
            hasScheduledRide = true
        } else {
            hasScheduledRide = false
            scheduledRideId = ""
        }
    }

    private func recenter() {
        if let coord = locationManager.coordinate {
            mapCenter = coord
            hasCenteredOnce = true
            mapRefreshID = UUID()
        }
    }
}

#Preview {
    NavigationStack { HomeView() }
}

struct ScheduledRideDetailsView: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var hasScheduledRide: Bool
    @Binding var scheduledRideId: String
    @Binding var scheduledPickupAddress: String
    @Binding var scheduledDropoffAddress: String
    @Binding var scheduledPickupLat: Double
    @Binding var scheduledPickupLng: Double
    @Binding var scheduledDropoffLat: Double
    @Binding var scheduledDropoffLng: Double
    @Binding var scheduledForEpoch: Double
    @Binding var scheduledRideType: String
    @Binding var scheduledNotes: String

    private var scheduledDateText: String {
        guard scheduledForEpoch > 0 else { return "Not set" }
        let d = Date(timeIntervalSince1970: scheduledForEpoch)
        let f = DateFormatter()
        f.locale = .current
        f.dateStyle = .full
        f.timeStyle = .short
        return f.string(from: d)
    }

    private var notesTrimmed: String {
        scheduledNotes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func clearScheduledRide() {
        hasScheduledRide = false
        scheduledRideId = ""
        scheduledPickupAddress = ""
        scheduledDropoffAddress = ""
        scheduledPickupLat = 0
        scheduledPickupLng = 0
        scheduledDropoffLat = 0
        scheduledDropoffLng = 0
        scheduledForEpoch = 0
        scheduledRideType = ""
        scheduledNotes = ""
        UserDefaults.standard.removeObject(forKey: "lumo_scheduled_for_epoch")
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {

                    HStack {
                        Button {
                            dismiss()
                        } label: {
                            Circle()
                                .fill(Color.white.opacity(0.15))
                                .frame(width: 38, height: 38)
                                .overlay(
                                    Image(systemName: "chevron.left")
                                        .foregroundColor(.white)
                                        .font(.system(size: 16, weight: .semibold))
                                )
                        }

                        Spacer()
                    }
                    .padding(.top, 12)

                    Text("Scheduled ride")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Pickup time")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white.opacity(0.65))
                            Spacer()
                            Text(scheduledDateText)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                                .multilineTextAlignment(.trailing)
                        }

                        Divider().background(Color.white.opacity(0.15))

                        VStack(alignment: .leading, spacing: 6) {
                            Text("From")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white.opacity(0.6))
                            Text(scheduledPickupAddress.isEmpty ? "Current location" : scheduledPickupAddress)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("To")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white.opacity(0.6))
                            Text(scheduledDropoffAddress.isEmpty ? "Enter destination" : scheduledDropoffAddress)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                        }

                        Divider().background(Color.white.opacity(0.15))

                        HStack {
                            Text("Ride type")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white.opacity(0.65))
                            Spacer()
                            Text(scheduledRideType.isEmpty ? "Standard" : scheduledRideType)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                        }

                        if !notesTrimmed.isEmpty {
                            Text("Notes: \(notesTrimmed)")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white.opacity(0.75))
                                .lineLimit(6)
                        }
                    }
                    .padding(18)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

                    Button(role: .destructive) {
                        clearScheduledRide()
                        dismiss()
                    } label: {
                        Text("Cancel scheduled ride")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.red.opacity(0.90))
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }

                    Spacer(minLength: 30)
                }
                .padding(.horizontal, 20)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }
}

// MARK: - Profile

struct ProfileView: View {
    // ✅ Binding from HomeView so Profile can trigger logout navigation
    @Binding var logoutTriggered: Bool

    // MARK: - Mock user data (later you can bind these to real user info)
    @State private var fullName: String = "Your name"
    @State private var email: String = ""
    @State private var phoneNumber: String = "+1 (312) 555-0123"

    @State private var preferredRideType: String = "LumoX"
    @State private var countryRegion: String = "United States"
    @State private var memberSince: String = ""

    // Save state
    @State private var isSaving: Bool = false
    @State private var showSaveAlert: Bool = false

    // Profile photo state
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var profileImageData: Data?
    private let profileImageDefaultsKey = "lumo_profileImageData"

    // Persisted profile info
    private let profileInfoDefaultsKey = "lumo_profileInfo"

    // Simple ride type options
    private let rideTypes = ["Saver", "LumoX", "LumoXL"]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {

                    // MARK: - Header with avatar
                    VStack(spacing: 14) {
                        ZStack {
                            if let data = profileImageData,
                               let uiImage = UIImage(data: data) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 90, height: 90)
                                    .clipShape(Circle())
                            } else {
                                Circle()
                                    .fill(Color.white.opacity(0.08))
                                    .frame(width: 90, height: 90)
                                    .overlay(
                                        Image(systemName: "person.fill")
                                            .font(.system(size: 36, weight: .medium))
                                            .foregroundColor(.white)
                                    )
                            }
                        }

                        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                            Text("Change photo")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.12))
                                .clipShape(Capsule())
                        }
                        .onChange(of: selectedPhotoItem) { newItem in
                            guard let newItem else { return }
                            Task {
                                if let data = try? await newItem.loadTransferable(type: Data.self) {
                                    await MainActor.run {
                                        profileImageData = data
                                        UserDefaults.standard.set(data, forKey: profileImageDefaultsKey)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.top, 24)

                    // MARK: - Account info card
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Account")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)

                        // Full name
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Full name")
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.6))

                            TextField("Your name", text: $fullName)
                                .font(.system(size: 16))
                                .foregroundColor(.white)
                                .padding(10)
                                .background(Color.white.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        // Phone (editable, but labeled as managed)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Phone")
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.6))

                            TextField("+1 (312) 555-0123", text: $phoneNumber)
                                .font(.system(size: 16))
                                .foregroundColor(.white)
                                .keyboardType(.phonePad)
                                .padding(10)
                                .background(Color.white.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 12))

                            Text("Managed by your sign-in method")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.45))
                        }

                        // Email (editable, but labeled as managed)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Email")
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.6))

                            TextField("you@example.com", text: $email)
                                .font(.system(size: 16))
                                .foregroundColor(.white)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .padding(10)
                                .background(Color.white.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 12))

                            Text("Managed by your sign-in method")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.45))
                        }
                    }
                    .padding(18)
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .padding(.horizontal, 20)

                    // MARK: - Preferences card
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Preferences")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)

                        // Country / region
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Country / Region")
                                    .font(.system(size: 13))
                                    .foregroundColor(.white.opacity(0.6))

                                Text(countryRegion)
                                    .font(.system(size: 16))
                                    .foregroundColor(.white)
                            }
                            Spacer()
                        }

                        Divider().background(Color.white.opacity(0.15))

                        // Preferred ride type
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Preferred ride type")
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.6))

                            HStack(spacing: 8) {
                                ForEach(rideTypes, id: \.self) { type in
                                    Button {
                                        preferredRideType = type
                                    } label: {
                                        Text(type)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(
                                                preferredRideType == type ? .black : .white
                                            )
                                            .padding(.vertical, 8)
                                            .padding(.horizontal, 14)
                                            .background(
                                                preferredRideType == type
                                                ? Color.white
                                                : Color.white.opacity(0.12)
                                            )
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                        }

                        Divider().background(Color.white.opacity(0.15))

                        // Member since
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Member since")
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.6))

                            Text(memberSince)
                                .font(.system(size: 16))
                                .foregroundColor(.white)
                        }
                    }
                    .padding(18)
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .padding(.horizontal, 20)

                    // MARK: - Safety card (placeholder)
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Safety")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Emergency contact")
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.6))

                            Text("Add a trusted contact")
                                .font(.system(size: 15))
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                    .padding(18)
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .padding(.horizontal, 20)

                    // MARK: - Account actions
                    VStack(spacing: 12) {
                        // ✅ SAVE BUTTON
                        Button(action: saveProfile) {
                            Group {
                                if isSaving {
                                    ProgressView()
                                        .tint(.black)
                                } else {
                                    Text("Save")
                                        .font(.system(size: 16, weight: .semibold))
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.white)
                            .foregroundColor(.black)
                            .clipShape(RoundedRectangle(cornerRadius: 22))
                        }

                        // ✅ LOG OUT BUTTON
                        Button {
                            handleLogout()
                        } label: {
                            Text("Log out")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.red)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }

                        Button {
                            // TODO: handle delete account flow
                            print("Delete my account tapped")
                        } label: {
                            Text("Delete my account")
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
                }
            }
        }
        .onAppear {
            loadMemberSince()

            if let currentUser = Auth.auth().currentUser {
                email = currentUser.email ?? ""
            } else {
                email = ""
            }

            let defaults = UserDefaults.standard
            if let savedData = defaults.data(forKey: profileImageDefaultsKey) {
                profileImageData = savedData
            }

            // restore saved profile info
            if let savedInfo = defaults.dictionary(forKey: profileInfoDefaultsKey) as? [String: String] {
                fullName = savedInfo["fullName"] ?? fullName
                email = savedInfo["email"] ?? email
                phoneNumber = savedInfo["phone"] ?? phoneNumber
                countryRegion = savedInfo["country"] ?? countryRegion
                if let ride = savedInfo["rideType"], rideTypes.contains(ride) {
                    preferredRideType = ride
                }
            }
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Profile saved", isPresented: $showSaveAlert) {
            Button("OK", role: .cancel) {}
        }
    }

    // MARK: - Save logic
    private func saveProfile() {
        isSaving = true

        // Optional: update Firebase display name
        if let user = Auth.auth().currentUser {
            let change = user.createProfileChangeRequest()
            change.displayName = fullName
            change.commitChanges(completion: nil)
        }

        let info: [String: String] = [
            "fullName": fullName,
            "email": email,
            "phone": phoneNumber,
            "country": countryRegion,
            "rideType": preferredRideType
        ]
        UserDefaults.standard.set(info, forKey: profileInfoDefaultsKey)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            isSaving = false
            showSaveAlert = true
        }
    }

    // MARK: - Logout logic
    private func handleLogout() {
        do {
            try Auth.auth().signOut()
            logoutTriggered = true   // tell HomeView to navigate out
        } catch {
            print("Error signing out: \(error.localizedDescription)")
        }
    }

    private func loadMemberSince() {
        let defaults = UserDefaults.standard
        let key = "lumo_firstLaunchDate"

        if let storedDate = defaults.object(forKey: key) as? Date {
            memberSince = formatMonthYear(storedDate)
        } else {
            let now = Date()
            defaults.set(now, forKey: key)
            memberSince = formatMonthYear(now)
        }
    }

    private func formatMonthYear(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }
}

// MARK: - Language

struct LanguageSettingsView: View {
    @EnvironmentObject private var languageStore: LumoLanguageStore

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Language")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)

                    Text("English is default. Arabic is available with right-to-left layout.")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.6))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 16)

                VStack(spacing: 10) {
                    ForEach(LumoAppLanguage.allCases) { language in
                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                languageStore.select(language)
                            }
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(language.displayName)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.white)

                                    Text(language.nativeName)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.white.opacity(0.6))
                                }

                                Spacer()

                                if languageStore.selectedLanguage == language {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundColor(.white)
                                } else {
                                    Circle()
                                        .stroke(Color.white.opacity(0.25), lineWidth: 1.5)
                                        .frame(width: 20, height: 20)
                                }
                            }
                            .padding(14)
                            .background(Color.white.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)

                Spacer()
            }
        }
        .navigationTitle("Language")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Payments (Wallet + deposit)

struct PaymentsView: View {
    @StateObject private var wallet = LumoWalletStore()
    @State private var showAddFundsSheet: Bool = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {

                    // Header
                    Text("Wallet")
                        .font(.system(size: 42, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.top, 10)
                        .padding(.horizontal, 20)

                    // Wallet card
                    LumoWalletCard(
                        balanceText: wallet.formattedBalance,
                        autoRefillEnabled: wallet.autoRefillEnabled,
                        addFundsTapped: { showAddFundsSheet = true }
                    )
                    .padding(.horizontal, 20)

                    // Your info
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Your information")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)

                        LumoInfoRow(title: "Name", value: wallet.userFullName)
                        LumoInfoRow(title: "Email", value: wallet.userEmail)
                        LumoInfoRow(title: "Phone", value: wallet.userPhone)

                        Divider().background(Color.white.opacity(0.12))

                        LumoInfoRow(title: "Default payment method", value: wallet.defaultPaymentMethod)
                    }
                    .padding(16)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .padding(.horizontal, 20)

                    // Recent activity (simple)
                    if !wallet.transactions.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Recent activity")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)

                            ForEach(wallet.transactions.prefix(6)) { tx in
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(tx.title)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundColor(.white)

                                        Text(tx.subtitle)
                                            .font(.system(size: 12))
                                            .foregroundColor(.white.opacity(0.6))
                                    }

                                    Spacer()

                                    Text(tx.amountText)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(.white)
                                }
                                .padding(12)
                                .background(Color.white.opacity(0.05))
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                            }
                        }
                        .padding(16)
                        .background(Color.white.opacity(0.03))
                        .clipShape(RoundedRectangle(cornerRadius: 22))
                        .padding(.horizontal, 20)
                    }

                    Spacer(minLength: 24)
                }
                .padding(.bottom, 28)
            }
        }
        .navigationTitle("Payments")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAddFundsSheet) {
            LumoAddFundsSheet(wallet: wallet)
        }
        .onAppear {
            wallet.refreshUserInfo()
        }
    }
}

private struct LumoWalletCard: View {
    let balanceText: String
    let autoRefillEnabled: Bool
    let addFundsTapped: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 28)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.11),
                            Color.white.opacity(0.06)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 10) {
                Text("Lumo balance")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white.opacity(0.92))

                Text(balanceText)
                    .font(.system(size: 56, weight: .heavy, design: .monospaced))
                    .foregroundColor(.white)
                    .minimumScaleFactor(0.65)
                    .lineLimit(1)

                HStack(spacing: 10) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.white.opacity(0.7))
                    Text(autoRefillEnabled ? "Auto-refill is on" : "Auto-refill is off")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white.opacity(0.75))
                }
                .padding(.top, 2)

                Button(action: addFundsTapped) {
                    HStack(spacing: 10) {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .bold))
                        Text("Add funds")
                            .font(.system(size: 18, weight: .bold))
                    }
                    .foregroundColor(.black)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(Color.white)
                    .clipShape(Capsule())
                }
                .padding(.top, 14)

                Spacer(minLength: 0)
            }
            .padding(20)

            Image(systemName: "chevron.right")
                .foregroundColor(.white.opacity(0.20))
                .padding(18)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 220)
    }
}

private struct LumoInfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.55))
                .frame(width: 150, alignment: .leading)

            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
        }
    }
}

private struct LumoAddFundsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var wallet: LumoWalletStore

    @State private var amountText: String = "25"
    @State private var selectedQuick: Int? = 25
    @State private var depositError: String? = nil
    @State private var showPaymentMethodPicker: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 18) {

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Add funds")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(.white)

                        Text("Funds will be added to your Lumo balance.")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .padding(.top, 10)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Amount")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white.opacity(0.6))

                        HStack(spacing: 10) {
                            Text("$")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.white)

                            TextField("0", text: $amountText)
                                .keyboardType(.decimalPad)
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.white)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .onChange(of: amountText) { newValue in
                                    // Keep it numeric-ish and limit length
                                    let filtered = newValue.filter { "0123456789.".contains($0) }
                                    if filtered != newValue { amountText = filtered }
                                    if amountText.count > 8 { amountText = String(amountText.prefix(8)) }
                                    depositError = nil
                                    selectedQuick = nil
                                }

                            Spacer()
                        }
                        .padding(14)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 16))

                        HStack(spacing: 10) {
                            LumoQuickAmountButton(title: "$10", isSelected: selectedQuick == 10) {
                                amountText = "10"
                                selectedQuick = 10
                                depositError = nil
                            }
                            LumoQuickAmountButton(title: "$25", isSelected: selectedQuick == 25) {
                                amountText = "25"
                                selectedQuick = 25
                                depositError = nil
                            }
                            LumoQuickAmountButton(title: "$50", isSelected: selectedQuick == 50) {
                                amountText = "50"
                                selectedQuick = 50
                                depositError = nil
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Payment method")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white.opacity(0.6))

                        Button {
                            showPaymentMethodPicker = true
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "creditcard.fill")
                                    .foregroundColor(.white)
                                    .padding(10)
                                    .background(Color.white.opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(wallet.defaultPaymentMethod)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(.white)

                                    Text("Used for deposits")
                                        .font(.system(size: 12))
                                        .foregroundColor(.white.opacity(0.6))
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .foregroundColor(.white.opacity(0.35))
                            }
                            .padding(12)
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                        }
                        .buttonStyle(.plain)
                    }

                    if let depositError {
                        Text(depositError)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.red)
                            .padding(.top, 2)
                    }

                    Spacer()

                    Button {
                        let cents = LumoWalletStore.parseAmountToCents(amountText)
                        if cents <= 0 {
                            depositError = "Enter a valid amount."
                            return
                        }
                        if cents > 100_000_00 {
                            depositError = "Max deposit is $100,000.00"
                            return
                        }

                        wallet.deposit(cents: cents, method: wallet.defaultPaymentMethod)
                        dismiss()
                    } label: {
                        Text("Add funds")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 18)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundColor(.white)
                            .padding(8)
                            .background(Color.white.opacity(0.10))
                            .clipShape(Circle())
                    }
                }
            }
            .sheet(isPresented: $showPaymentMethodPicker) {
                LumoPaymentMethodPicker(wallet: wallet)
            }
        }
    }
}

private struct LumoQuickAmountButton: View {
    let title: String
    let isSelected: Bool
    let tapped: () -> Void

    var body: some View {
        Button(action: tapped) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(isSelected ? .black : .white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(isSelected ? Color.white : Color.white.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }
}

// MARK: - Payment method picker + Stripe card entry

private struct LumoPaymentMethodPicker: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var wallet: LumoWalletStore

    @State private var showCardEntry: Bool = false
    @State private var showComingSoon: Bool = false
    @State private var comingSoonTitle: String = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 14) {
                    Text("Payment method")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.top, 12)

                    Button {
                        showCardEntry = true
                    } label: {
                        LumoPMRow(icon: "creditcard.fill", title: "Card", subtitle: "Visa, Mastercard, etc.")
                    }
                    .buttonStyle(.plain)

                    Button {
                        comingSoonTitle = "PayPal"
                        showComingSoon = true
                    } label: {
                        LumoPMRow(icon: "p.circle.fill", title: "PayPal", subtitle: "Coming soon")
                    }
                    .buttonStyle(.plain)

                    Button {
                        comingSoonTitle = "Gift card"
                        showComingSoon = true
                    } label: {
                        LumoPMRow(icon: "giftcard.fill", title: "Gift card", subtitle: "Coming soon")
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
                .padding(.horizontal, 20)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundColor(.white)
                            .padding(8)
                            .background(Color.white.opacity(0.10))
                            .clipShape(Circle())
                    }
                }
            }
            .alert("\(comingSoonTitle)", isPresented: $showComingSoon) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("We’ll add this next.")
            }
            .sheet(isPresented: $showCardEntry) {
                LumoStripeCardEntrySheet(wallet: wallet) {
                    // After saving a card, close the picker too
                    dismiss()
                }
            }
        }
    }
}

private struct LumoPMRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.white)
                .padding(10)
                .background(Color.white.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)

                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.6))
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundColor(.white.opacity(0.35))
        }
        .padding(12)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

private struct LumoStripeCardEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var wallet: LumoWalletStore

    let onCardSaved: () -> Void

    @State private var cardParams = STPPaymentMethodCardParams()
    @State private var isValid: Bool = false
    @State private var isSaving: Bool = false
    @State private var errorText: String? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 16) {
                    Text("Add card")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.top, 12)

                    Text("Enter your card details securely with Stripe.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))

                    StripeCardFieldRepresentable(cardParams: $cardParams, isValid: $isValid)
                        .frame(height: 52)
                        .padding(12)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 16))

                    if let errorText {
                        Text(errorText)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.red)
                    }

                    Spacer()

                    Button {
                        saveCard()
                    } label: {
                        Group {
                            if isSaving {
                                ProgressView().tint(.black)
                            } else {
                                Text("Use this card")
                                    .font(.system(size: 16, weight: .bold))
                            }
                        }
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(isValid ? Color.white : Color.white.opacity(0.35))
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                    }
                    .disabled(!isValid || isSaving)
                    .padding(.bottom, 12)
                }
                .padding(.horizontal, 20)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundColor(.white)
                            .padding(8)
                            .background(Color.white.opacity(0.10))
                            .clipShape(Circle())
                    }
                }
            }
        }
        .onAppear {
            // IMPORTANT: Replace with your real Stripe publishable key.
            // Ideally set this once on app launch, but keeping it here avoids extra files.
            if StripeAPI.defaultPublishableKey == nil || StripeAPI.defaultPublishableKey?.isEmpty == true {
                StripeAPI.defaultPublishableKey = "pk_test_REPLACE_WITH_YOUR_KEY"
            }
        }
    }

    private func saveCard() {
        errorText = nil
        isSaving = true

        let pmParams = STPPaymentMethodParams(card: cardParams, billingDetails: nil, metadata: nil)

        STPAPIClient.shared.createPaymentMethod(with: pmParams) { paymentMethod, error in
            DispatchQueue.main.async {
                isSaving = false

                if let error = error {
                    errorText = error.localizedDescription
                    return
                }

                guard let pm = paymentMethod, let card = pm.card else {
                    errorText = "Could not save card."
                    return
                }

                let brand = Self.brandName(card.brand)
                let last4 = card.last4 ?? "••••"

                wallet.setCardPaymentMethod(id: pm.stripeId, brand: brand, last4: last4)

                dismiss()       // close card sheet
                onCardSaved()   // close picker
            }
        }
    }

    private static func brandName(_ brand: STPCardBrand) -> String {
        switch brand {
        case .visa: return "Visa"
        case .mastercard: return "Mastercard"
        case .amex: return "Amex"
        case .discover: return "Discover"
        case .JCB: return "JCB"
        case .dinersClub: return "Diners"
        case .unionPay: return "UnionPay"
        default: return "Card"
        }
    }
}

private struct StripeCardFieldRepresentable: UIViewRepresentable {
    @Binding var cardParams: STPPaymentMethodCardParams
    @Binding var isValid: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(cardParams: $cardParams, isValid: $isValid)
    }

    func makeUIView(context: Context) -> STPPaymentCardTextField {
        let field = STPPaymentCardTextField()
        field.delegate = context.coordinator
        field.borderWidth = 0
        field.backgroundColor = .clear
        field.textColor = .white
        field.tintColor = .white
        field.placeholderColor = UIColor.white.withAlphaComponent(0.35)
        field.postalCodeEntryEnabled = true
        context.coordinator.sync(from: field)
        return field
    }

    func updateUIView(_ uiView: STPPaymentCardTextField, context: Context) {
        // Stripe manages its own text content.
    }

    final class Coordinator: NSObject, STPPaymentCardTextFieldDelegate {
        @Binding var cardParams: STPPaymentMethodCardParams
        @Binding var isValid: Bool

        init(cardParams: Binding<STPPaymentMethodCardParams>, isValid: Binding<Bool>) {
            _cardParams = cardParams
            _isValid = isValid
        }

        func paymentCardTextFieldDidChange(_ textField: STPPaymentCardTextField) {
            sync(from: textField)
        }

        func sync(from textField: STPPaymentCardTextField) {
            cardParams = textField.cardParams
            isValid = textField.isValid
        }
    }
}

// MARK: - Wallet store (UserDefaults-backed)

final class LumoWalletStore: ObservableObject {
    @Published private(set) var balanceCents: Int = 0
    @Published private(set) var transactions: [LumoWalletTransaction] = []

    @Published var autoRefillEnabled: Bool = false

    // User info
    @Published private(set) var userFullName: String = "Not set"
    @Published private(set) var userEmail: String = "Not set"
    @Published private(set) var userPhone: String = "Not set"

    // Placeholder until you hook up real saved payment methods
    @Published var defaultPaymentMethod: String = "Card (set up later)"

    @Published private(set) var stripePaymentMethodId: String? = nil
    @Published private(set) var stripeCardBrand: String? = nil
    @Published private(set) var stripeCardLast4: String? = nil

    private let pmIdKey = "lumo_walletStripePMId"
    private let pmBrandKey = "lumo_walletStripePMBrand"
    private let pmLast4Key = "lumo_walletStripePMLast4"

    private let balanceKey = "lumo_walletBalanceCents"
    private let txKey = "lumo_walletTransactions"
    private let autoRefillKey = "lumo_walletAutoRefill"

    init() {
        load()
        refreshUserInfo()
    }

    var formattedBalance: String {
        Self.formatCents(balanceCents)
    }

    func refreshUserInfo() {
        // Pull from FirebaseAuth if available
        if let user = Auth.auth().currentUser {
            let name = user.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let email = user.email?.trimmingCharacters(in: .whitespacesAndNewlines)
            let phone = user.phoneNumber?.trimmingCharacters(in: .whitespacesAndNewlines)

            userFullName = (name?.isEmpty == false) ? name! : "Not set"
            userEmail = (email?.isEmpty == false) ? email! : "Not set"
            userPhone = (phone?.isEmpty == false) ? phone! : "Not set"
        } else {
            userFullName = "Not set"
            userEmail = "Not set"
            userPhone = "Not set"
        }

        // If ProfileView saved info exists, prefer it (since you already persist it)
        if let saved = UserDefaults.standard.dictionary(forKey: "lumo_profileInfo") as? [String: String] {
            if let n = saved["fullName"], !n.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                userFullName = n
            }
            if let e = saved["email"], !e.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                userEmail = e
            }
            if let p = saved["phone"], !p.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                userPhone = p
            }
        }
    }

    func deposit(cents: Int, method: String) {
        guard cents > 0 else { return }

        balanceCents += cents

        let tx = LumoWalletTransaction(
            kind: .deposit,
            cents: cents,
            method: method,
            date: Date()
        )
        transactions.insert(tx, at: 0)

        persist()
    }

    func setCardPaymentMethod(id: String, brand: String, last4: String) {
        stripePaymentMethodId = id
        stripeCardBrand = brand
        stripeCardLast4 = last4
        defaultPaymentMethod = "\(brand) •••• \(last4)"
        persist()
    }

    // MARK: - Persistence

    private func load() {
        let defaults = UserDefaults.standard
        balanceCents = defaults.integer(forKey: balanceKey)
        autoRefillEnabled = defaults.bool(forKey: autoRefillKey)

        stripePaymentMethodId = defaults.string(forKey: pmIdKey)
        stripeCardBrand = defaults.string(forKey: pmBrandKey)
        stripeCardLast4 = defaults.string(forKey: pmLast4Key)

        if let b = stripeCardBrand, let l4 = stripeCardLast4 {
            defaultPaymentMethod = "\(b) •••• \(l4)"
        } else {
            defaultPaymentMethod = "Card (set up later)"
        }

        if let data = defaults.data(forKey: txKey),
           let decoded = try? JSONDecoder().decode([LumoWalletTransaction].self, from: data) {
            transactions = decoded
        } else {
            transactions = []
        }
    }

    private func persist() {
        let defaults = UserDefaults.standard
        defaults.set(balanceCents, forKey: balanceKey)
        defaults.set(autoRefillEnabled, forKey: autoRefillKey)

        defaults.set(stripePaymentMethodId, forKey: pmIdKey)
        defaults.set(stripeCardBrand, forKey: pmBrandKey)
        defaults.set(stripeCardLast4, forKey: pmLast4Key)

        if let data = try? JSONEncoder().encode(transactions) {
            defaults.set(data, forKey: txKey)
        }
    }

    // MARK: - Formatting / parsing

    static func formatCents(_ cents: Int) -> String {
        let dollars = Double(cents) / 100.0
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: dollars)) ?? String(format: "$%.2f", dollars)
    }

    static func parseAmountToCents(_ text: String) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }

        // Use Decimal to avoid float issues
        if let decimal = Decimal(string: trimmed, locale: Locale(identifier: "en_US_POSIX")) {
            let centsDecimal = decimal * 100
            let ns = NSDecimalNumber(decimal: centsDecimal)
            return max(0, ns.intValue)
        }
        return 0
    }
}

struct LumoWalletTransaction: Identifiable, Codable {
    enum Kind: String, Codable {
        case deposit
    }

    let id: UUID
    let kind: Kind
    let cents: Int
    let method: String
    let date: Date

    init(kind: Kind, cents: Int, method: String, date: Date) {
        self.id = UUID()
        self.kind = kind
        self.cents = cents
        self.method = method
        self.date = date
    }

    var title: String {
        switch kind {
        case .deposit:
            return "Deposit"
        }
    }

    var subtitle: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "\(formatter.string(from: date)) • \(method)"
    }

    var amountText: String {
        "+" + LumoWalletStore.formatCents(cents)
    }
}

// MARK: - Privacy (polished)

struct PrivacyView: View {
    @State private var locationAccess: Bool = true
    @State private var personalization: Bool = true
    @State private var dataSharing: Bool = false
    @State private var crashReports: Bool = true

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {

                    // MARK: - Location & tracking
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Location & tracking")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)

                        Toggle(isOn: $locationAccess) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Allow location")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.white)
                                Text("Let Lumo use your location for pickups and nearby drivers.")
                                    .font(.system(size: 12))
                                    .foregroundColor(.white.opacity(0.6))
                            }
                        }
                        .toggleStyle(SwitchToggleStyle(tint: .white))

                        Divider().background(Color.white.opacity(0.15))

                        Toggle(isOn: $crashReports) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Share anonymous diagnostics")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.white)
                                Text("Help improve Lumo by sending anonymous crash and performance data.")
                                    .font(.system(size: 12))
                                    .foregroundColor(.white.opacity(0.6))
                            }
                        }
                        .toggleStyle(SwitchToggleStyle(tint: .white))
                    }
                    .padding(18)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .padding(.horizontal, 20)

                    // MARK: - Personalization & data
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Personalization")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)

                        Toggle(isOn: $personalization) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Personalized suggestions")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.white)
                                Text("Use your ride history to improve recommendations.")
                                    .font(.system(size: 12))
                                    .foregroundColor(.white.opacity(0.6))
                            }
                        }
                        .toggleStyle(SwitchToggleStyle(tint: .white))

                        Divider().background(Color.white.opacity(0.15))

                        Toggle(isOn: $dataSharing) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Share data with partners")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.white)
                                Text("Share limited, anonymized information to improve partner services.")
                                    .font(.system(size: 12))
                                    .foregroundColor(.white.opacity(0.6))
                            }
                        }
                        .toggleStyle(SwitchToggleStyle(tint: .white))
                    }
                    .padding(18)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .padding(.horizontal, 20)

                    // MARK: - Data controls
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Your data")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)

                        Button {
                            print("Download data tapped")
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Download your data")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(.white)
                                    Text("Request a copy of your ride and account data.")
                                        .font(.system(size: 12))
                                        .foregroundColor(.white.opacity(0.6))
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.white.opacity(0.6))
                            }
                            .padding(12)
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }

                        Button {
                            print("Privacy policy tapped")
                        } label: {
                            HStack {
                                Text("View privacy policy")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.white.opacity(0.8))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.white.opacity(0.6))
                            }
                            .padding(.vertical, 8)
                        }
                    }
                    .padding(18)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
            }
        }
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Ride History (polished)

struct RideHistoryItem: Identifiable {
    let id = UUID()
    let date: String
    let time: String
    let pickup: String
    let dropoff: String
    let price: String
    let rideType: String
}

struct RideHistoryView: View {
    private let history: [RideHistoryItem] = [
        RideHistoryItem(
            date: "Nov 28, 2025",
            time: "5:42 PM",
            pickup: "Downtown Chicago",
            dropoff: "O'Hare International Airport",
            price: "$32.40",
            rideType: "LumoX"
        ),
        RideHistoryItem(
            date: "Nov 26, 2025",
            time: "8:12 PM",
            pickup: "West Loop",
            dropoff: "UIC Campus",
            price: "$14.90",
            rideType: "Saver"
        ),
        RideHistoryItem(
            date: "Nov 20, 2025",
            time: "3:05 PM",
            pickup: "Lincoln Park",
            dropoff: "Downtown Chicago",
            price: "$18.60",
            rideType: "LumoXL"
        )
    ]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if history.isEmpty {
                VStack(spacing: 8) {
                    Text("No rides yet")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                    Text("Your past trips will show up here.")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.6))
                }
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        ForEach(history) { ride in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text(ride.rideType)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.white)
                                    Spacer()
                                    Text(ride.price)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.white)
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(ride.date) • \(ride.time)")
                                        .font(.system(size: 12))
                                        .foregroundColor(.white.opacity(0.6))

                                    Text("From: \(ride.pickup)")
                                        .font(.system(size: 13))
                                        .foregroundColor(.white.opacity(0.85))

                                    Text("To: \(ride.dropoff)")
                                        .font(.system(size: 13))
                                        .foregroundColor(.white.opacity(0.85))
                                }
                            }
                            .padding(14)
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                }
            }
        }
        .navigationTitle("Ride history")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Notifications (polished)

struct NotificationsView: View {
    @State private var tripUpdates: Bool = true
    @State private var driverArriving: Bool = true
    @State private var promotions: Bool = true
    @State private var productUpdates: Bool = false
    @State private var sms: Bool = false
    @State private var email: Bool = true

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {

                    // MARK: - In-app & push
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Trip notifications")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)

                        Toggle(isOn: $tripUpdates) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Trip status updates")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.white)
                                Text("Driver assigned, ride started, cancellations, and more.")
                                    .font(.system(size: 12))
                                    .foregroundColor(.white.opacity(0.6))
                            }
                        }
                        .toggleStyle(SwitchToggleStyle(tint: .white))

                        Divider().background(Color.white.opacity(0.15))

                        Toggle(isOn: $driverArriving) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Driver arrival alerts")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.white)
                                Text("Get notified when your driver is nearby.")
                                    .font(.system(size: 12))
                                    .foregroundColor(.white.opacity(0.6))
                            }
                        }
                        .toggleStyle(SwitchToggleStyle(tint: .white))
                    }
                    .padding(18)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .padding(.horizontal, 20)

                    // MARK: - Marketing
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Promotions & news")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)

                        Toggle(isOn: $promotions) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Promotions and discounts")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.white)
                                Text("Get notified when there are offers in your area.")
                                    .font(.system(size: 12))
                                    .foregroundColor(.white.opacity(0.6))
                            }
                        }
                        .toggleStyle(SwitchToggleStyle(tint: .white))

                        Divider().background(Color.white.opacity(0.15))

                        Toggle(isOn: $productUpdates) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Product updates")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.white)
                                Text("New features, app changes, and important announcements.")
                                    .font(.system(size: 12))
                                    .foregroundColor(.white.opacity(0.6))
                            }
                        }
                        .toggleStyle(SwitchToggleStyle(tint: .white))
                    }
                    .padding(18)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .padding(.horizontal, 20)

                    // MARK: - Channels
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Channels")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)

                        Toggle(isOn: $sms) {
                            Text("SMS text messages")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.white)
                        }
                        .toggleStyle(SwitchToggleStyle(tint: .white))

                        Toggle(isOn: $email) {
                            Text("Email")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.white)
                        }
                        .toggleStyle(SwitchToggleStyle(tint: .white))
                    }
                    .padding(18)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Support (polished)

struct SupportView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {

                    // MARK: - Quick actions
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Need help with a trip?")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)

                        Button {
                            print("Help with recent trip tapped")
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Help with a recent trip")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(.white)
                                    Text("Report an issue, missing item, or incorrect charge.")
                                        .font(.system(size: 12))
                                        .foregroundColor(.white.opacity(0.6))
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.white.opacity(0.6))
                            }
                            .padding(12)
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                        }
                    }
                    .padding(18)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .padding(.horizontal, 20)

                    // MARK: - Help topics
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Help topics")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)

                        SupportRow(title: "Payment & charges", subtitle: "Refunds, receipts, and payment methods")
                        SupportRow(title: "Account & login", subtitle: "Phone number, email, and profile")
                        SupportRow(title: "Safety & security", subtitle: "Reporting issues, emergency options")
                        SupportRow(title: "Using Lumo", subtitle: "How rides, pickups, and ETA work")
                    }
                    .padding(18)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .padding(.horizontal, 20)

                    // MARK: - Contact support
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Contact")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)

                        Button {
                            print("Contact support tapped")
                        } label: {
                            HStack {
                                Image(systemName: "envelope.fill")
                                    .foregroundColor(.black)
                                    .padding(10)
                                    .background(Color.white)
                                    .clipShape(Circle())

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Message support")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(.white)
                                    Text("We’ll get back to you as soon as possible.")
                                        .font(.system(size: 12))
                                        .foregroundColor(.white.opacity(0.6))
                                }

                                Spacer()
                            }
                            .padding(12)
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                        }
                    }
                    .padding(18)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
            }
        }
        .navigationTitle("Support")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SupportRow: View {
    let title: String
    let subtitle: String

    var body: some View {
        Button {
            print("\(title) tapped")
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.6))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(10)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }
}

// MARK: - Legal (polished)

private enum LegalDocument: CaseIterable, Hashable, Identifiable {
    case termsOfService
    case privacyPolicy
    case communityGuidelines
    case licenses

    var id: String { title }

    var title: String {
        switch self {
        case .termsOfService:
            return "Terms of Service"
        case .privacyPolicy:
            return "Privacy Policy"
        case .communityGuidelines:
            return "Community Guidelines"
        case .licenses:
            return "Licenses"
        }
    }

    var subtitle: String {
        switch self {
        case .termsOfService:
            return "Your agreement with Lumo"
        case .privacyPolicy:
            return "How we handle your data"
        case .communityGuidelines:
            return "Rules for using Lumo"
        case .licenses:
            return "Open-source components and licenses"
        }
    }

    var body: String {
        switch self {
        case .termsOfService:
            return """
            Welcome to Lumo. By using Lumo, you agree to use the app responsibly and follow these terms.

            Lumo connects riders with independent drivers for transportation requests. Ride availability, pickup times, prices, and driver availability may vary.

            You are responsible for providing accurate pickup and dropoff information. You agree not to misuse the app, create false ride requests, harass drivers or riders, or use Lumo for illegal activity.

            Drivers using Lumo are responsible for following local laws, maintaining valid licenses, insurance, and vehicle requirements, and providing safe transportation.

            Payments made through Lumo must be valid and authorized. If a payment fails, the ride may not be confirmed.

            Lumo may suspend or remove accounts that violate these terms, create safety concerns, commit fraud, or misuse the platform.

            Lumo may update these terms from time to time. Continued use of the app means you accept the updated terms.

            If you do not agree with these terms, please stop using Lumo.
            """
        case .privacyPolicy:
            return """
            Lumo respects your privacy. This policy explains how we handle information used to provide rides and app features.

            We may collect information such as your name, phone number, email address, profile photo, pickup and dropoff locations, ride history, payment status, device information, app activity, messages, and support information.

            We use this information to create and manage accounts, connect riders and drivers, process rides, improve safety, provide support, send notifications, prevent fraud, and improve Lumo.

            Location information may be used while the app is active and, when needed, during active rides to show pickup, dropoff, driver movement, routing, and trip progress.

            Payment details are processed through Stripe. Lumo does not store full card numbers in the app.

            Messages, call-related records, and ride information may be used to support safety, customer support, and dispute review.

            We do not sell your personal information. We may share information with service providers such as payment processors, cloud hosting, maps, notifications, and safety/support tools only as needed to operate Lumo.

            You may request help with your account, data, or privacy questions by contacting Lumo support.
            """
        case .communityGuidelines:
            return """
            Lumo is built for safe, respectful transportation. Riders and drivers must treat each other with respect.

            Do not threaten, harass, discriminate against, abuse, or endanger another person.

            Do not request or provide rides for illegal activity. Do not bring dangerous items, weapons, illegal substances, or unsafe behavior into a ride.

            Riders should be ready at the pickup location, provide accurate trip details, and respect the driver's vehicle.

            Drivers should drive safely, follow traffic laws, keep the vehicle clean, and communicate professionally.

            Both riders and drivers should use in-app communication respectfully and only for trip-related needs.

            Unsafe driving, fraud, false reports, repeated cancellations, harassment, or platform misuse may lead to account review, suspension, or removal.

            If there is an emergency, contact local emergency services immediately.
            """
        case .licenses:
            return """
            Lumo uses third-party services and open-source components to provide app features.

            These may include services and SDKs for maps, navigation, authentication, cloud hosting, notifications, payments, analytics, and app infrastructure.

            Examples may include:
            - Google Maps and Google Navigation services
            - Firebase services
            - Supabase services
            - Stripe payment services
            - Apple iOS frameworks
            - Open-source Swift packages used in the app

            Each third-party service or open-source library is owned by its respective provider and may be subject to its own license terms.

            This page is provided for transparency. Additional license notices may be added as the app is updated.
            """
        }
    }
}

struct LegalView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 24) {

                VStack(alignment: .leading, spacing: 8) {
                    Text("Legal documents")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)

                    Text("Review the terms that apply to your use of Lumo.")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.6))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 16)

                VStack(spacing: 10) {
                    ForEach(LegalDocument.allCases) { document in
                        NavigationLink {
                            LegalDocumentDetailView(document: document)
                        } label: {
                            LegalRow(title: document.title, subtitle: document.subtitle)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)

                Spacer()
            }
        }
        .navigationTitle("Legal")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct LegalRow: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.6))
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundColor(.white.opacity(0.6))
        }
        .padding(12)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct LegalDocumentDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let document: LegalDocument

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 20) {
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Back")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Color.white.opacity(0.10))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 16)

                Text(document.title)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ScrollView(showsIndicators: false) {
                    Text(document.body)
                        .font(.system(size: 15, weight: .regular))
                        .lineSpacing(7)
                        .foregroundColor(.white.opacity(0.78))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .multilineTextAlignment(.leading)
                        .padding(.bottom, 32)
                }
            }
            .padding(.horizontal, 20)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }
}

// MARK: - Delivery (Uber Eats-inspired MVP)

private struct DeliveryCategoryChip: View {
    let title: String
    let isSelected: Bool
    let tapped: () -> Void

    var body: some View {
        Button(action: tapped) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(isSelected ? .black : .white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? Color.white : Color.white.opacity(0.10))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct DeliveryRestaurantCard: View {
    let name: String
    let cuisine: String
    let eta: String
    let fee: String
    let isOpen: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(name)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)

                    Text(cuisine)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.65))
                }

                Spacer()

                Text(isOpen ? "Open" : "Closed")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isOpen ? .green : .white.opacity(0.5))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
            }

            HStack(spacing: 10) {
                Label(eta, systemImage: "clock")
                Text("•")
                    .foregroundColor(.white.opacity(0.35))
                Label(fee, systemImage: "bicycle")
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.white.opacity(0.75))
        }
        .padding(16)
        .background(Color.white.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

private struct DeliveryMenuRow: View {
    let title: String
    let desc: String
    let price: String
    let addTapped: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)

                Text(desc)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(2)

                Text(price)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white.opacity(0.9))
            }

            Spacer()

            Button(action: addTapped) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.black)
                    .frame(width: 34, height: 34)
                    .background(Color.white)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Delivery Models

struct LumoMerchant: Identifiable, Hashable {
    let id: String
    let name: String
    let cuisine: String
    let etaMins: Int
    let deliveryFee: Double
    let isOpen: Bool
    let categories: [String]
    let menuSections: [LumoMenuSection]
}

struct LumoMenuSection: Identifiable, Hashable {
    let id: String
    let title: String
    let items: [LumoMenuItem]
}

struct LumoMenuItem: Identifiable, Hashable {
    let id: String
    let title: String
    let description: String
    let price: Double
}

struct LumoCartItem: Identifiable, Hashable {
    let id: String
    let title: String
    let price: Double
    var qty: Int
}

// MARK: - Delivery Store

@MainActor
final class DeliveryStore: ObservableObject {
    @Published var selectedMode: DeliveryMode = .food
    @Published var searchText: String = ""
    @Published var selectedCategory: String = "All"

    @Published var selectedMerchant: LumoMerchant? = nil
    @Published var cart: [LumoCartItem] = []

    // Checkout
    @Published var dropoffAddress: String = ""
    @Published var notes: String = ""
    @Published var tipCents: Int = 0

    // Package
    @Published var pickupAddress: String = ""
    @Published var packageSize: String = "Small"

    // Order tracking
    @Published var activeOrderId: String? = nil
    @Published var activeOrderStatus: String = ""
    @Published var trackingURL: URL? = nil

    enum DeliveryMode { case food, package }

    @Published private(set) var merchants: [LumoMerchant] = []

    private let db = Firestore.firestore()
    private var merchantsListener: ListenerRegistration? = nil
    private var activeOrderListener: ListenerRegistration? = nil

    func startFirestore() {
        if merchantsListener != nil { return }

        merchantsListener = db.collection("merchants")
            .addSnapshotListener { [weak self] snap, err in
                guard let self else { return }
                guard err == nil, let docs = snap?.documents else {
                    // fallback so UI still runs
                    if self.merchants.isEmpty { self.merchants = self.mockMerchants() }
                    return
                }

                let mapped: [LumoMerchant] = docs.map { d in
                    let data = d.data()
                    let name = data["name"] as? String ?? "Restaurant"
                    let cuisine = data["cuisine"] as? String ?? ""
                    let etaMins = data["etaMins"] as? Int ?? 30
                    let deliveryFee = data["deliveryFee"] as? Double ?? 2.49
                    let isOpen = data["isOpen"] as? Bool ?? true
                    let categories = data["categories"] as? [String] ?? []

                    return LumoMerchant(
                        id: d.documentID,
                        name: name,
                        cuisine: cuisine,
                        etaMins: etaMins,
                        deliveryFee: deliveryFee,
                        isOpen: isOpen,
                        categories: categories,
                        menuSections: [] // load on demand
                    )
                }

                self.merchants = mapped.isEmpty ? self.mockMerchants() : mapped
            }
    }

    func stopFirestore() {
        merchantsListener?.remove()
        merchantsListener = nil
        activeOrderListener?.remove()
        activeOrderListener = nil
    }

    // fallback data (your existing mock data moved into a function)
    private func mockMerchants() -> [LumoMerchant] {
        let burgers = LumoMerchant(
            id: "m_burgers",
            name: "Smash & Co.",
            cuisine: "Burgers • Fries",
            etaMins: 25,
            deliveryFee: 1.49,
            isOpen: true,
            categories: ["Burgers", "American"],
            menuSections: [
                LumoMenuSection(
                    id: "s_popular",
                    title: "Popular",
                    items: [
                        LumoMenuItem(id: "i_smash", title: "Classic Smash Burger", description: "Two patties, cheese, pickles, house sauce.", price: 8.99),
                        LumoMenuItem(id: "i_fries", title: "Crispy Fries", description: "Sea salt, optional spicy seasoning.", price: 3.49)
                    ]
                )
            ]
        )

        let pizza = LumoMerchant(
            id: "m_pizza",
            name: "Night Oven Pizza",
            cuisine: "Pizza • Italian",
            etaMins: 35,
            deliveryFee: 2.99,
            isOpen: true,
            categories: ["Pizza", "Italian"],
            menuSections: [
                LumoMenuSection(
                    id: "s_pies",
                    title: "Pizzas",
                    items: [
                        LumoMenuItem(id: "i_margherita", title: "Margherita", description: "Tomato, mozzarella, basil.", price: 12.99),
                        LumoMenuItem(id: "i_pepperoni", title: "Pepperoni", description: "Pepperoni, mozzarella, oregano.", price: 14.49)
                    ]
                ),
                LumoMenuSection(
                    id: "s_sides",
                    title: "Sides",
                    items: [
                        LumoMenuItem(id: "i_garlic", title: "Garlic Knots", description: "Butter-garlic glaze.", price: 5.49)
                    ]
                )
            ]
        )

        let sushi = LumoMerchant(
            id: "m_sushi",
            name: "Kuro Sushi",
            cuisine: "Sushi • Japanese",
            etaMins: 30,
            deliveryFee: 2.49,
            isOpen: false,
            categories: ["Sushi", "Japanese"],
            menuSections: [
                LumoMenuSection(
                    id: "s_rolls",
                    title: "Rolls",
                    items: [
                        LumoMenuItem(id: "i_california", title: "California Roll", description: "Crab, avocado, cucumber.", price: 7.99),
                        LumoMenuItem(id: "i_spicytuna", title: "Spicy Tuna Roll", description: "Tuna, spicy mayo, scallions.", price: 9.49)
                    ]
                )
            ]
        )

        return [burgers, pizza, sushi]
    }

    var allCategories: [String] {
        let cats = Set(merchants.flatMap { $0.categories })
        return ["All"] + cats.sorted()
    }

    var filteredMerchants: [LumoMerchant] {
        let s = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return merchants.filter { m in
            let matchesSearch = s.isEmpty || m.name.lowercased().contains(s) || m.cuisine.lowercased().contains(s)
            let matchesCat = (selectedCategory == "All") || m.categories.contains(selectedCategory)
            return matchesSearch && matchesCat
        }
    }

    var cartCount: Int { cart.reduce(0) { $0 + $1.qty } }

    var subtotal: Double { cart.reduce(0) { $0 + ($1.price * Double($1.qty)) } }

    var deliveryFee: Double { selectedMerchant?.deliveryFee ?? 2.49 }

    var serviceFee: Double { min(4.99, subtotal * 0.10) }

    var total: Double { subtotal + deliveryFee + serviceFee + (Double(tipCents) / 100.0) }

    func add(item: LumoMenuItem) {
        if let i = cart.firstIndex(where: { $0.id == item.id }) {
            cart[i].qty += 1
        } else {
            cart.append(LumoCartItem(id: item.id, title: item.title, price: item.price, qty: 1))
        }
    }

    func remove(itemId: String) {
        guard let i = cart.firstIndex(where: { $0.id == itemId }) else { return }
        if cart[i].qty > 1 { cart[i].qty -= 1 } else { cart.remove(at: i) }
    }

    func resetAfterOrder() {
        cart.removeAll()
        notes = ""
        tipCents = 0
        selectedMerchant = nil
    }

    func placeFoodOrder() {
        guard let merchant = selectedMerchant else { return }
        let address = dropoffAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else { return }
        guard !cart.isEmpty else { return }

        let uid = Auth.auth().currentUser?.uid ?? "anonymous"

        let items: [[String: Any]] = cart.map {
            ["id": $0.id, "title": $0.title, "price": $0.price, "qty": $0.qty]
        }

        activeOrderStatus = "Placing order…"

        let ref = db.collection("orders").document()
        ref.setData([
            "type": "food",
            "userId": uid,
            "merchantId": merchant.id,
            "merchantName": merchant.name,
            "status": "placed",
            "dropoffAddress": address,
            "notes": notes,
            "tipCents": tipCents,
            "subtotal": subtotal,
            "deliveryFee": deliveryFee,
            "serviceFee": serviceFee,
            "total": total,
            "items": items,
            "createdAt": FieldValue.serverTimestamp()
        ]) { [weak self] err in
            guard let self else { return }
            if let err = err {
                self.activeOrderStatus = "Order failed: \(err.localizedDescription)"
                return
            }
            self.activeOrderId = ref.documentID
            self.activeOrderStatus = "placed"
            self.listenToActiveOrder(orderId: ref.documentID)
        }
    }

    func placePackageOrder() {
        let pickup = pickupAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let dropoff = dropoffAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pickup.isEmpty, !dropoff.isEmpty else { return }

        let uid = Auth.auth().currentUser?.uid ?? "anonymous"

        activeOrderStatus = "Requesting courier…"

        let ref = db.collection("orders").document()
        ref.setData([
            "type": "package",
            "userId": uid,
            "status": "placed",
            "pickupAddress": pickup,
            "dropoffAddress": dropoff,
            "packageSize": packageSize,
            "notes": notes,
            "createdAt": FieldValue.serverTimestamp()
        ]) { [weak self] err in
            guard let self else { return }
            if let err = err {
                self.activeOrderStatus = "Request failed: \(err.localizedDescription)"
                return
            }
            self.activeOrderId = ref.documentID
            self.activeOrderStatus = "placed"
            self.listenToActiveOrder(orderId: ref.documentID)
        }
    }

    func loadMenuIfNeeded(for merchant: LumoMerchant) {
        if !merchant.menuSections.isEmpty { return }

        db.collection("merchants")
            .document(merchant.id)
            .collection("menuItems")
            .whereField("isAvailable", isEqualTo: true)
            .getDocuments { [weak self] snap, err in
                guard let self else { return }
                guard err == nil, let docs = snap?.documents else { return }

                let pairs: [(String, LumoMenuItem)] = docs.compactMap { d in
                    let data = d.data()
                    let sectionRaw = (data["section"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let section = (sectionRaw?.isEmpty == false) ? sectionRaw! : "Popular"

                    let title = (data["title"] as? String) ?? "Item"
                    let desc = (data["description"] as? String) ?? ""
                    let price = (data["price"] as? Double) ?? 0

                    return (section, LumoMenuItem(id: d.documentID, title: title, description: desc, price: price))
                }

                let grouped = Dictionary(grouping: pairs, by: { $0.0 })
                let sections: [LumoMenuSection] = grouped.keys.sorted().map { key in
                    LumoMenuSection(
                        id: "sec_\(key)",
                        title: key,
                        items: (grouped[key] ?? []).map { $0.1 }
                    )
                }

                if let idx = self.merchants.firstIndex(where: { $0.id == merchant.id }) {
                    let old = self.merchants[idx]
                    let updated = LumoMerchant(
                        id: old.id,
                        name: old.name,
                        cuisine: old.cuisine,
                        etaMins: old.etaMins,
                        deliveryFee: old.deliveryFee,
                        isOpen: old.isOpen,
                        categories: old.categories,
                        menuSections: sections
                    )
                    self.merchants[idx] = updated

                    if self.selectedMerchant?.id == updated.id {
                        self.selectedMerchant = updated
                    }
                }
            }
    }

    private func listenToActiveOrder(orderId: String) {
        activeOrderListener?.remove()

        activeOrderListener = db.collection("orders")
            .document(orderId)
            .addSnapshotListener { [weak self] snap, err in
                guard let self else { return }
                guard err == nil, let data = snap?.data() else { return }

                if let status = data["status"] as? String, !status.isEmpty {
                    self.activeOrderStatus = status
                }

                if let tracking = data["trackingURL"] as? String, let url = URL(string: tracking) {
                    self.trackingURL = url
                }
            }
    }
}


// MARK: - Entry point

struct DeliveryRootView: View {
    @StateObject private var store = DeliveryStore()

    var body: some View {
        DeliveryHubView()
            .environmentObject(store)
            .onAppear { store.startFirestore() }
            .onDisappear { store.stopFirestore() }
    }
}


// MARK: - Hub

struct DeliveryHubView: View {
    @EnvironmentObject private var store: DeliveryStore

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Delivery")
                        .font(.system(size: 42, weight: .heavy))
                        .foregroundColor(.white)

                    Text("Food and packages — all in Lumo.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)

                NavigationLink {
                    FoodDeliveryHomeView()
                        .environmentObject(store)
                        .onAppear {
                            store.selectedMode = .food
                        }
                } label: {
                    hubCard(
                        title: "Food",
                        subtitle: "Browse restaurants and order to your door",
                        icon: "fork.knife"
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)

                NavigationLink {
                    PackageDeliveryFormView()
                        .environmentObject(store)
                        .onAppear {
                            store.selectedMode = .package
                        }
                } label: {
                    hubCard(
                        title: "Packages",
                        subtitle: "Send anything — quick pickup and drop-off",
                        icon: "shippingbox"
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)

                Spacer()
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func hubCard(title: String, subtitle: String, icon: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.black)
                .frame(width: 44, height: 44)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)

                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.65))
                    .lineLimit(2)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundColor(.white.opacity(0.35))
        }
        .padding(16)
        .background(Color.white.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22))
    }
}

// MARK: - Food Home

struct FoodDeliveryHomeView: View {
    @EnvironmentObject private var store: DeliveryStore

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        categoryRow

                        VStack(spacing: 12) {
                            ForEach(store.filteredMerchants) { m in
                                NavigationLink {
                                    RestaurantDetailView(merchant: m)
                                        .environmentObject(store)
                                } label: {
                                    DeliveryRestaurantCard(
                                        name: m.name,
                                        cuisine: m.cuisine,
                                        eta: "\(m.etaMins)–\(m.etaMins + 10) min",
                                        fee: String(format: "$%.2f delivery", m.deliveryFee),
                                        isOpen: m.isOpen
                                    )
                                }
                                .buttonStyle(.plain)
                                .simultaneousGesture(TapGesture().onEnded {
                                    store.loadMenuIfNeeded(for: m)
                                })
                                .disabled(!m.isOpen)
                                .opacity(m.isOpen ? 1 : 0.55)
                            }
                        }

                        Spacer(minLength: 26)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 120)
                }

                if store.cartCount > 0 {
                    cartBar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: store.cartCount)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Food")
                .font(.system(size: 38, weight: .heavy))
                .foregroundColor(.white)

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.white.opacity(0.5))

                TextField("Search restaurants or cuisines", text: $store.searchText)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                if !store.searchText.isEmpty {
                    Button { store.searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.white.opacity(0.45))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    private var categoryRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(store.allCategories, id: \.self) { cat in
                    DeliveryCategoryChip(title: cat, isSelected: store.selectedCategory == cat) {
                        store.selectedCategory = cat
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var cartBar: some View {
        NavigationLink {
            DeliveryCartView()
                .environmentObject(store)
        } label: {
            HStack(spacing: 12) {
                Text("\(store.cartCount)")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundColor(.black)
                    .frame(width: 26, height: 26)
                    .background(Color.white)
                    .clipShape(Circle())

                Text("View cart")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.black)

                Spacer()

                Text(String(format: "$%.2f", store.total))
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundColor(.black)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Restaurant Detail

struct RestaurantDetailView: View {
    @EnvironmentObject private var store: DeliveryStore
    let merchant: LumoMerchant

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        header

                        ForEach((store.selectedMerchant?.id == merchant.id ? (store.selectedMerchant?.menuSections ?? merchant.menuSections) : merchant.menuSections)) { section in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(section.title)
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.white)

                                VStack(spacing: 10) {
                                    ForEach(section.items) { item in
                                        DeliveryMenuRow(
                                            title: item.title,
                                            desc: item.description,
                                            price: String(format: "$%.2f", item.price)
                                        ) {
                                            store.add(item: item)
                                        }
                                    }
                                }
                            }
                            .padding(.top, 6)
                        }

                        Spacer(minLength: 26)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 130)
                }

                if store.cartCount > 0 {
                    NavigationLink {
                        DeliveryCartView()
                            .environmentObject(store)
                    } label: {
                        HStack(spacing: 12) {
                            Text("\(store.cartCount)")
                                .font(.system(size: 13, weight: .heavy))
                                .foregroundColor(.black)
                                .frame(width: 26, height: 26)
                                .background(Color.white)
                                .clipShape(Circle())

                            Text("View cart")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.black)

                            Spacer()

                            Text(String(format: "$%.2f", store.total))
                                .font(.system(size: 16, weight: .heavy))
                                .foregroundColor(.black)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .padding(.horizontal, 20)
                        .padding(.bottom, 18)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .onAppear { store.selectedMerchant = merchant }
        .navigationTitle(merchant.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(merchant.name)
                .font(.system(size: 28, weight: .heavy))
                .foregroundColor(.white)

            Text(merchant.cuisine)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.65))

            HStack(spacing: 10) {
                Label("\(merchant.etaMins)–\(merchant.etaMins + 10) min", systemImage: "clock")
                Text("•").foregroundColor(.white.opacity(0.35))
                Label(String(format: "$%.2f", merchant.deliveryFee), systemImage: "bicycle")
                Text("•").foregroundColor(.white.opacity(0.35))
                Label("Top rated", systemImage: "star.fill")
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.white.opacity(0.75))
            .padding(.top, 2)
        }
        .padding(.bottom, 8)
    }
}

// MARK: - Cart

struct DeliveryCartView: View {
    @EnvironmentObject private var store: DeliveryStore

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                Text("Cart")
                    .font(.system(size: 34, weight: .heavy))
                    .foregroundColor(.white)
                    .padding(.top, 10)
                    .padding(.horizontal, 20)

                if store.cart.isEmpty {
                    VStack(spacing: 8) {
                        Text("Your cart is empty")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                        Text("Add items to checkout.")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 20)
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 10) {
                            ForEach(store.cart) { item in
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.title)
                                            .font(.system(size: 15, weight: .bold))
                                            .foregroundColor(.white)

                                        Text(String(format: "$%.2f", item.price))
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(.white.opacity(0.65))
                                    }

                                    Spacer()

                                    HStack(spacing: 10) {
                                        Button { store.remove(itemId: item.id) } label: {
                                            Image(systemName: "minus")
                                                .font(.system(size: 12, weight: .bold))
                                                .foregroundColor(.black)
                                                .frame(width: 30, height: 30)
                                                .background(Color.white)
                                                .clipShape(Circle())
                                        }
                                        .buttonStyle(.plain)

                                        Text("\(item.qty)")
                                            .font(.system(size: 14, weight: .heavy))
                                            .foregroundColor(.white)
                                            .frame(minWidth: 22)

                                        Button {
                                            if let i = store.cart.firstIndex(where: { $0.id == item.id }) {
                                                store.cart[i].qty += 1
                                            }
                                        } label: {
                                            Image(systemName: "plus")
                                                .font(.system(size: 12, weight: .bold))
                                                .foregroundColor(.black)
                                                .frame(width: 30, height: 30)
                                                .background(Color.white)
                                                .clipShape(Circle())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(14)
                                .background(Color.white.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 18))
                            }

                            feeBreakdown

                            NavigationLink {
                                FoodCheckoutView()
                                    .environmentObject(store)
                            } label: {
                                Text("Continue to checkout")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.black)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 18))
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 6)

                            Spacer(minLength: 26)
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 22)
                    }
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var feeBreakdown: some View {
        VStack(spacing: 10) {
            row("Subtotal", String(format: "$%.2f", store.subtotal))
            row("Delivery fee", String(format: "$%.2f", store.deliveryFee))
            row("Service fee", String(format: "$%.2f", store.serviceFee))
            if store.tipCents > 0 {
                row("Tip", String(format: "$%.2f", Double(store.tipCents) / 100.0))
            }
            Divider().background(Color.white.opacity(0.12))
            row("Total", String(format: "$%.2f", store.total), bold: true)
        }
        .padding(14)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func row(_ left: String, _ right: String, bold: Bool = false) -> some View {
        HStack {
            Text(left)
                .font(.system(size: 13, weight: bold ? .bold : .semibold))
                .foregroundColor(.white.opacity(bold ? 0.95 : 0.65))
            Spacer()
            Text(right)
                .font(.system(size: 13, weight: bold ? .bold : .semibold))
                .foregroundColor(.white.opacity(0.95))
        }
    }
}

// MARK: - Food Checkout

struct FoodCheckoutView: View {
    @EnvironmentObject private var store: DeliveryStore
    @State private var showTracking: Bool = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Checkout")
                        .font(.system(size: 34, weight: .heavy))
                        .foregroundColor(.white)
                        .padding(.top, 10)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Drop-off")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white.opacity(0.6))

                        TextField("Enter your address", text: $store.dropoffAddress)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(14)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 18))

                        TextField("Delivery notes (optional)", text: $store.notes)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(14)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                    }
                    .padding(14)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 22))

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Tip")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white.opacity(0.6))

                        HStack(spacing: 10) {
                            tipButton("$0", cents: 0)
                            tipButton("$2", cents: 200)
                            tipButton("$4", cents: 400)
                            tipButton("$6", cents: 600)
                        }
                    }
                    .padding(14)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 22))

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Total")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white.opacity(0.6))

                        Text(String(format: "$%.2f", store.total))
                            .font(.system(size: 26, weight: .heavy, design: .monospaced))
                            .foregroundColor(.white)
                    }
                    .padding(14)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 22))

                    Button {
                        store.placeFoodOrder()
                        showTracking = true
                    } label: {
                        Text("Place order")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(store.dropoffAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.white.opacity(0.35) : Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                    }
                    .disabled(store.dropoffAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    NavigationLink(isActive: $showTracking) {
                        DeliveryTrackingView(jobTypeTitle: "Food delivery")
                            .environmentObject(store)
                    } label: { EmptyView() }

                    Spacer(minLength: 26)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 22)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func tipButton(_ title: String, cents: Int) -> some View {
        Button { store.tipCents = cents } label: {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(store.tipCents == cents ? .black : .white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(store.tipCents == cents ? Color.white : Color.white.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Package Form

struct PackageDeliveryFormView: View {
    @EnvironmentObject private var store: DeliveryStore
    @State private var showTracking: Bool = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Package")
                        .font(.system(size: 34, weight: .heavy))
                        .foregroundColor(.white)
                        .padding(.top, 10)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Pickup")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white.opacity(0.6))

                        TextField("Pickup address", text: $store.pickupAddress)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(14)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 18))

                        Text("Drop-off")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white.opacity(0.6))

                        TextField("Drop-off address", text: $store.dropoffAddress)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(14)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 18))

                        Text("Package size")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white.opacity(0.6))

                        Picker("Size", selection: $store.packageSize) {
                            Text("Small").tag("Small")
                            Text("Medium").tag("Medium")
                            Text("Large").tag("Large")
                        }
                        .pickerStyle(.segmented)

                        TextField("Notes (optional)", text: $store.notes)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(14)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                    }
                    .padding(14)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 22))

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Estimated")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white.opacity(0.6))

                        Text("$8.99")
                            .font(.system(size: 26, weight: .heavy, design: .monospaced))
                            .foregroundColor(.white)

                        Text("Pricing will be distance-based once we connect routing.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .padding(14)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 22))

                    Button {
                        store.placePackageOrder()
                        showTracking = true
                    } label: {
                        Text("Request courier")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(canRequest ? Color.white : Color.white.opacity(0.35))
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                    }
                    .disabled(!canRequest)

                    NavigationLink(isActive: $showTracking) {
                        DeliveryTrackingView(jobTypeTitle: "Package delivery")
                            .environmentObject(store)
                    } label: { EmptyView() }

                    Spacer(minLength: 26)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 22)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var canRequest: Bool {
        !store.pickupAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !store.dropoffAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - Tracking

struct DeliveryTrackingView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: DeliveryStore
    let jobTypeTitle: String

    @State private var showSafari: Bool = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                Text(jobTypeTitle)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.top, 12)
                    .padding(.horizontal, 20)

                VStack(alignment: .leading, spacing: 10) {
                    Text(store.activeOrderId ?? "—")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.75))

                    Text(store.activeOrderStatus.isEmpty ? "Creating delivery…" : store.activeOrderStatus)
                        .font(.system(size: 26, weight: .heavy))
                        .foregroundColor(.white)
                        .minimumScaleFactor(0.85)
                        .lineLimit(2)

                    Text("This screen will update live from Onfleet webhooks once we connect your backend.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }
                .padding(16)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .padding(.horizontal, 20)

                if store.trackingURL != nil {
                    Button { showSafari = true } label: {
                        HStack {
                            Text("Open live tracking")
                                .font(.system(size: 16, weight: .bold))
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 14, weight: .bold))
                        }
                        .foregroundColor(.black)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .padding(.horizontal, 20)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Button { store.resetAfterOrder() } label: {
                    Text("Done")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .padding(.horizontal, 20)
                        .padding(.bottom, 18)
                }
                .buttonStyle(.plain)
            }
        }
        .onReceive(store.$activeOrderStatus) { status in
            if status == "completed" || status == "delivered" {
                dismiss()
            }
        }
        .navigationTitle("Tracking")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showSafari) {
            if let url = store.trackingURL {
                SafariView(url: url).ignoresSafeArea()
            }
        }
    }
}

// MARK: - Safari wrapper

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let vc = SFSafariViewController(url: url)
        vc.preferredControlTintColor = .white
        return vc
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}


// MARK: - Scheduled Ride (Local Storage + Formatting)

private enum RiderScheduledRideKeys {
    static let hasScheduledRide = "lumo_hasScheduledRide"

    // Addresses
    static let pickupAddress = "lumo_scheduledPickupAddress"
    static let dropoffAddress = "lumo_scheduledDropoffAddress"

    // Time (support multiple legacy keys)
    static let pickupTimestamp = "lumo_scheduledPickupTimestamp" // Double (seconds since 1970)
    static let pickupDate = "lumo_scheduledPickupDate"           // Date
    static let pickupISO = "lumo_scheduledPickupISO"             // String
    static let pickupTimeString = "lumo_scheduledPickupTimeString"      // String (e.g. "7:46 PM")
}

private struct RiderScheduledRideSnapshot {
    let pickupAddress: String
    let dropoffAddress: String
    let pickupDate: Date?
}

private enum RiderScheduledRideStorage {

    static func load() -> RiderScheduledRideSnapshot? {
        let d = UserDefaults.standard

        let hasFlag = d.bool(forKey: RiderScheduledRideKeys.hasScheduledRide)

        let pickupAddr = (d.string(forKey: RiderScheduledRideKeys.pickupAddress) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let dropoffAddr = (d.string(forKey: RiderScheduledRideKeys.dropoffAddress) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        let pickupDate: Date? = {
            if let dt = d.object(forKey: RiderScheduledRideKeys.pickupDate) as? Date {
                return dt
            }
            if d.object(forKey: RiderScheduledRideKeys.pickupTimestamp) != nil {
                let ts = d.double(forKey: RiderScheduledRideKeys.pickupTimestamp)
                if ts > 0 { return Date(timeIntervalSince1970: ts) }
            }
            if let iso = d.string(forKey: RiderScheduledRideKeys.pickupISO), !iso.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let f = ISO8601DateFormatter()
                return f.date(from: iso)
            }
            if let s = d.string(forKey: RiderScheduledRideKeys.pickupTimeString), !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // We cannot rebuild a full Date from a time-only string reliably, so keep Date nil.
                return nil
            }
            return nil
        }()

        // Show the pill if either the explicit flag is set OR we have meaningful content.
        let hasContent = !pickupAddr.isEmpty || !dropoffAddr.isEmpty || pickupDate != nil
        guard hasFlag || hasContent else { return nil }

        return RiderScheduledRideSnapshot(
            pickupAddress: pickupAddr.isEmpty ? "Pickup not set" : pickupAddr,
            dropoffAddress: dropoffAddr.isEmpty ? "Drop-off not set" : dropoffAddr,
            pickupDate: pickupDate
        )
    }

    static func formattedPickupTime(_ date: Date?) -> String {
        if let date {
            let f = DateFormatter()
            f.dateStyle = .none
            f.timeStyle = .short
            return f.string(from: date)
        }

        // Fallback if the scheduler saved only a string time.
        let d = UserDefaults.standard
        let s = (d.string(forKey: RiderScheduledRideKeys.pickupTimeString) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.isEmpty { return s }

        return "Not set"
    }

    static func save(pickupAddress: String, dropoffAddress: String, pickupDate: Date?) {
        let d = UserDefaults.standard
        d.set(true, forKey: RiderScheduledRideKeys.hasScheduledRide)
        d.set(pickupAddress, forKey: RiderScheduledRideKeys.pickupAddress)
        d.set(dropoffAddress, forKey: RiderScheduledRideKeys.dropoffAddress)

        if let pickupDate {
            d.set(pickupDate, forKey: RiderScheduledRideKeys.pickupDate)
            d.set(pickupDate.timeIntervalSince1970, forKey: RiderScheduledRideKeys.pickupTimestamp)
            let f = ISO8601DateFormatter()
            d.set(f.string(from: pickupDate), forKey: RiderScheduledRideKeys.pickupISO)

            let df = DateFormatter()
            df.dateStyle = .none
            df.timeStyle = .short
            d.set(df.string(from: pickupDate), forKey: RiderScheduledRideKeys.pickupTimeString)
        }
    }

    static func clear() {
        let d = UserDefaults.standard
        d.set(false, forKey: RiderScheduledRideKeys.hasScheduledRide)
        d.removeObject(forKey: RiderScheduledRideKeys.pickupAddress)
        d.removeObject(forKey: RiderScheduledRideKeys.dropoffAddress)
        d.removeObject(forKey: RiderScheduledRideKeys.pickupTimestamp)
        d.removeObject(forKey: RiderScheduledRideKeys.pickupDate)
        d.removeObject(forKey: RiderScheduledRideKeys.pickupISO)
        d.removeObject(forKey: RiderScheduledRideKeys.pickupTimeString)
    }
}
