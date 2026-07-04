import SwiftUI
import FirebaseCore
import FirebaseAuth
import Stripe
import GoogleMaps
import GoogleSignIn

// MARK: - Firebase / Google App Delegate
class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
    ) -> Bool {

        // Firebase setup
        FirebaseApp.configure()

        // Google Maps setup
        GMSServices.provideAPIKey("AIzaSyBGGtwh_qslNfTnr7jVJD4iYNNPHMbRYXY")

        // If you enabled this earlier for testing, keep it removed for real SMS:
        // Auth.auth().settings?.isAppVerificationDisabledForTesting = true

        return true
    }

    // Firebase Phone Auth: notification handling
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable : Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        if Auth.auth().canHandleNotification(userInfo) {
            completionHandler(.noData)
            return
        }

        completionHandler(.noData)
    }

    // Firebase Auth / reCAPTCHA + Google Sign-In URL handling
    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey : Any] = [:]
    ) -> Bool {

        // 1) Let Google Sign-In try to handle the URL
        if GIDSignIn.sharedInstance.handle(url) {
            return true
        }

        // 2) Let Firebase Phone Auth handle its URLs (reCAPTCHA etc.)
        if Auth.auth().canHandle(url) {
            return true
        }

        return false
    }
}

// MARK: - App Entry
@main
struct LumoApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    // Global navigation + location
    @StateObject private var navigationCoordinator = NavigationCoordinator()
    @StateObject private var locationManager = LumoLocationManager()

    init() {
        // Set your Stripe publishable key here
        StripeAPI.defaultPublishableKey = "pk_test_51SYcoMLxOAYYnBGn6DlClEfr2WdraGlgyntgNM2T9qnogzLbHHxHt1rJTxOhmGOigrN61Cp3ZetxG1pK92UCNe7X00IfuokhdW"
        // or keep your literal key:
        // StripeAPI.defaultPublishableKey = "pk_test_51SYcoM..."
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack(path: $navigationCoordinator.path) {
                SplashScreen()
            }
            .environmentObject(navigationCoordinator)
            .environmentObject(locationManager)
        }
    }
}

