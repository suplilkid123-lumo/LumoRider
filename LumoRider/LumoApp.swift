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
        defaults.synchronize()
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

// MARK: - App Delegate
class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {

        // ✅ Firebase
        FirebaseApp.configure()
        UNUserNotificationCenter.current().delegate = self

        // ✅ Push Notifications (FCM)
        UNUserNotificationCenter.current().delegate = self
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

                // Force-fetch FCM token (helps when delegate callback doesn't fire immediately)
                Messaging.messaging().token { token, err in
                    if let err = err {
                        print("🔴 FCM token fetch error: \(err)")
                        return
                    }
                    guard let token = token, !token.isEmpty else {
                        print("🔴 FCM token fetch returned empty")
                        return
                    }
                    print("✅ FCM Token (forced): \(token)")
                    UserDefaults.standard.set(token, forKey: "lumo_fcm_token")
                    Task { @MainActor in
                        await self.uploadDeviceTokenIfPossible(token)
                    }
                }
            }
        }

        // 🚨 DEV ONLY: disable real phone verification to avoid internal error
        #if DEBUG
        Auth.auth().settings?.isAppVerificationDisabledForTesting = true
        #else
        Auth.auth().settings?.isAppVerificationDisabledForTesting = false
        #endif

        // ✅ Google Maps
        GMSServices.provideAPIKey("AIzaSyBGGtwh_qslNfTnr7jVJD4iYNNPHMbRYXY")

        // Upload cached FCM token as soon as we have a logged-in user
        Auth.auth().addStateDidChangeListener { _, user in
            guard let uid = user?.uid, !uid.isEmpty else { return }
            let cachedToken = UserDefaults.standard.string(forKey: "lumo_fcm_token") ?? ""
            guard !cachedToken.isEmpty else { return }

            Task { @MainActor in
                await self.uploadDeviceTokenIfPossible(cachedToken)
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
        #if DEBUG
        Auth.auth().setAPNSToken(deviceToken, type: .sandbox)
        #else
        Auth.auth().setAPNSToken(deviceToken, type: .prod)
        #endif

        Messaging.messaging().apnsToken = deviceToken

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
            print("✅ FCM Token (after APNs): \(token)")
            UserDefaults.standard.set(token, forKey: "lumo_fcm_token")
            Task { @MainActor in
                await self.uploadDeviceTokenIfPossible(token)
            }
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("🔴 Failed to register for remote notifications: \(error)")
    }

    // ✅ FCM token
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken = fcmToken, !fcmToken.isEmpty else { return }
        print("✅ FCM Token: \(fcmToken)")

        // Cache locally so we can upload after login
        UserDefaults.standard.set(fcmToken, forKey: "lumo_fcm_token")

        Task { @MainActor in
            await self.uploadDeviceTokenIfPossible(fcmToken)
        }
    }

    // Show notification while app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }

    @MainActor
    private func uploadDeviceTokenIfPossible(_ token: String) async {
        guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else {
            // User not logged in yet; keep token cached.
            return
        }
        await upsertDeviceTokenToSupabase(userId: uid, fcmToken: token)
    }

    @MainActor
    private func upsertDeviceTokenToSupabase(userId: String, fcmToken: String) async {
        // NOTE: Update table/column names if your schema differs.
        let supabaseProjectURL = "https://rpryqbdodbieioebedjg.supabase.co"
        let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJwcnlxYmRvZGJpZWlvZWJlZGpnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjUwNjE0MjYsImV4cCI6MjA4MDYzNzQyNn0.8ZTaA1bCyRUKb6U4NNZou6DMfXP3yyE1NeNL8Ljt9as"

        guard let baseURL = URL(string: supabaseProjectURL) else { return }
        var url = baseURL.appendingPathComponent("rest/v1/device_tokens")
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        comps?.queryItems = [
            URLQueryItem(name: "on_conflict", value: "token")
        ]
        if let built = comps?.url { url = built }

        // Upsert by token (requires a unique constraint on token)
        let payload: [[String: Any]] = [[
            "user_id": userId,
            "app": "rider",
            "role": "rider",
            "platform": "ios",
            "token": fcmToken,
            "fcm_token": fcmToken
        ]]

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        req.setValue("resolution=merge-duplicates,return=representation", forHTTPHeaderField: "Prefer")

        do {
            req.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
            let (data, response) = try await URLSession.shared.data(for: req)
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            let body = String(data: data, encoding: .utf8) ?? ""
            if !(200...299).contains(code) {
                print("🔴 Supabase token upsert failed: HTTP \(code) body=\(body)")
            } else {
                print("✅ Uploaded device token to Supabase")
                if !body.isEmpty {
                    print("✅ Supabase response: \(body)")
                }
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

        // Your own notification handling (if any) would go here
        completionHandler(.newData)
    }

    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable : Any]) {

        if Auth.auth().canHandleNotification(userInfo) {
            // FirebaseAuth handled it, nothing else to do
            return
        }

        // Your own handling (if you ever add it) would go here
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}

// MARK: - App Entry Point
@main
struct LumoApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    @StateObject private var navigationCoordinator = NavigationCoordinator()
    @StateObject private var locationManager = LumoLocationManager()
    @StateObject private var languageStore = LumoLanguageStore()

    init() {
        StripeAPI.defaultPublishableKey = "pk_test_51SYcoMLxOAYYnBGn6DlClEfr2WdraGlgyntgNM2T9qnogzLbHHxHt1rJTxOhmGOigrN61Cp3ZetxG1pK92UCNe7X00IfuokhdW"
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack(path: $navigationCoordinator.path) {
                SplashScreen()
            }
            .environmentObject(navigationCoordinator)
            .environmentObject(locationManager)
            .environmentObject(languageStore)
            .environment(\.locale, languageStore.locale)
            .environment(\.layoutDirection, languageStore.layoutDirection)
        }
    }
}
