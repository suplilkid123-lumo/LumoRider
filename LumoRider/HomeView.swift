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

enum LumoSettingsL10n {
    enum Key: String {
        case accountMenuTitle
        case accountMenuProfile
        case accountMenuLanguage
        case accountMenuPrivacy
        case accountMenuRideHistory
        case accountMenuDelivery
        case accountMenuNotifications
        case accountMenuSupport
        case accountMenuLegal
        case accountMenuLogout

        case languageTitle
        case languageSubtitle
        case languageEnglishTitle
        case languageEnglishSubtitle
        case languageArabicTitle
        case languageArabicSubtitle

        case homeRideScheduled
        case homeFromLabel
        case homeToLabel
        case homeSearchPrompt
        case homeNow
        case homeSchedule
        case homePlanRide
        case homePickup
        case homeDropoff
        case homeWhereFrom
        case homeWhereTo
        case homeNotSet
        case homeCurrentLocation
        case homeEnterDestination

        case destinationSetTrip
        case destinationEnterPickup
        case destinationUseCurrentLocation
        case destinationDestination
        case destinationRecentPlaces
        case destinationContinue
        case destinationFindingLocation
        case destinationLocationUnavailable

        case rideOptionsChooseRide
        case rideOptionsChooseButton
        case rideOptionsRideFallback
        case rideOptionsSaverName
        case rideOptionsSaverSubtitle
        case rideOptionsSaverEta
        case rideOptionsShareName
        case rideOptionsShareSubtitle
        case rideOptionsShareEta
        case rideOptionsLumoXName
        case rideOptionsLumoXSubtitle
        case rideOptionsLumoXEta
        case rideOptionsLumoXLName
        case rideOptionsLumoXLSubtitle
        case rideOptionsLumoXLEta
        case rideOptionsFasterBadge

        case confirmPickupBack

        case addPaymentTitle
        case addPaymentApplePayTitle
        case addPaymentApplePaySubtitle
        case addPaymentCashTitle
        case addPaymentCashSubtitle
        case addPaymentSavedCardSubtitle
        case addPaymentDifferentCardTitle
        case addPaymentDifferentCardSubtitle
        case addPaymentTestPaymentTitle
        case addPaymentTestPaymentSubtitle
        case addPaymentScheduleRide
        case addPaymentConfirmRide
        case addPaymentChooseMethodError
        case addPaymentApplePayUnavailableError
        case addPaymentFareUnavailableError
        case addPaymentCouldNotPresentApplePayError
        case addPaymentApplePayConfigError
        case addPaymentApplePayFailedError
        case addPaymentApplePayCancelledError
        case addPaymentServerReachError
        case addPaymentNoInternetError
        case addPaymentRequestTimedOutError
        case addPaymentCouldNotConfirmRideError
        case addPaymentCouldNotConfirmRidePrefix

        case privacyTitle
        case privacyLocationTracking
        case privacyAllowLocationTitle
        case privacyAllowLocationSubtitle
        case privacyDiagnosticsTitle
        case privacyDiagnosticsSubtitle
        case privacyPersonalization
        case privacyPersonalizedSuggestionsTitle
        case privacyPersonalizedSuggestionsSubtitle
        case privacySharePartnersTitle
        case privacySharePartnersSubtitle
        case privacyYourData
        case privacyDownloadDataTitle
        case privacyDownloadDataSubtitle
        case privacyViewPolicyTitle

        case notificationsTitle
        case notificationsTripSection
        case notificationsTripStatusTitle
        case notificationsTripStatusSubtitle
        case notificationsDriverArrivalTitle
        case notificationsDriverArrivalSubtitle
        case notificationsPromotionsSection
        case notificationsPromotionsTitle
        case notificationsPromotionsSubtitle
        case notificationsProductUpdatesTitle
        case notificationsProductUpdatesSubtitle
        case notificationsChannelsSection
        case notificationsSMSTitle
        case notificationsEmailTitle

        case supportTitle
        case supportNeedHelpTitle
        case supportRecentTripTitle
        case supportRecentTripSubtitle
        case supportHelpTopicsTitle
        case supportPaymentChargesTitle
        case supportPaymentChargesSubtitle
        case supportAccountLoginTitle
        case supportAccountLoginSubtitle
        case supportSafetySecurityTitle
        case supportSafetySecuritySubtitle
        case supportUsingLumoTitle
        case supportUsingLumoSubtitle
        case supportContactTitle
        case supportMessageTitle
        case supportMessageSubtitle

        case legalTitle
        case legalDocumentsTitle
        case legalDocumentsSubtitle
        case legalTermsTitle
        case legalTermsSubtitle
        case legalPrivacyTitle
        case legalPrivacySubtitle
        case legalGuidelinesTitle
        case legalGuidelinesSubtitle
        case legalLicensesTitle
        case legalLicensesSubtitle
        case legalBackTitle
    }

    static func text(_ key: Key, language: LumoAppLanguage) -> String {
        if language == .arabic, let value = arabic[key] {
            return value
        }
        return english[key] ?? key.rawValue
    }

    static func languageTitleKey(for language: LumoAppLanguage) -> Key {
        switch language {
        case .english:
            return .languageEnglishTitle
        case .arabic:
            return .languageArabicTitle
        }
    }

    static func languageSubtitleKey(for language: LumoAppLanguage) -> Key {
        switch language {
        case .english:
            return .languageEnglishSubtitle
        case .arabic:
            return .languageArabicSubtitle
        }
    }

