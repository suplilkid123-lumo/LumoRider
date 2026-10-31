import SwiftUI
import Combine
import FirebaseCore
import FirebaseAuth
import Stripe
import GoogleMaps
import GoogleSignIn
import UserNotifications
import FirebaseMessaging
import UIKit

/// Development-only isolated backend selection. Test settings are injected only
/// by the local test build; all normal Debug and Release builds use production.
enum JiyloTestEnvironment {
    private static let productionURL = "https://rpryqbdodbieioebedjg.supabase.co"
    private static let productionAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJwcnlxYmRvZGJpZWlvZWJlZGpnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjUwNjE0MjYsImV4cCI6MjA4MDYzNzQyNn0.8ZTaA1bCyRUKb6U4NNZou6DMfXP3yyE1NeNL8Ljt9as"

    static let isEnabled: Bool = {
        #if DEBUG
        guard Bundle.main.object(forInfoDictionaryKey: "JIYLO_TEST_MODE") as? String == "YES",
              let value = Bundle.main.object(forInfoDictionaryKey: "JIYLO_TEST_BACKEND_URL") as? String,
              let url = URL(string: value),
              url.scheme == "http",
              let host = url.host,
              !host.isEmpty,
              (host == "localhost" || host == "127.0.0.1" || host == "[::1]" || host.hasSuffix(".local") || (host.contains(":") && host.lowercased().hasPrefix("fd"))),
              url.absoluteString != productionURL else {
            return false
        }
        return true
        #else
        return false
        #endif
    }()

    static var isAuthorizedTestRider: Bool {
        #if DEBUG
        return isEnabled
            && FirebaseApp.app()?.options.projectID == "demo-jiylo-test"
            && Auth.auth().currentUser?.email == "rider.jiylo.test@example.invalid"
        #else
        return false
        #endif
    }

    static var supabaseURLString: String {
        guard isEnabled,
              let value = Bundle.main.object(forInfoDictionaryKey: "JIYLO_TEST_BACKEND_URL") as? String else {
            return productionURL
        }
        return value
    }

    static var supabaseAnonKey: String {
        guard isEnabled,
              let value = Bundle.main.object(forInfoDictionaryKey: "JIYLO_TEST_ANON_KEY") as? String,
              !value.isEmpty else {
            return productionAnonKey
        }
        return value
    }

    static var testRiderSignInURL: URL? {
        guard isEnabled,
              let value = Bundle.main.object(forInfoDictionaryKey: "JIYLO_TEST_RIDER_SIGN_IN_URL") as? String else {
            return nil
        }
        return URL(string: value)
    }

    static func configureFirebaseAuthIfNeeded() {
        guard isEnabled,
              let host = Bundle.main.object(forInfoDictionaryKey: "JIYLO_TEST_FIREBASE_HOST") as? String,
              let portText = Bundle.main.object(forInfoDictionaryKey: "JIYLO_TEST_FIREBASE_PORT") as? String,
              let port = Int(portText),
              !host.isEmpty else { return }
        Auth.auth().useEmulator(withHost: host, port: port)
    }
}

@MainActor
private enum RiderRideScreenAwakeController {
    private static let awakeStatuses: Set<String> = [
        "requested", "searching", "accepted", "approaching", "arrived",
        "arrived_at_pickup", "started", "in_progress"
    ]

    static func update(rideID: String?, status: String?, applicationIsActive: Bool) {
        let normalizedRideID = rideID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normalizedStatus = status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let shouldKeepAwake = applicationIsActive
            && !normalizedRideID.isEmpty
            && awakeStatuses.contains(normalizedStatus)

        if UIApplication.shared.isIdleTimerDisabled != shouldKeepAwake {
            UIApplication.shared.isIdleTimerDisabled = shouldKeepAwake
        }
    }

    static func restoreSystemIdleTimer() {
        if UIApplication.shared.isIdleTimerDisabled {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }
}

private struct RiderRideScreenAwakeModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase

    let rideID: String?
    let status: String?

    func body(content: Content) -> some View {
        content
            .onAppear(perform: synchronize)
            .onChange(of: rideID) { _, _ in synchronize() }
            .onChange(of: status) { _, _ in synchronize() }
            .onChange(of: scenePhase) { _, _ in synchronize() }
            .onDisappear {
                RiderRideScreenAwakeController.restoreSystemIdleTimer()
            }
    }

