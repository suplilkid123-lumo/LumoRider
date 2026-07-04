import SwiftUI
import MapKit
import CoreLocation
import Combine
import PhotosUI
import UIKit
import FirebaseAuth

struct HomeView: View {

    @State private var isNow: Bool = true

    // Center of the map (for Google Maps)
    @State private var mapCenter = CLLocationCoordinate2D(latitude: 41.8781, longitude: -87.6298)

    @StateObject private var locationManager = LumoLocationManager()
    @State private var hasCenteredOnce = false
    @State private var showDestinationSearch = false
    @State private var isMapFullScreen = false
    @State private var showProfileMenu = false
    @State private var logoutTriggered: Bool = false

    var body: some View {
        ZStack {
            NavigationLink(destination: GetStartedView(), isActive: $logoutTriggered) {
                EmptyView()
            }
            .hidden()
            .animation(.none, value: logoutTriggered)   // 👈 no animation on logout navigation

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
                        .shadow(color: Color.white.opacity(0.05), radius: 12, y: 4)
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

                        Button {
                            isNow = false
                        } label: {
                            NavigationLink(destination: ScheduleRideView()) {
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
                        }

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
                    .shadow(color: Color.white.opacity(0.05), radius: 20, y: 6)
                    .padding(.horizontal, 24)

                    // MARK: — MAP SECTION
                    ZStack(alignment: .topTrailing) {
                        GoogleMapView(centerCoordinate: mapCenter)
                            .frame(height: 330)
                            .clipShape(RoundedRectangle(cornerRadius: 34))
                            .shadow(color: Color.white.opacity(0.08), radius: 20, y: 6)

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

                            NavigationLink {
                                ProfileView()
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
                                AddPaymentView()
                            } label: {
                                Text("Payments")
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
        .onReceive(locationManager.$region.compactMap { $0 }) { region in
            if !hasCenteredOnce {
                mapCenter = region.center
                hasCenteredOnce = true
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: — FULL SCREEN MAP OVERLAY
    private var fullScreenMapOverlay: some View {
        Group {
            if isMapFullScreen {
                ZStack {
                    GoogleMapView(centerCoordinate: mapCenter)
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

    private func recenter() {
        if let region = locationManager.region {
            withAnimation {
                mapCenter = region.center
                hasCenteredOnce = true
            }
        }
    }
}

#Preview {
    NavigationStack { HomeView() }
}

// MARK: - Profile

struct ProfileView: View {
    // MARK: - Mock user data (later you can bind these to real user info)
    @State private var fullName: String = "Your name"
    @State private var email: String = ""
    @State private var phoneNumber: String = "+1 (312) 555-0123"

    @State private var preferredRideType: String = "LumoX"
    @State private var countryRegion: String = "United States"
    @State private var memberSince: String = ""

    // Profile photo state
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var profileImageData: Data?
    private let profileImageDefaultsKey = "lumo_profileImageData"

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
                        Button {
                            // Local log out button (for later if you want)
                            print("Log out tapped in Profile")
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
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
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

// MARK: - Payments (placeholder, you already use AddPaymentView elsewhere)

struct PaymentsView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Text("Payments")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white)
        }
        .navigationTitle("Payments")
        .navigationBarTitleDisplayMode(.inline)
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
                    LegalRow(title: "Terms of Service", subtitle: "Your agreement with Lumo")
                    LegalRow(title: "Privacy Policy", subtitle: "How we handle your data")
                    LegalRow(title: "Community Guidelines", subtitle: "Rules for using Lumo")
                    LegalRow(title: "Licenses", subtitle: "Open-source components and licenses")
                }
                .padding(.horizontal, 20)

                Spacer()
            }
        }
        .navigationTitle("Legal")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct LegalRow: View {
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
            .padding(12)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
}