    private static let english: [Key: String] = [
        .accountMenuTitle: "Account",
        .accountMenuProfile: "Profile",
        .accountMenuLanguage: "Language",
        .accountMenuPrivacy: "Privacy",
        .accountMenuRideHistory: "Ride history",
        .accountMenuDelivery: "Delivery",
        .accountMenuNotifications: "Notifications",
        .accountMenuSupport: "Support",
        .accountMenuLegal: "Legal",
        .accountMenuLogout: "Log out",

        .languageTitle: "Language",
        .languageSubtitle: "English is default. Arabic is available with right-to-left layout.",
        .languageEnglishTitle: "English",
        .languageEnglishSubtitle: "Default language",
        .languageArabicTitle: "Arabic",
        .languageArabicSubtitle: "Right-to-left layout",

        .homeRideScheduled: "Ride scheduled",
        .homeFromLabel: "From",
        .homeToLabel: "To",
        .homeSearchPrompt: "Where are you going?",
        .homeNow: "Now",
        .homeSchedule: "Schedule",
        .homePlanRide: "Plan your ride",
        .homePickup: "Pickup",
        .homeDropoff: "Dropoff",
        .homeWhereFrom: "Where from?",
        .homeWhereTo: "Where to?",
        .homeNotSet: "Not set",
        .homeCurrentLocation: "Current location",
        .homeEnterDestination: "Enter destination",

        .destinationSetTrip: "Set your trip",
        .destinationEnterPickup: "Enter pickup",
        .destinationUseCurrentLocation: "Use current location",
        .destinationDestination: "Destination",
        .destinationRecentPlaces: "Recent places",
        .destinationContinue: "Continue",
        .destinationFindingLocation: "Finding your location...",
        .destinationLocationUnavailable: "Location unavailable",

        .rideOptionsChooseRide: "Choose a ride",
        .rideOptionsChooseButton: "Choose",
        .rideOptionsRideFallback: "ride",
        .rideOptionsSaverName: "Saver",
        .rideOptionsSaverSubtitle: "More affordable, shared route",
        .rideOptionsSaverEta: "6:15 PM · 8–17 min",
        .rideOptionsShareName: "Share",
        .rideOptionsShareSubtitle: "Share your ride and save 30%",
        .rideOptionsShareEta: "6:15 PM · 8–17 min",
        .rideOptionsLumoXName: "JiyloX",
        .rideOptionsLumoXSubtitle: "Standard ride for up to 4",
        .rideOptionsLumoXEta: "6:03 PM · 7 min",
        .rideOptionsLumoXLName: "JiyloXL",
        .rideOptionsLumoXLSubtitle: "Larger car, up to 6",
        .rideOptionsLumoXLEta: "6:05 PM · 8 min",
        .rideOptionsFasterBadge: "Faster",

        .confirmPickupBack: "Back",

        .addPaymentTitle: "Add payment",
        .addPaymentApplePayTitle: "Apple Pay",
        .addPaymentApplePaySubtitle: "Pay instantly with Apple Wallet",
        .addPaymentCashTitle: "Cash",
        .addPaymentCashSubtitle: "Pay driver directly",
        .addPaymentSavedCardSubtitle: "Card saved locally — re-enter to pay securely",
        .addPaymentDifferentCardTitle: "Use a different card",
        .addPaymentDifferentCardSubtitle: "Add new credit or debit card",
        .addPaymentTestPaymentTitle: "Test payment",
        .addPaymentTestPaymentSubtitle: "Skip payment (debug only)",
        .addPaymentScheduleRide: "Schedule ride",
        .addPaymentConfirmRide: "Confirm ride",
        .addPaymentChooseMethodError: "Please choose a payment method.",
        .addPaymentApplePayUnavailableError: "Apple Pay is not available on this device.",
        .addPaymentFareUnavailableError: "Trip fare is not available yet. Please go back and select the ride again.",
        .addPaymentCouldNotPresentApplePayError: "Could not present Apple Pay.",
        .addPaymentApplePayConfigError: "Apple Pay is not configured correctly.",
        .addPaymentApplePayFailedError: "Apple Pay failed.",
        .addPaymentApplePayCancelledError: "Apple Pay cancelled.",
        .addPaymentServerReachError: "Can’t reach the server. Check your Supabase Project URL and your internet connection.",
        .addPaymentNoInternetError: "No internet connection. Please try again.",
        .addPaymentRequestTimedOutError: "Request timed out. Please try again.",
        .addPaymentCouldNotConfirmRideError: "Couldn’t confirm ride. Please try again.",
        .addPaymentCouldNotConfirmRidePrefix: "Couldn’t confirm ride.",

        .privacyTitle: "Privacy",
        .privacyLocationTracking: "Location & tracking",
        .privacyAllowLocationTitle: "Allow location",
        .privacyAllowLocationSubtitle: "Let Jiylo use your location for pickups and nearby drivers.",
        .privacyDiagnosticsTitle: "Share anonymous diagnostics",
        .privacyDiagnosticsSubtitle: "Help improve Jiylo by sending anonymous crash and performance data.",
        .privacyPersonalization: "Personalization",
        .privacyPersonalizedSuggestionsTitle: "Personalized suggestions",
        .privacyPersonalizedSuggestionsSubtitle: "Use your ride history to improve recommendations.",
        .privacySharePartnersTitle: "Share data with partners",
        .privacySharePartnersSubtitle: "Share limited, anonymized information to improve partner services.",
        .privacyYourData: "Your data",
        .privacyDownloadDataTitle: "Download your data",
        .privacyDownloadDataSubtitle: "Request a copy of your ride and account data.",
        .privacyViewPolicyTitle: "View privacy policy",

        .notificationsTitle: "Notifications",
        .notificationsTripSection: "Trip notifications",
        .notificationsTripStatusTitle: "Trip status updates",
        .notificationsTripStatusSubtitle: "Driver assigned, ride started, cancellations, and more.",
        .notificationsDriverArrivalTitle: "Driver arrival alerts",
        .notificationsDriverArrivalSubtitle: "Get notified when your driver is nearby.",
        .notificationsPromotionsSection: "Promotions & news",
        .notificationsPromotionsTitle: "Promotions and discounts",
        .notificationsPromotionsSubtitle: "Get notified when there are offers in your area.",
        .notificationsProductUpdatesTitle: "Product updates",
        .notificationsProductUpdatesSubtitle: "New features, app changes, and important announcements.",
        .notificationsChannelsSection: "Channels",
        .notificationsSMSTitle: "SMS text messages",
        .notificationsEmailTitle: "Email",

        .supportTitle: "Support",
        .supportNeedHelpTitle: "Need help with a trip?",
        .supportRecentTripTitle: "Help with a recent trip",
        .supportRecentTripSubtitle: "Report an issue, missing item, or incorrect charge.",
        .supportHelpTopicsTitle: "Help topics",
        .supportPaymentChargesTitle: "Payment & charges",
        .supportPaymentChargesSubtitle: "Refunds, receipts, and payment methods",
        .supportAccountLoginTitle: "Account & login",
        .supportAccountLoginSubtitle: "Phone number, email, and profile",
        .supportSafetySecurityTitle: "Safety & security",
        .supportSafetySecuritySubtitle: "Reporting issues, emergency options",
        .supportUsingLumoTitle: "Using Jiylo",
        .supportUsingLumoSubtitle: "How rides, pickups, and ETA work",
        .supportContactTitle: "Contact",
        .supportMessageTitle: "Message support",
        .supportMessageSubtitle: "We'll get back to you as soon as possible.",

        .legalTitle: "Legal",
        .legalDocumentsTitle: "Legal documents",
        .legalDocumentsSubtitle: "Review the terms that apply to your use of Jiylo.",
        .legalTermsTitle: "Terms of Service",
        .legalTermsSubtitle: "Your agreement with Jiylo",
        .legalPrivacyTitle: "Privacy Policy",
        .legalPrivacySubtitle: "How we handle your data",
        .legalGuidelinesTitle: "Community Guidelines",
        .legalGuidelinesSubtitle: "Rules for using Jiylo",
        .legalLicensesTitle: "Licenses",
        .legalLicensesSubtitle: "Open-source components and licenses",
        .legalBackTitle: "Back"
    ]