    private func synchronize() {
        RiderRideScreenAwakeController.update(
            rideID: rideID,
            status: status,
            applicationIsActive: scenePhase == .active
        )
    }
}

enum LumoAppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case arabic = "ar"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english:
            return "English"
        case .arabic:
            return "Arabic"
        }
    }

    var nativeName: String {
        switch self {
        case .english:
            return "English"
        case .arabic:
            return "العربية"
        }
    }

    var localeIdentifier: String {
        switch self {
        case .english:
            return "en"
        case .arabic:
            return "ar"
        }
    }

    var locale: Locale {
        Locale(identifier: localeIdentifier)
    }

    var layoutDirection: LayoutDirection {
        isRightToLeft ? .rightToLeft : .leftToRight
    }

    var isRightToLeft: Bool {
        self == .arabic
    }

    fileprivate var semanticContentAttribute: UISemanticContentAttribute {
        isRightToLeft ? .forceRightToLeft : .forceLeftToRight
    }
}

final class LumoLanguageStore: ObservableObject {
    static let selectedLanguageKey = "lumo_selected_language"

    @Published var selectedLanguage: LumoAppLanguage

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let savedRawValue = defaults.string(forKey: Self.selectedLanguageKey)
        let savedLanguage = savedRawValue.flatMap(LumoAppLanguage.init(rawValue:))
        selectedLanguage = savedLanguage ?? .english

        persistAndApply(selectedLanguage)
    }

    var locale: Locale {
        selectedLanguage.locale
    }

    var layoutDirection: LayoutDirection {
        selectedLanguage.layoutDirection
    }

    func select(_ language: LumoAppLanguage) {
        guard selectedLanguage != language else { return }
        selectedLanguage = language
        persistAndApply(language)
    }

    private func persistAndApply(_ language: LumoAppLanguage) {
        defaults.set(language.rawValue, forKey: Self.selectedLanguageKey)
        defaults.set([language.localeIdentifier], forKey: "AppleLanguages")
        Self.applySemanticContentAttribute(language.semanticContentAttribute)
    }

    private static func applySemanticContentAttribute(_ attribute: UISemanticContentAttribute) {
        DispatchQueue.main.async {
            UIView.appearance().semanticContentAttribute = attribute
            UINavigationBar.appearance().semanticContentAttribute = attribute
            UITabBar.appearance().semanticContentAttribute = attribute

            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .forEach { window in
                    window.semanticContentAttribute = attribute
                    window.rootViewController?.view.semanticContentAttribute = attribute
                    window.setNeedsLayout()
                    window.layoutIfNeeded()
                }
        }
    }
}

private enum RiderFirebaseBootstrap {
    // This static initializer is serialized by Swift and is the only place
    // that configures the default Firebase app. Do not probe FirebaseApp.app()
    // here: asking Firebase for a default app before one exists is itself what
    // emits I-COR000003 during launch.
    private static let configureDefaultApp: Void = {
        print("[FirebaseStartup][Rider] configure begin")
        if JiyloTestEnvironment.isEnabled {
            // Auth stores its session under the Google app ID. Give the local
            // emulator a distinct ID so a previously signed-in production
            // rider cannot be reused by an in-place DEBUG test install.
            let options = FirebaseOptions(
                googleAppID: "1:000000000000:ios:0000000000000000",
                gcmSenderID: "000000000000"
            )
            options.projectID = "demo-jiylo-test"
            options.apiKey = "AIza" + String(repeating: "0", count: 35)
            FirebaseApp.configure(options: options)
        } else {
            FirebaseApp.configure()
        }
        JiyloTestEnvironment.configureFirebaseAuthIfNeeded()
        print("[FirebaseStartup][Rider] configure complete")
    }()

    static func ensureConfigured(stage: String) {
        print("[FirebaseStartup][Rider] ensure stage=\(stage)")
        _ = configureDefaultApp
    }
}

@MainActor
final class RiderChatNotificationCoordinator: ObservableObject {
    static let shared = RiderChatNotificationCoordinator()

    @Published private(set) var pendingRideID: String?

    private init() {}

    nonisolated static func payload(from userInfo: [AnyHashable: Any]) -> (rideID: String, messageID: String?)? {
        guard (userInfo["type"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "passenger_chat",
              let rawRideID = (userInfo["ride_id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let rideUUID = UUID(uuidString: rawRideID) else { return nil }
        return (rideUUID.uuidString.lowercased(), userInfo["message_id"] as? String)
    }

    func queueTappedChat(rideID: String) {
        pendingRideID = rideID.lowercased()
    }

    func consume(rideID: String) {
        guard pendingRideID == rideID.lowercased() else { return }
        pendingRideID = nil
    }
}

// MARK: - App Delegate
final class RiderAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate, ObservableObject {
    @Published private(set) var firebaseReady = false
    private var hasAPNSToken = false
    private var authListenerHandle: AuthStateDidChangeListenerHandle?
    private static let notificationInstallationIDKey = "rider_notification_installation_id"

    private var notificationInstallationID: String {
        if let existing = UserDefaults.standard.string(forKey: Self.notificationInstallationIDKey),
           UUID(uuidString: existing) != nil {
            return existing.lowercased()
        }
        let created = UUID().uuidString.lowercased()
        UserDefaults.standard.set(created, forKey: Self.notificationInstallationIDKey)
        return created
    }

    deinit {
        if let authListenerHandle { Auth.auth().removeStateDidChangeListener(authListenerHandle) }
    }

    func application(
        _ application: UIApplication,
        willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // UIKit has attached this UIApplicationDelegate by this point. This is
        // earlier than didFinish, so no SDK proxy or app service can observe an
        // unconfigured default app.
        RiderFirebaseBootstrap.ensureConfigured(stage: "willFinishLaunching")
        return true
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {

        RiderFirebaseBootstrap.ensureConfigured(stage: "didFinishLaunching")
        firebaseReady = true

        // The isolated test build never registers its APNs/FCM token with the
        // hosted project. Test rides use local-only state and have no remote
        // push delivery side effects.
        if JiyloTestEnvironment.isEnabled {
            GMSServices.provideAPIKey("AIzaSyBGGtwh_qslNfTnr7jVJD4iYNNPHMbRYXY")
            return true
        }

        // ✅ Push Notifications (FCM)
        UNUserNotificationCenter.current().delegate = self
        print("[FirebaseStartup][Rider] first Messaging access")
        Messaging.messaging().delegate = self

        // Ensure Messaging initializes automatically
        Messaging.messaging().isAutoInitEnabled = true

        // Ask permission
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if let error = error {
                print("🔴 Push permission error: \(error)")
            }

            DispatchQueue.main.async {
                application.registerForRemoteNotifications()
                // The Firebase delegate proxy can receive the APNs token even
                // when UIKit does not call this app delegate's registration
                // method. Reconcile that token before uploading an FCM token.
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    self.reconcileMessagingAPNsToken(attempt: 0)
                }

                // FCM registration waits for an APNs token from UIKit or the
                // Firebase Messaging delegate proxy.
            }
        }

        // Phone authentication must use Firebase's normal APNs/reCAPTCHA app
        // verification flow. Only an isolated test target should opt out.

        // ✅ Google Maps
        GMSServices.provideAPIKey("AIzaSyBGGtwh_qslNfTnr7jVJD4iYNNPHMbRYXY")

        // Upload cached FCM token as soon as we have a logged-in user
        print("[FirebaseStartup][Rider] first Auth access")
        authListenerHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let uid = user?.uid, !uid.isEmpty else { return }
            let cachedToken = UserDefaults.standard.string(forKey: "lumo_fcm_token") ?? ""
            guard !cachedToken.isEmpty else { return }

            Task { @MainActor in
                await self?.uploadDeviceTokenIfPossible(cachedToken)
            }
        }

        if let launchPayload = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
            logPassengerChatNotification("launch", userInfo: launchPayload)
            if let payload = RiderChatNotificationCoordinator.payload(from: launchPayload) {
                Task { @MainActor in
                    RiderChatNotificationCoordinator.shared.queueTappedChat(rideID: payload.rideID)
                }
            }
        }

        return true
    }

    // ✅ Firebase + Google Sign-In URL handling
    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey : Any] = [:]
    ) -> Bool {

        if GIDSignIn.sharedInstance.handle(url) {
            return true
        }

        return Auth.auth().canHandle(url)
    }

    // ✅ APNs token -> Firebase Messaging
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // Firebase's enabled AppDelegate proxy forwards APNs to Auth. Avoid
        // forwarding it twice or guessing the APNs environment from DEBUG.
        Messaging.messaging().apnsToken = deviceToken
        hasAPNSToken = true
        print("[RiderChatPush] APNs token assigned; requesting FCM token")

        // Force refresh token after APNs token is set
        Messaging.messaging().token { token, err in
            if let err = err {
                print("🔴 FCM token refresh error: \(err)")
                return
            }
            guard let token = token, !token.isEmpty else {
                print("🔴 FCM token refresh returned empty")
                return
            }
            UserDefaults.standard.set(token, forKey: "lumo_fcm_token")
            Task { @MainActor in
                await self.uploadDeviceTokenIfPossible(token)
            }
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("🔴 Failed to register for remote notifications: \(error)")
    }

    private func reconcileMessagingAPNsToken(attempt: Int) {
        guard !hasAPNSToken else { return }
        guard Messaging.messaging().apnsToken != nil else {
            if attempt < 3 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    self.reconcileMessagingAPNsToken(attempt: attempt + 1)
                }
            }
            return
        }
        hasAPNSToken = true
        print("[RiderChatPush] APNs token recovered from Firebase Messaging")
        Messaging.messaging().token { token, error in
            if let error {
                print("🔴 FCM token recovery error: \(error)")
                return
            }
            guard let token, !token.isEmpty else { return }
            UserDefaults.standard.set(token, forKey: "lumo_fcm_token")
            Task { @MainActor in
                await self.uploadDeviceTokenIfPossible(token)
            }
        }
    }

    // ✅ FCM token
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        if messaging.apnsToken != nil { hasAPNSToken = true }
        guard hasAPNSToken else { return }
        guard let fcmToken = fcmToken, !fcmToken.isEmpty else { return }

        // Cache locally so we can upload after login
        UserDefaults.standard.set(fcmToken, forKey: "lumo_fcm_token")
        print("[RiderChatPush] FCM token received; authenticated registration queued")

        Task { @MainActor in
            await self.uploadDeviceTokenIfPossible(fcmToken)
        }
    }

    // Show notification while app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        logPassengerChatNotification("foreground-willPresent", userInfo: notification.request.content.userInfo)
        completionHandler([.banner, .sound, .badge])
    }

    @MainActor
    private func uploadDeviceTokenIfPossible(_ token: String) async {
        guard hasAPNSToken,
              let user = Auth.auth().currentUser,
              !user.uid.isEmpty else {
            // User not logged in yet; keep token cached.
            return
        }
        do {
            let idToken = try await user.getIDToken(forcingRefresh: true)
            guard Auth.auth().currentUser?.uid == user.uid else { return }
            await upsertDeviceTokenToSupabase(fcmToken: token, idToken: idToken, userID: user.uid)
        } catch {
            // Retain the cached FCM token; a later authenticated callback will retry.
            print("🔴 Rider notification authentication is not ready: \(error)")
        }
    }

    @MainActor
    private func upsertDeviceTokenToSupabase(fcmToken: String, idToken: String, userID: String) async {
        let supabaseProjectURL = "https://rpryqbdodbieioebedjg.supabase.co"
        let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJwcnlxYmRvZGJpZWlvZWJlZGpnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjUwNjE0MjYsImV4cCI6MjA4MDYzNzQyNn0.8ZTaA1bCyRUKb6U4NNZou6DMfXP3yyE1NeNL8Ljt9as"

        guard let baseURL = URL(string: supabaseProjectURL) else { return }
        let url = baseURL.appendingPathComponent("rest/v1/rpc/register_rider_notification_token_v1")

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")

        do {
            req.httpBody = try JSONSerialization.data(withJSONObject: [
                "p_token": fcmToken,
                "p_installation_id": notificationInstallationID
            ], options: [])
            let (data, response) = try await URLSession.shared.data(for: req)
            guard Auth.auth().currentUser?.uid == userID else { return }
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            if !(200...299).contains(code) {
                // PostgREST returns a structured error here. It contains no
                // credential material, but cap it so diagnostics remain safe
                // and useful without ever logging an FCM token or ID token.
                let detail = String(decoding: data, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let safeDetail = String(detail.prefix(512))
                print("🔴 Supabase token upsert failed: HTTP \(code)\(safeDetail.isEmpty ? "" : " response=\(safeDetail)")")
            } else {
                print("[RiderChatPush] token registration succeeded installation=\(notificationInstallationID)")
            }
        } catch {
            print("🔴 Supabase token upsert error: \(error)")
        }
    }

    // ✅ Firebase Phone Auth – forward push notifications to FirebaseAuth
    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable : Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {

        if Auth.auth().canHandleNotification(userInfo) {
            // FirebaseAuth handled this notification (used for phone auth)
            completionHandler(.noData)
            return
        }

        logPassengerChatNotification("background-received", userInfo: userInfo)
        completionHandler(.newData)
    }

    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable : Any]) {

        if Auth.auth().canHandleNotification(userInfo) {
            // FirebaseAuth handled it, nothing else to do
            return
        }

        logPassengerChatNotification("background-received", userInfo: userInfo)
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        logPassengerChatNotification("tap", userInfo: userInfo)
        if let payload = RiderChatNotificationCoordinator.payload(from: userInfo) {
            Task { @MainActor in
                RiderChatNotificationCoordinator.shared.queueTappedChat(rideID: payload.rideID)
            }
        }
        completionHandler()
    }

    private func logPassengerChatNotification(_ event: String, userInfo: [AnyHashable: Any]) {
        guard let payload = RiderChatNotificationCoordinator.payload(from: userInfo) else { return }
        print("[RiderChatPush] \(event) type=passenger_chat ride=\(payload.rideID) message=\(payload.messageID ?? "missing")")
    }
}