    private static let arabic: [Key: String] = [
        .accountMenuTitle: "الحساب",
        .accountMenuProfile: "الملف الشخصي",
        .accountMenuLanguage: "اللغة",
        .accountMenuPrivacy: "الخصوصية",
        .accountMenuRideHistory: "سجل الرحلات",
        .accountMenuDelivery: "التوصيل",
        .accountMenuNotifications: "الإشعارات",
        .accountMenuSupport: "الدعم",
        .accountMenuLegal: "المستندات القانونية",
        .accountMenuLogout: "تسجيل الخروج",

        .languageTitle: "اللغة",
        .languageSubtitle: "الإنجليزية هي الافتراضية. العربية متاحة بتخطيط من اليمين إلى اليسار.",
        .languageEnglishTitle: "الإنجليزية",
        .languageEnglishSubtitle: "اللغة الافتراضية",
        .languageArabicTitle: "العربية",
        .languageArabicSubtitle: "تخطيط من اليمين إلى اليسار",

        .homeRideScheduled: "تمت جدولة الرحلة",
        .homeFromLabel: "من",
        .homeToLabel: "إلى",
        .homeSearchPrompt: "إلى أين تريد الذهاب؟",
        .homeNow: "الآن",
        .homeSchedule: "جدولة",
        .homePlanRide: "خطط رحلتك",
        .homePickup: "الانطلاق",
        .homeDropoff: "الوجهة",
        .homeWhereFrom: "من أين؟",
        .homeWhereTo: "إلى أين؟",
        .homeNotSet: "غير محدد",
        .homeCurrentLocation: "الموقع الحالي",
        .homeEnterDestination: "أدخل الوجهة",

        .destinationSetTrip: "حدد رحلتك",
        .destinationEnterPickup: "أدخل موقع الانطلاق",
        .destinationUseCurrentLocation: "استخدم الموقع الحالي",
        .destinationDestination: "الوجهة",
        .destinationRecentPlaces: "الأماكن الأخيرة",
        .destinationContinue: "متابعة",
        .destinationFindingLocation: "جارٍ تحديد موقعك...",
        .destinationLocationUnavailable: "الموقع غير متاح",

        .rideOptionsChooseRide: "اختر رحلة",
        .rideOptionsChooseButton: "اختر",
        .rideOptionsRideFallback: "رحلة",
        .rideOptionsSaverName: "اقتصادي",
        .rideOptionsSaverSubtitle: "أوفر سعراً، مسار مشترك",
        .rideOptionsSaverEta: "6:15 م · 8–17 دقيقة",
        .rideOptionsShareName: "مشترك",
        .rideOptionsShareSubtitle: "شارك الرحلة ووفر 30٪",
        .rideOptionsShareEta: "6:15 م · 8–17 دقيقة",
        .rideOptionsLumoXName: "JiyloX",
        .rideOptionsLumoXSubtitle: "رحلة عادية حتى 4 ركاب",
        .rideOptionsLumoXEta: "6:03 م · 7 دقائق",
        .rideOptionsLumoXLName: "JiyloXL",
        .rideOptionsLumoXLSubtitle: "سيارة أوسع حتى 6 ركاب",
        .rideOptionsLumoXLEta: "6:05 م · 8 دقائق",
        .rideOptionsFasterBadge: "أسرع",

        .confirmPickupBack: "رجوع",

        .addPaymentTitle: "إضافة الدفع",
        .addPaymentApplePayTitle: "Apple Pay",
        .addPaymentApplePaySubtitle: "ادفع فوراً باستخدام Apple Wallet",
        .addPaymentCashTitle: "نقداً",
        .addPaymentCashSubtitle: "ادفع للسائق مباشرة",
        .addPaymentSavedCardSubtitle: "البطاقة محفوظة محلياً — أعد إدخالها للدفع بأمان",
        .addPaymentDifferentCardTitle: "استخدم بطاقة أخرى",
        .addPaymentDifferentCardSubtitle: "أضف بطاقة ائتمان أو خصم جديدة",
        .addPaymentTestPaymentTitle: "دفع تجريبي",
        .addPaymentTestPaymentSubtitle: "تجاوز الدفع (للاختبار فقط)",
        .addPaymentScheduleRide: "جدولة الرحلة",
        .addPaymentConfirmRide: "تأكيد الرحلة",
        .addPaymentChooseMethodError: "يرجى اختيار طريقة دفع.",
        .addPaymentApplePayUnavailableError: "Apple Pay غير متاح على هذا الجهاز.",
        .addPaymentFareUnavailableError: "أجرة الرحلة غير متاحة بعد. يرجى الرجوع واختيار الرحلة مرة أخرى.",
        .addPaymentCouldNotPresentApplePayError: "تعذر عرض Apple Pay.",
        .addPaymentApplePayConfigError: "لم يتم إعداد Apple Pay بشكل صحيح.",
        .addPaymentApplePayFailedError: "فشل Apple Pay.",
        .addPaymentApplePayCancelledError: "تم إلغاء Apple Pay.",
        .addPaymentServerReachError: "تعذر الوصول إلى الخادم. تحقق من رابط مشروع Supabase واتصال الإنترنت.",
        .addPaymentNoInternetError: "لا يوجد اتصال بالإنترنت. يرجى المحاولة مرة أخرى.",
        .addPaymentRequestTimedOutError: "انتهت مهلة الطلب. يرجى المحاولة مرة أخرى.",
        .addPaymentCouldNotConfirmRideError: "تعذر تأكيد الرحلة. يرجى المحاولة مرة أخرى.",
        .addPaymentCouldNotConfirmRidePrefix: "تعذر تأكيد الرحلة.",

        .privacyTitle: "الخصوصية",
        .privacyLocationTracking: "الموقع والتتبع",
        .privacyAllowLocationTitle: "السماح بالموقع",
        .privacyAllowLocationSubtitle: "السماح لـ Jiylo باستخدام موقعك لعمليات الالتقاط والسائقين القريبين.",
        .privacyDiagnosticsTitle: "مشاركة تشخيصات مجهولة",
        .privacyDiagnosticsSubtitle: "ساعد في تحسين Jiylo بإرسال بيانات أعطال وأداء مجهولة.",
        .privacyPersonalization: "التخصيص",
        .privacyPersonalizedSuggestionsTitle: "اقتراحات مخصصة",
        .privacyPersonalizedSuggestionsSubtitle: "استخدام سجل رحلاتك لتحسين التوصيات.",
        .privacySharePartnersTitle: "مشاركة البيانات مع الشركاء",
        .privacySharePartnersSubtitle: "مشاركة معلومات محدودة ومجهولة لتحسين خدمات الشركاء.",
        .privacyYourData: "بياناتك",
        .privacyDownloadDataTitle: "تنزيل بياناتك",
        .privacyDownloadDataSubtitle: "طلب نسخة من بيانات الرحلات والحساب.",
        .privacyViewPolicyTitle: "عرض سياسة الخصوصية",

        .notificationsTitle: "الإشعارات",
        .notificationsTripSection: "إشعارات الرحلات",
        .notificationsTripStatusTitle: "تحديثات حالة الرحلة",
        .notificationsTripStatusSubtitle: "تعيين السائق وبدء الرحلة والإلغاءات والمزيد.",
        .notificationsDriverArrivalTitle: "تنبيهات وصول السائق",
        .notificationsDriverArrivalSubtitle: "تلقي إشعار عندما يكون سائقك قريبًا.",
        .notificationsPromotionsSection: "العروض والأخبار",
        .notificationsPromotionsTitle: "العروض والخصومات",
        .notificationsPromotionsSubtitle: "تلقي إشعار عند توفر عروض في منطقتك.",
        .notificationsProductUpdatesTitle: "تحديثات المنتج",
        .notificationsProductUpdatesSubtitle: "ميزات جديدة وتغييرات في التطبيق وإعلانات مهمة.",
        .notificationsChannelsSection: "القنوات",
        .notificationsSMSTitle: "الرسائل النصية القصيرة",
        .notificationsEmailTitle: "البريد الإلكتروني",

        .supportTitle: "الدعم",
        .supportNeedHelpTitle: "هل تحتاج مساعدة في رحلة؟",
        .supportRecentTripTitle: "المساعدة في رحلة حديثة",
        .supportRecentTripSubtitle: "الإبلاغ عن مشكلة أو غرض مفقود أو رسوم غير صحيحة.",
        .supportHelpTopicsTitle: "مواضيع المساعدة",
        .supportPaymentChargesTitle: "المدفوعات والرسوم",
        .supportPaymentChargesSubtitle: "المبالغ المستردة والإيصالات وطرق الدفع",
        .supportAccountLoginTitle: "الحساب وتسجيل الدخول",
        .supportAccountLoginSubtitle: "رقم الهاتف والبريد الإلكتروني والملف الشخصي",
        .supportSafetySecurityTitle: "السلامة والأمان",
        .supportSafetySecuritySubtitle: "الإبلاغ عن المشكلات وخيارات الطوارئ",
        .supportUsingLumoTitle: "استخدام Jiylo",
        .supportUsingLumoSubtitle: "كيفية عمل الرحلات ونقاط الالتقاط ووقت الوصول المتوقع",
        .supportContactTitle: "التواصل",
        .supportMessageTitle: "مراسلة الدعم",
        .supportMessageSubtitle: "سنرد عليك في أقرب وقت ممكن.",

        .legalTitle: "المستندات القانونية",
        .legalDocumentsTitle: "المستندات القانونية",
        .legalDocumentsSubtitle: "راجع الشروط التي تنطبق على استخدامك لـ Jiylo.",
        .legalTermsTitle: "شروط الخدمة",
        .legalTermsSubtitle: "اتفاقيتك مع Jiylo",
        .legalPrivacyTitle: "سياسة الخصوصية",
        .legalPrivacySubtitle: "كيف نتعامل مع بياناتك",
        .legalGuidelinesTitle: "إرشادات المجتمع",
        .legalGuidelinesSubtitle: "قواعد استخدام Jiylo",
        .legalLicensesTitle: "التراخيص",
        .legalLicensesSubtitle: "مكونات وتراخيص مفتوحة المصدر",
        .legalBackTitle: "رجوع"
    ]
}