// MARK: - App Entry Point
@main
struct LumoApp: App {

    @UIApplicationDelegateAdaptor(RiderAppDelegate.self) var delegate

    @StateObject private var navigationCoordinator = NavigationCoordinator()
    @StateObject private var languageStore = LumoLanguageStore()
    @ObservedObject private var rideService = SupabaseRideService.shared
    @State private var showLaunchAnimation = true

    init() {
        // Keep the SDK and payment screen on one explicitly configured key.
        StripeAPI.defaultPublishableKey = StripeConfig.publishableKey

        guard let agoraAppID = Bundle.main.object(
            forInfoDictionaryKey: "AgoraAppID"
        ) as? String,
        !agoraAppID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            assertionFailure("AgoraAppID is missing from Info settings.")
            return
        }

        AgoraCallManager.shared.configure(appId: agoraAppID)
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if delegate.firebaseReady {
                #if DEBUG
                if JiyloTestEnvironment.isEnabled && ProcessInfo.processInfo.arguments.contains("--jiylo-payment-smoke") {
                    JiyloPaymentSmokeView()
                        .environmentObject(languageStore)
                } else {
                    normalRoot
                }
                #else
                normalRoot
                #endif
                } else {
                    Color.black.ignoresSafeArea()
                }

                if showLaunchAnimation {
                    LumoLaunchView(isPresented: $showLaunchAnimation)
                        .zIndex(1)
                }
            }
            .modifier(RiderRideScreenAwakeModifier(
                rideID: rideService.activeRideID,
                status: rideService.activeRideStatus
            ))
        }
    }

    private var normalRoot: some View {
                NavigationStack(path: $navigationCoordinator.path) {
                    SplashScreen()
                }
                .environmentObject(navigationCoordinator)
                .environmentObject(languageStore)
                .environment(\.locale, languageStore.locale)
                .environment(\.layoutDirection, languageStore.layoutDirection)
    }
}

#if DEBUG
/// Physical-device regression route. It is unavailable outside the isolated
/// local test build and signs in only to the Firebase Auth emulator.
private struct JiyloPaymentSmokeView: View {
    @State private var ready = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            if ready {
                AddPaymentView(
                    pickupAddress: "TEST Chicago pickup",
                    dropoffAddress: "TEST Chicago destination",
                    pickupLat: 41.8780,
                    pickupLng: -87.6298,
                    dropoffLat: 41.8850,
                    dropoffLng: -87.6200,
                    rideTypeLabel: "JiyloX"
                )
            } else {
                Text(errorText ?? "Signing in to isolated Test Rider…")
                    .task { await signIn() }
            }
        }
    }

    private func signIn() async {
        guard let url = JiyloTestEnvironment.testRiderSignInURL else {
            errorText = "The isolated Test Rider endpoint is unavailable."
            return
        }
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let token = object["customToken"] as? String else {
                throw URLError(.userAuthenticationRequired)
            }
            _ = try await Auth.auth().signIn(withCustomToken: token)
            ready = true
        } catch {
            let ns = error as NSError
            print("[JiyloPaymentSmoke] sign-in error domain=\(ns.domain) code=\(ns.code) message=\(ns.localizedDescription)")
            errorText = "Test Rider sign-in failed (\(ns.domain) \(ns.code))."
        }
    }
}
#endif