extension LumoLanguageStore {
    func settingsText(_ key: LumoSettingsL10n.Key) -> String {
        LumoSettingsL10n.text(key, language: selectedLanguage)
    }
}

private struct HomeContentHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct HomeView: View {
    @EnvironmentObject private var languageStore: LumoLanguageStore
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
    @State private var restoredActiveRide: ActiveRideRecord?
    @State private var restoredAccessToken: String?
    @State private var showRestoredActiveRide = false

    // MARK: - Scheduled pill display text
    private var scheduledPillTimeText: String {
        guard scheduledForEpoch > 0 else { return languageStore.settingsText(.homeNotSet) }
        let d = Date(timeIntervalSince1970: scheduledForEpoch)
        let f = DateFormatter()
        f.locale = .current
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: d)
    }

    private var scheduledPillFromText: String {
        let t = scheduledPickupAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? languageStore.settingsText(.homeCurrentLocation) : t
    }

    private var scheduledPillToText: String {
        let t = scheduledDropoffAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? languageStore.settingsText(.homeEnterDestination) : t
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
    @State private var homeContentHeight: CGFloat?
    @AppStorage("lumo_profileImageData") private var profileImageData: Data = Data()

    private let homeSectionSpacing: CGFloat = 18


    var body: some View {
        GeometryReader { availableSpace in
            ZStack {

            Color.black.ignoresSafeArea()

            VStack(spacing: homeSectionSpacing) {
                    VStack(spacing: homeSectionSpacing) {

                    // MARK: — TOP BAR
                    HStack(spacing: 16) {
                        Text("Jiylo")
                            .font(.system(size: 31, weight: .bold, design: .rounded))
                            .tracking(-0.7)
                            .foregroundColor(.white)

                        Spacer()

                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                showProfileMenu.toggle()
                            }
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(Color.white.opacity(0.12))

                                if let profileImage = UIImage(data: profileImageData) {
                                    Image(uiImage: profileImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 44, height: 44)
                                        .clipShape(Circle())
                                } else {
                                    Image(systemName: "person.fill")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.white)
                                }
                            }
                            .frame(width: 44, height: 44)
                            .clipShape(Circle())
                            .overlay {
                                Circle()
                                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
                            }
                            .accessibilityHidden(true)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(languageStore.settingsText(.accountMenuProfile))
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                    // MARK: — SCHEDULED RIDE PILL
                    if hasScheduledRide && !scheduledRideId.isEmpty {
                        Button {
                            // Jump to the scheduled-ride screen
                            showScheduledRideFromPill = true
                        } label: {
                            HStack(spacing: 13) {
                                Image(systemName: "calendar.badge.clock")
                                    .font(.system(size: 15, weight: .semibold))
                                    .frame(width: 36, height: 36)
                                    .background(Color.white.opacity(0.10), in: Circle())

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(languageStore.settingsText(.homeRideScheduled))
                                        .font(.system(size: 14, weight: .semibold))

                                    Text(scheduledPillTimeText)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.white.opacity(0.80))
                                        .lineLimit(1)

                                    Text("\(languageStore.settingsText(.homeFromLabel)): \(scheduledPillFromText)")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.white.opacity(0.70))
                                        .lineLimit(1)

                                    Text("\(languageStore.settingsText(.homeToLabel)): \(scheduledPillToText)")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.white.opacity(0.70))
                                        .lineLimit(1)
                                }

                                Spacer(minLength: 0)

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.55))
                            }
                            .foregroundColor(.white)
                            .padding(14)
                            .frame(maxWidth: .infinity)
                            .background(Color.white.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 20)
                    }

                    // MARK: — SEARCH BAR
                    Button { showDestinationSearch = true } label: {
                        HStack(spacing: 13) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.black)

                            Text(languageStore.settingsText(.homeSearchPrompt))
                                .foregroundColor(.black.opacity(0.64))
                                .font(.system(size: 16, weight: .medium))

                            Spacer()

                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.black.opacity(0.38))
                        }
                        .padding(.horizontal, 17)
                        .frame(height: 56)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.black.opacity(0.06), lineWidth: 1)
                        }
                        .padding(.horizontal, 20)
                    }
                    .buttonStyle(.plain)

                    // MARK: — NOW / SCHEDULE SWITCH
                    HStack(spacing: 4) {
                        Button {
                            isNow = true
                        } label: {
                            Text(languageStore.settingsText(.homeNow))
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(isNow ? .black : .white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 38)
                                .background(isNow ? Color.white : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            ScheduleRideView()
                        } label: {
                            Text(languageStore.settingsText(.homeSchedule))
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(!isNow ? .black : .white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 38)
                                .background(!isNow ? Color.white : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .simultaneousGesture(TapGesture().onEnded {
                            isNow = false
                        })
                    }
                    .padding(4)
                    .background(Color.white.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    }
                    .padding(.horizontal, 20)

                    // MARK: — PLAN YOUR RIDE CARD
                    VStack(alignment: .leading, spacing: 0) {

                        Text(languageStore.settingsText(.homePlanRide))
                            .font(.system(size: 19, weight: .bold))
                            .foregroundColor(.black)
                            .padding(.bottom, 14)

                        // PICKUP
                        NavigationLink {
                            DestinationSearchView(locationManager: locationManager)
                        } label: {
                            HStack(spacing: 13) {
                                ZStack {
                                    Circle().fill(Color.black.opacity(0.07))
                                    Circle()
                                        .fill(Color.black)
                                        .frame(width: 8, height: 8)
                                }
                                .frame(width: 34, height: 34)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(languageStore.settingsText(.homePickup))
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.black.opacity(0.48))

                                    Text(languageStore.settingsText(.homeWhereFrom))
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.black)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.black.opacity(0.28))
                            }
                            .frame(minHeight: 54)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Divider()
                            .overlay(Color.black.opacity(0.06))
                            .padding(.leading, 47)
                            .padding(.vertical, 4)

                        // DROPOFF
                        NavigationLink {
                            DestinationSearchView(locationManager: locationManager)
                        } label: {
                            HStack(spacing: 13) {
                                Image(systemName: "mappin.and.ellipse")
                                    .foregroundColor(.black)
                                    .font(.system(size: 15, weight: .semibold))
                                    .frame(width: 34, height: 34)
                                    .background(Color.black.opacity(0.07), in: Circle())

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(languageStore.settingsText(.homeDropoff))
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.black.opacity(0.48))

                                    Text(languageStore.settingsText(.homeWhereTo))
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.black)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.black.opacity(0.28))
                            }
                            .frame(minHeight: 54)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                    }
                    .padding(20)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color.black.opacity(0.06), lineWidth: 1)
                    }
                    .padding(.horizontal, 20)

                    }
                    .background {
                        GeometryReader { contentSpace in
                            Color.clear.preference(
                                key: HomeContentHeightPreferenceKey.self,
                                value: contentSpace.size.height
                            )
                        }
                    }

                    // MARK: — MAP SECTION
                    let remainingMapHeight = max(
                        availableSpace.size.height
                            - (homeContentHeight ?? availableSpace.size.height)
                            - homeSectionSpacing,
                        0
                    )

                    ZStack(alignment: .topTrailing) {
                        GoogleMapView(centerCoordinate: mapCenter, rideId: activeRideId.isEmpty ? nil : activeRideId)
                            .id(mapRefreshID)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                            }

                        VStack(spacing: 10) {

                            Button { recenter() } label: {
                                Image(systemName: "location.fill")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.black)
                                    .frame(width: 42, height: 42)
                                    .background(Color.white)
                                    .clipShape(Circle())
                                    .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
                            }

                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    isMapFullScreen = true
                                }
                            } label: {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.black)
                                    .frame(width: 42, height: 42)
                                    .background(Color.white)
                                    .clipShape(Circle())
                                    .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
                            }
                        }
                        .padding(14)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: remainingMapHeight)
                    .padding(.horizontal, 20)
            }
            .onPreferenceChange(HomeContentHeightPreferenceKey.self) { height in
                homeContentHeight = height
            }

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

                            Text(languageStore.settingsText(.accountMenuTitle))
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.bottom, 4)

                            // ✅ UPDATED: pass binding into ProfileView
                            NavigationLink {
                                ProfileView(logoutTriggered: $logoutTriggered)
                            } label: {
                                Text(languageStore.settingsText(.accountMenuProfile))
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
                                Text(languageStore.settingsText(.accountMenuLanguage))
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
                                Text(languageStore.settingsText(.accountMenuPrivacy))
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
                                Text(languageStore.settingsText(.accountMenuRideHistory))
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
                                Text(languageStore.settingsText(.accountMenuDelivery))
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
                                Text(languageStore.settingsText(.accountMenuNotifications))
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
                                Text(languageStore.settingsText(.accountMenuSupport))
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
                                Text(languageStore.settingsText(.accountMenuLegal))
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
                                    rideService.clearActiveRideForLogout()
                                    activeRideId = ""
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
                                Text(languageStore.settingsText(.accountMenuLogout))
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
        }
        .sheet(isPresented: $showDestinationSearch) {
            DestinationSearchView(locationManager: locationManager)
        }
        .overlay(fullScreenMapOverlay)
        .onAppear {
            reconcileScheduledRideState()
        }
        .task { await restoreActiveRideIfNeeded() }
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
            let normalizedStatus = status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if SupabaseRideService.terminalStatuses.contains(normalizedStatus) {
                showRestoredActiveRide = false
                restoredActiveRide = nil
                restoredAccessToken = nil
                activeRideId = ""
                rideService.stopObservingRideStatus()
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
        .onReceive(rideService.$activeRideID) { rideID in
            guard rideID == nil else { return }
            showRestoredActiveRide = false
            restoredActiveRide = nil
            restoredAccessToken = nil
            activeRideId = ""
        }
        .onReceive(NotificationCenter.default.publisher(for: .RideDidCancel)) { _ in
            clearActiveRideNavigation()
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
        .navigationDestination(isPresented: $showRestoredActiveRide) {
            if let ride = restoredActiveRide, let rideUUID = UUID(uuidString: ride.id) {
                if ride.normalizedStatus == "searching" || ride.normalizedStatus == "requested" {
                    SearchingForDriverView(
                        rideId: rideUUID,
                        pickupAddress: ride.pickupAddress ?? "",
                        dropoffAddress: ride.dropoffAddress ?? "",
                        rideTypeLabel: ride.displayRideType,
                        priceText: restoredFareText(ride),
                        supabase: LumoSupabaseConfig(
                            baseURL: URL(string: JiyloTestEnvironment.supabaseURLString)!,
                            anonKey: JiyloTestEnvironment.supabaseAnonKey,
                            accessToken: restoredAccessToken
                        ),
                        onRideEnded: clearActiveRideNavigation
                    )
                } else {
                    DriverTrackingView(
                        rideId: ride.id,
                        driver: restoredDriverProfile(ride),
                        onRideEnded: clearActiveRideNavigation
                    )
                }
            } else {
                Color.clear.onAppear { showRestoredActiveRide = false }
            }
        }
    }

    @MainActor
    private func clearActiveRideNavigation() {
        showDestinationSearch = false
        showRestoredActiveRide = false
        restoredActiveRide = nil
        restoredAccessToken = nil
        activeRideId = ""
        rideService.stopObservingRideStatus()
    }

    @MainActor
    private func restoreActiveRideIfNeeded() async {
        guard !showRestoredActiveRide else { return }
        let sessionToken = rideService.activeRideSessionToken()
        do {
            let restored = try await rideService.fetchNewestActiveRide()
            guard rideService.isActiveRideSessionCurrent(sessionToken) else { return }
            guard let ride = restored.ride, UUID(uuidString: ride.id) != nil else {
                restoredActiveRide = nil
                restoredAccessToken = nil
                activeRideId = ""
                rideService.stopObservingRideStatus()
                return
            }
            restoredActiveRide = ride
            restoredAccessToken = restored.accessToken
            activeRideId = ride.id
            rideService.beginObservingRideStatus(rideId: ride.id)
            showRestoredActiveRide = true
        } catch {
            guard rideService.isActiveRideSessionCurrent(sessionToken) else { return }
            if error is ActiveRideRecoveryError {
                // An ambiguous backend result is not safe to resume.  Clear every
                // local restore handle rather than letting an old ID reappear.
                clearActiveRideNavigation()
                return
            }
            // A network/authentication failure is not evidence that the trip ended.
            // Keep the persisted ride identifier for the next recovery attempt.
            print("[RideRecovery] Active ride lookup failed; retaining trip context.")
        }
    }

    private func restoredFareText(_ ride: ActiveRideRecord) -> String? {
        guard let fare = ride.fare else { return nil }
        let value = fare.formatted(.number.precision(.fractionLength(0...2)))
        return "\(value) \((ride.currency ?? "").uppercased())".trimmingCharacters(in: .whitespaces)
    }

    private func restoredDriverProfile(_ ride: ActiveRideRecord) -> DriverTrackingView.DriverProfile {
        DriverTrackingView.DriverProfile(
            name: ride.driverName ?? "Your driver",
            rating: ride.driverRating ?? 4.92,
            vehicleMakeModel: ride.driverVehicle ?? "Sedan",
            serviceLevel: ride.driverServiceLevel ?? ride.displayRideType ?? "Comfort",
            plate: ride.driverPlate ?? "—",
            colorName: ride.driverColor ?? "Black",
            phoneE164: ride.driverPhone,
            photoURL: ride.driverPhotoURL
        )
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

        let hasDatabaseScheduledRideID =
            UUID(uuidString: scheduledRideId) != nil &&
            UserDefaults.standard.bool(forKey: "lumo_scheduled_ride_id_is_database")

        if hasAnyScheduledData && hasDatabaseScheduledRideID {
            hasScheduledRide = true
        } else {
            hasScheduledRide = false
            scheduledRideId = ""
            UserDefaults.standard.removeObject(forKey: "lumo_scheduled_ride_id_is_database")
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
        .environmentObject(LumoLanguageStore())
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

    // MARK: - User profile data
    @State private var fullName: String = "Your name"
    @State private var email: String = ""
    @State private var phoneNumber: String = ""

    @State private var preferredRideType: String = "JiyloX"
    @State private var countryRegion: String = "United States"
    @State private var memberSince: String = ""

    // Save state
    @State private var isSaving: Bool = false
    @State private var showSaveAlert: Bool = false

    // Profile photo state
    @State private var selectedPhotoItem: PhotosPickerItem?
    @AppStorage("lumo_profileImageData") private var profileImageData: Data = Data()

    // Persisted profile info
    private let profileInfoDefaultsKey = "lumo_profileInfo"

    // Simple ride type options
    private let rideTypes = ["Saver", "JiyloX", "JiyloXL"]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {

                    // MARK: - Header with avatar
                    VStack(spacing: 14) {
                        ZStack {
                            if let uiImage = UIImage(data: profileImageData) {
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

                        // Phone (managed by Firebase Phone Auth)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Phone")
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.6))

                            Text(phoneNumber.isEmpty ? "Not set" : phoneNumber)
                                .font(.system(size: 16))
                                .foregroundColor(.white)
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
                phoneNumber = currentUser.phoneNumber ?? ""
            } else {
                email = ""
                phoneNumber = ""
            }

            let defaults = UserDefaults.standard
            // restore saved profile info
            if let savedInfo = defaults.dictionary(forKey: profileInfoDefaultsKey) as? [String: String] {
                fullName = savedInfo["fullName"] ?? fullName
                email = savedInfo["email"] ?? email
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
            SupabaseRideService.shared.clearActiveRideForLogout()
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
                    Text(languageStore.settingsText(.languageTitle))
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)

                    Text(languageStore.settingsText(.languageSubtitle))
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
                                    Text(languageStore.settingsText(LumoSettingsL10n.languageTitleKey(for: language)))
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.white)

                                    Text(languageStore.settingsText(LumoSettingsL10n.languageSubtitleKey(for: language)))
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
        .navigationTitle(languageStore.settingsText(.languageTitle))
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
                Text("Jiylo balance")
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

                        Text("Funds will be added to your Jiylo balance.")
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

        // Profile preferences can supplement Firebase account data, but they
        // must not replace the authenticated phone number.
        if let saved = UserDefaults.standard.dictionary(forKey: "lumo_profileInfo") as? [String: String] {
            if let n = saved["fullName"], !n.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                userFullName = n
            }
            if let e = saved["email"], !e.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                userEmail = e
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
    @EnvironmentObject private var languageStore: LumoLanguageStore
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
                        Text(languageStore.settingsText(.privacyLocationTracking))
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)

                        Toggle(isOn: $locationAccess) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(languageStore.settingsText(.privacyAllowLocationTitle))
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.white)
                                Text(languageStore.settingsText(.privacyAllowLocationSubtitle))
                                    .font(.system(size: 12))
                                    .foregroundColor(.white.opacity(0.6))
                            }
                        }
                        .toggleStyle(SwitchToggleStyle(tint: .white))

                        Divider().background(Color.white.opacity(0.15))

                        Toggle(isOn: $crashReports) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(languageStore.settingsText(.privacyDiagnosticsTitle))
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.white)
                                Text(languageStore.settingsText(.privacyDiagnosticsSubtitle))
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
                        Text(languageStore.settingsText(.privacyPersonalization))
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)

                        Toggle(isOn: $personalization) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(languageStore.settingsText(.privacyPersonalizedSuggestionsTitle))
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.white)
                                Text(languageStore.settingsText(.privacyPersonalizedSuggestionsSubtitle))
                                    .font(.system(size: 12))
                                    .foregroundColor(.white.opacity(0.6))
                            }
                        }
                        .toggleStyle(SwitchToggleStyle(tint: .white))

                        Divider().background(Color.white.opacity(0.15))

                        Toggle(isOn: $dataSharing) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(languageStore.settingsText(.privacySharePartnersTitle))
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.white)
                                Text(languageStore.settingsText(.privacySharePartnersSubtitle))
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
                        Text(languageStore.settingsText(.privacyYourData))
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)

                        Button {
                            print("Download data tapped")
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(languageStore.settingsText(.privacyDownloadDataTitle))
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(.white)
                                    Text(languageStore.settingsText(.privacyDownloadDataSubtitle))
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
                                Text(languageStore.settingsText(.privacyViewPolicyTitle))
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
        .navigationTitle(languageStore.settingsText(.privacyTitle))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Ride History (polished)

struct RideHistoryView: View {
    @State private var history: [RideHistoryRecord] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if isLoading {
                ProgressView("Loading ride history…")
                    .tint(.white)
                    .foregroundColor(.white)
            } else if let errorMessage {
                VStack(spacing: 12) {
                    Text(errorMessage)
                        .font(.system(size: 15))
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                    Button("Try again") {
                        Task { await loadHistory() }
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                }
                .padding(.horizontal, 32)
            } else if history.isEmpty {
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
                            NavigationLink {
                                RideHistoryDetailsView(ride: ride)
                            } label: {
                                VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text(ride.displayRideType)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.white)
                                    Spacer()
                                    Text(historyFare(ride))
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.white)
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(historyDate(ride))
                                        .font(.system(size: 12))
                                        .foregroundColor(.white.opacity(0.6))

                                    Text("From: \(ride.pickupAddress ?? "—")")
                                        .font(.system(size: 13))
                                        .foregroundColor(.white.opacity(0.85))

                                    Text("To: \(ride.dropoffAddress ?? "—")")
                                        .font(.system(size: 13))
                                        .foregroundColor(.white.opacity(0.85))

                                    Text(historyStatus(ride.status))
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(ride.status == "completed" ? .green : .orange)
                                }
                            }
                            .padding(14)
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                            }
                            .buttonStyle(.plain)
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
        .onAppear {
            Task { await loadHistory() }
        }
    }

    @MainActor
    private func loadHistory() async {
        isLoading = true
        errorMessage = nil
        do {
            history = try await SupabaseRideService.shared.fetchRideHistory()
        } catch {
            history = []
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

private struct RideHistoryDetailsView: View {
    let ride: RideHistoryRecord

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    historyDetailRow("Status", historyStatus(ride.status))
                    historyDetailRow("Ride type", ride.displayRideType)
                    historyDetailRow("Date and time", historyDate(ride))
                    historyDetailRow("Pickup", ride.pickupAddress ?? "—")
                    historyDetailRow("Destination", ride.dropoffAddress ?? "—")
                    historyDetailRow("Fare", historyFare(ride))
                }
                .padding(20)
            }
        }
        .navigationTitle("Ride details")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func historyDetailRow(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 12)).foregroundColor(.white.opacity(0.55))
            Text(value).font(.system(size: 16, weight: .medium)).foregroundColor(.white)
        }
    }
}

private func historyDate(_ ride: RideHistoryRecord) -> String {
    guard let value = ride.finalDateString else { return "—" }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let date = formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    guard let date else { return value }
    return date.formatted(date: .abbreviated, time: .shortened)
}

private func historyFare(_ ride: RideHistoryRecord) -> String {
    guard let fare = ride.fare else { return "—" }
    return "\(fare.formatted(.number.precision(.fractionLength(0...2)))) \((ride.currency ?? "").uppercased())"
        .trimmingCharacters(in: .whitespaces)
}

private func historyStatus(_ status: String) -> String {
    status.replacingOccurrences(of: "_", with: " ").capitalized
}

// MARK: - Notifications (polished)

struct NotificationsView: View {
    @EnvironmentObject private var languageStore: LumoLanguageStore
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
                        Text(languageStore.settingsText(.notificationsTripSection))
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)

                        Toggle(isOn: $tripUpdates) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(languageStore.settingsText(.notificationsTripStatusTitle))
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.white)
                                Text(languageStore.settingsText(.notificationsTripStatusSubtitle))
                                    .font(.system(size: 12))
                                    .foregroundColor(.white.opacity(0.6))
                            }
                        }
                        .toggleStyle(SwitchToggleStyle(tint: .white))

                        Divider().background(Color.white.opacity(0.15))

                        Toggle(isOn: $driverArriving) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(languageStore.settingsText(.notificationsDriverArrivalTitle))
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.white)
                                Text(languageStore.settingsText(.notificationsDriverArrivalSubtitle))
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
                        Text(languageStore.settingsText(.notificationsPromotionsSection))
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)

                        Toggle(isOn: $promotions) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(languageStore.settingsText(.notificationsPromotionsTitle))
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.white)
                                Text(languageStore.settingsText(.notificationsPromotionsSubtitle))
                                    .font(.system(size: 12))
                                    .foregroundColor(.white.opacity(0.6))
                            }
                        }
                        .toggleStyle(SwitchToggleStyle(tint: .white))

                        Divider().background(Color.white.opacity(0.15))

                        Toggle(isOn: $productUpdates) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(languageStore.settingsText(.notificationsProductUpdatesTitle))
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.white)
                                Text(languageStore.settingsText(.notificationsProductUpdatesSubtitle))
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
                        Text(languageStore.settingsText(.notificationsChannelsSection))
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)

                        Toggle(isOn: $sms) {
                            Text(languageStore.settingsText(.notificationsSMSTitle))
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.white)
                        }
                        .toggleStyle(SwitchToggleStyle(tint: .white))

                        Toggle(isOn: $email) {
                            Text(languageStore.settingsText(.notificationsEmailTitle))
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
        .navigationTitle(languageStore.settingsText(.notificationsTitle))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Support (polished)

struct SupportView: View {
    @EnvironmentObject private var languageStore: LumoLanguageStore

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {

                    // MARK: - Quick actions
                    VStack(alignment: .leading, spacing: 12) {
                        Text(languageStore.settingsText(.supportNeedHelpTitle))
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)

                        Button {
                            print("Help with recent trip tapped")
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(languageStore.settingsText(.supportRecentTripTitle))
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(.white)
                                    Text(languageStore.settingsText(.supportRecentTripSubtitle))
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
                        Text(languageStore.settingsText(.supportHelpTopicsTitle))
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)

                        SupportRow(titleKey: .supportPaymentChargesTitle, subtitleKey: .supportPaymentChargesSubtitle)
                        SupportRow(titleKey: .supportAccountLoginTitle, subtitleKey: .supportAccountLoginSubtitle)
                        SupportRow(titleKey: .supportSafetySecurityTitle, subtitleKey: .supportSafetySecuritySubtitle)
                        SupportRow(titleKey: .supportUsingLumoTitle, subtitleKey: .supportUsingLumoSubtitle)
                    }
                    .padding(18)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .padding(.horizontal, 20)

                    // MARK: - Contact support
                    VStack(alignment: .leading, spacing: 12) {
                        Text(languageStore.settingsText(.supportContactTitle))
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
                                    Text(languageStore.settingsText(.supportMessageTitle))
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(.white)
                                    Text(languageStore.settingsText(.supportMessageSubtitle))
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
        .navigationTitle(languageStore.settingsText(.supportTitle))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SupportRow: View {
    @EnvironmentObject private var languageStore: LumoLanguageStore

    let titleKey: LumoSettingsL10n.Key
    let subtitleKey: LumoSettingsL10n.Key

    var body: some View {
        Button {
            print("\(titleKey.rawValue) tapped")
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(languageStore.settingsText(titleKey))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white)
                    Text(languageStore.settingsText(subtitleKey))
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

    var id: LumoSettingsL10n.Key { titleKey }

    var titleKey: LumoSettingsL10n.Key {
        switch self {
        case .termsOfService:
            return .legalTermsTitle
        case .privacyPolicy:
            return .legalPrivacyTitle
        case .communityGuidelines:
            return .legalGuidelinesTitle
        case .licenses:
            return .legalLicensesTitle
        }
    }

    var subtitleKey: LumoSettingsL10n.Key {
        switch self {
        case .termsOfService:
            return .legalTermsSubtitle
        case .privacyPolicy:
            return .legalPrivacySubtitle
        case .communityGuidelines:
            return .legalGuidelinesSubtitle
        case .licenses:
            return .legalLicensesSubtitle
        }
    }

    var body: String {
        switch self {
        case .termsOfService:
            return """
            Welcome to Jiylo. By using Jiylo, you agree to use the app responsibly and follow these terms.

            Jiylo connects riders with independent drivers for transportation requests. Ride availability, pickup times, prices, and driver availability may vary.

            You are responsible for providing accurate pickup and dropoff information. You agree not to misuse the app, create false ride requests, harass drivers or riders, or use Jiylo for illegal activity.

            Drivers using Jiylo are responsible for following local laws, maintaining valid licenses, insurance, and vehicle requirements, and providing safe transportation.

            Payments made through Jiylo must be valid and authorized. If a payment fails, the ride may not be confirmed.

            Jiylo may suspend or remove accounts that violate these terms, create safety concerns, commit fraud, or misuse the platform.

            Jiylo may update these terms from time to time. Continued use of the app means you accept the updated terms.

            If you do not agree with these terms, please stop using Jiylo.
            """
        case .privacyPolicy:
            return """
            Jiylo respects your privacy. This policy explains how we handle information used to provide rides and app features.

            We may collect information such as your name, phone number, email address, profile photo, pickup and dropoff locations, ride history, payment status, device information, app activity, messages, and support information.

            We use this information to create and manage accounts, connect riders and drivers, process rides, improve safety, provide support, send notifications, prevent fraud, and improve Jiylo.

            Location information may be used while the app is active and, when needed, during active rides to show pickup, dropoff, driver movement, routing, and trip progress.

            Payment details are processed through Stripe. Jiylo does not store full card numbers in the app.

            Messages, call-related records, and ride information may be used to support safety, customer support, and dispute review.

            We do not sell your personal information. We may share information with service providers such as payment processors, cloud hosting, maps, notifications, and safety/support tools only as needed to operate Jiylo.

            You may request help with your account, data, or privacy questions by contacting Jiylo support.
            """
        case .communityGuidelines:
            return """
            Jiylo is built for safe, respectful transportation. Riders and drivers must treat each other with respect.

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
            Jiylo uses third-party services and open-source components to provide app features.

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
    @EnvironmentObject private var languageStore: LumoLanguageStore

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 24) {

                VStack(alignment: .leading, spacing: 8) {
                    Text(languageStore.settingsText(.legalDocumentsTitle))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)

                    Text(languageStore.settingsText(.legalDocumentsSubtitle))
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
                            LegalRow(
                                title: languageStore.settingsText(document.titleKey),
                                subtitle: languageStore.settingsText(document.subtitleKey)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)

                Spacer()
            }
        }
        .navigationTitle(languageStore.settingsText(.legalTitle))
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
    @EnvironmentObject private var languageStore: LumoLanguageStore

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
                        Text(languageStore.settingsText(.legalBackTitle))
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

                Text(languageStore.settingsText(document.titleKey))
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

// MARK: - Delivery is implemented in FoodDeliveryModels.swift, FoodDeliveryService.swift, and DeliveryRequestView.swift.

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
