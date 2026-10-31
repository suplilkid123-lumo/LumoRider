import SwiftUI
import Foundation
import UIKit
import FirebaseAuth
import Stripe
import PassKit
import CoreLocation

// BEGIN RideCreationContract (Foundation-only; exercised by the regression runner)
enum RideCreationContract {
    static func rpcError(status: Int, payload: [String: Any]?, operation: String) -> NSError {
        let code = payload?["code"] as? String
        let serverMessage = payload?["message"] as? String
        let message: String
        if code == "PGRST202" {
            message = "Ride booking is temporarily unavailable because the server is missing a required booking service. Please contact Jiylo support."
        } else if status == 401 && serverMessage?.lowercased() == "invalid api key" {
            message = "Jiylo could not connect to the booking service because its server configuration was rejected. Please contact Jiylo support."
        } else {
            message = serverMessage ?? "Could not create the ride securely."
        }
        return NSError(domain: "AddPaymentView", code: status, userInfo: [
            NSLocalizedDescriptionKey: message,
            "operation": operation,
            "backendCode": code ?? ""
        ])
    }

    static func validate(_ response: [String: Any], scheduled: Bool) throws {
        guard let id = response["id"] as? String, UUID(uuidString: id) != nil,
              let status = response["status"] as? String,
              status == (scheduled ? "scheduled" : "requested") else {
            // An idempotent retry may return an already accepted or terminal ride.
            // Do not present it as a newly searching request or create another ride.
            throw NSError(domain: "AddPaymentView", code: 409, userInfo: [
                NSLocalizedDescriptionKey: "The server did not confirm a new ride request. Return to Home to check your current trip before trying again."
            ])
        }
    }
}
// END RideCreationContract

// Helper to read saved card info (brand + last4) from UserDefaults
private func loadSavedCardInfo() -> (brand: String, last4: String)? {
    let defaults = UserDefaults.standard
    guard
        let data = defaults.data(forKey: "savedCardInfo"),
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
        let brand = json["brand"],
        let last4 = json["last4"]
    else {
        return nil
    }
    return (brand, last4)
}

// MARK: - Minimal Supabase ride row decode
private struct SupabaseRideRow: Decodable {
    let id: String?
    let status: String?
}

struct AddPaymentView: View {
    @EnvironmentObject private var languageStore: LumoLanguageStore
    @State private var createdRideId: UUID? = nil

    // 🔹 Scheduled ride time (seconds since 1970). Prefer the passed value, but we can silently fall back to UserDefaults.
    @State private var scheduledForEpoch: Double

    // 🔹 What we actually created this time (used for navigation)
    @State private var createdWasScheduled: Bool = false
    @State private var createdScheduledForEpoch: Double = 0
    @Environment(\.dismiss) private var dismiss

    // MARK: - Ride details (pass these in from your ride request flow)
    // Defaults are kept for legacy call sites, but payment-created rides use the values passed by the trip flow.
    let pickupAddress: String
    let dropoffAddress: String
    let pickupLat: Double
    let pickupLng: Double
    let dropoffLat: Double
    let dropoffLng: Double
    let rideTypeLabel: String?
    let estimatedFareText: String?
    let fareIQD: Int?
    let fareUSD: Double?
    let currency: String?

    // MARK: - Payment UI
    @State private var showCardSheet: Bool = false
    @State private var savedCard = loadSavedCardInfo()
    @State private var selectedPayment: PaymentChoice = .none

    // MARK: - Confirm ride flow
    @State private var isConfirming: Bool = false
    @State private var rideInsertStarted: Bool = false
    @State private var authoritativeQuoteRequestID = UUID()
    @State private var authoritativeRideRequestID = UUID()
    @State private var authoritativeCashFareText: String? = nil
    @State private var approvedQuoteID: String? = nil
    @State private var confirmRideError: String? = nil
    @State private var showRideConfirmed: Bool = false

    // MARK: - Apple Pay (Stripe)
    @State private var applePayCoordinator: ApplePayCoordinator? = nil
    @State private var applePayContext: STPApplePayContext? = nil

    // MARK: - Supabase config
    private var supabaseProjectURL: String { JiyloTestEnvironment.supabaseURLString }
    private var supabaseAnonKey: String { JiyloTestEnvironment.supabaseAnonKey }
    private let ridesTableName = "rides"

    private func logRideDispatchTrace(_ message: @autoclosure () -> String) {
        #if DEBUG
        print("[RideDispatchTrace] \(message())")
        #endif
    }

    /// Test payment is available only to a DEBUG build connected directly to a
    /// local development backend. A physical DEBUG build that still points
    /// at the hosted backend must never simulate a payment.
    private var simulatedPaymentEnabled: Bool {
        JiyloTestEnvironment.isAuthorizedTestRider
    }

    enum PaymentChoice {
        case none
        case applePay
        case cash
        case savedCard
        case newCard
        case test
    }

    // MARK: - Init with defaults
    init(
        pickupAddress: String = "",
        dropoffAddress: String = "",
        pickupLat: Double = 0,
        pickupLng: Double = 0,
        dropoffLat: Double = 0,
        dropoffLng: Double = 0,
        rideTypeLabel: String? = nil,
        estimatedFareText: String? = nil,
        fareIQD: Int? = nil,
        fareUSD: Double? = nil,
        currency: String? = nil,
        scheduledForEpoch: Double = 0
    ) {
        self.pickupAddress = pickupAddress
        self.dropoffAddress = dropoffAddress
        self.pickupLat = pickupLat
        self.pickupLng = pickupLng
        self.dropoffLat = dropoffLat
        self.dropoffLng = dropoffLng
        self.rideTypeLabel = rideTypeLabel
        self.estimatedFareText = estimatedFareText
        self.fareIQD = fareIQD
        self.fareUSD = fareUSD
        self.currency = currency
        _scheduledForEpoch = State(initialValue: scheduledForEpoch)
    }

    private var scheduledDate: Date? {
        guard scheduledForEpoch > 0 else { return nil }
        return Date(timeIntervalSince1970: scheduledForEpoch)
    }

    private var isScheduledFlow: Bool {
        guard let d = scheduledDate else { return false }
        return d.timeIntervalSince(Date()) > 0
    }

    private var confirmButtonTitle: String {
        languageStore.settingsText(isScheduledFlow ? .addPaymentScheduleRide : .addPaymentConfirmRide)
    }

    private func iso8601(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 24) {

                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Circle())
                    }

                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)

                Text(languageStore.settingsText(.addPaymentTitle))
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)

                VStack(spacing: 16) {

                    paymentOptionRow(
                        icon: "applelogo",
                        title: languageStore.settingsText(.addPaymentApplePayTitle),
                        subtitle: languageStore.settingsText(.addPaymentApplePaySubtitle),
                        isSelected: selectedPayment == .applePay,
                        action: {
                            selectedPayment = .applePay
                            confirmRideError = nil
                        }
                    )

                    paymentOptionRow(
                        icon: "banknote",
                        title: languageStore.settingsText(.addPaymentCashTitle),
                        subtitle: languageStore.settingsText(.addPaymentCashSubtitle),
                        isSelected: selectedPayment == .cash,
                        action: {
                            startCashRideFlow()
                        }
                    )

                    if let savedCard {
                        paymentOptionRow(
                            icon: "creditcard",
                            title: "\(savedCard.brand) •••• \(savedCard.last4)",
                            subtitle: languageStore.settingsText(.addPaymentSavedCardSubtitle),
                            isSelected: selectedPayment == .savedCard,
                            action: {
                                selectedPayment = .savedCard
                                confirmRideError = nil
                                showCardSheet = true
                            }
                        )

                        paymentOptionRow(
                            icon: "plus.circle",
                            title: languageStore.settingsText(.addPaymentDifferentCardTitle),
                            subtitle: languageStore.settingsText(.addPaymentDifferentCardSubtitle),
                            isSelected: selectedPayment == .newCard,
                            action: {
                                selectedPayment = .newCard
                                confirmRideError = nil
                                showCardSheet = true
                            }
                        )

                        if simulatedPaymentEnabled {
                            paymentOptionRow(
                                icon: "wrench.and.screwdriver",
                                title: languageStore.settingsText(.addPaymentTestPaymentTitle),
                                subtitle: languageStore.settingsText(.addPaymentTestPaymentSubtitle),
                                isSelected: selectedPayment == .test,
                                action: {
                                    selectedPayment = .test
                                    confirmRideError = nil
                                }
                            )
                        }
                    } else {
                        paymentOptionRow(
                            icon: "plus.circle",
                            title: languageStore.settingsText(.addPaymentDifferentCardTitle),
                            subtitle: languageStore.settingsText(.addPaymentDifferentCardSubtitle),
                            isSelected: selectedPayment == .newCard,
                            action: {
                                selectedPayment = .newCard
                                confirmRideError = nil
                                showCardSheet = true
                            }
                        )

                        if simulatedPaymentEnabled {
                            paymentOptionRow(
                                icon: "wrench.and.screwdriver",
                                title: languageStore.settingsText(.addPaymentTestPaymentTitle),
                                subtitle: languageStore.settingsText(.addPaymentTestPaymentSubtitle),
                                isSelected: selectedPayment == .test,
                                action: {
                                    selectedPayment = .test
                                    confirmRideError = nil
                                }
                            )
                        }
                    }
                }
                .padding(.horizontal, 24)

                Spacer()

                VStack(spacing: 10) {
                    Button {
                        Task { await handleConfirmTapped() }
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 999)
                                .fill(canConfirm ? Color.white : Color.white.opacity(0.30))

                            if isConfirming {
                                ProgressView()
                                    .tint(.black)
                            } else {
                                Text(confirmButtonTitle)
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.black)
                            }
                        }
                        .frame(height: 56)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canConfirm || isConfirming || rideInsertStarted)
                    .padding(.horizontal, 24)

                    if let confirmRideError {
                        Text(confirmRideError)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                            .padding(.bottom, 10)
                    } else {
                        Spacer().frame(height: 18)
                    }
                }
                .padding(.bottom, 14)
            }
        }
        .sheet(isPresented: $showCardSheet, onDismiss: {
            savedCard = loadSavedCardInfo()
            if selectedPayment == .newCard || selectedPayment == .savedCard {
                selectedPayment = .none
            }
        }) {
            CardPaymentView(
                pickupAddress: pickupAddress,
                dropoffAddress: dropoffAddress,
                pickupCoordinate: CLLocationCoordinate2D(latitude: pickupLat, longitude: pickupLng),
                dropoffCoordinate: CLLocationCoordinate2D(latitude: dropoffLat, longitude: dropoffLng),
                rideTypeLabel: rideTypeLabel,
                estimatedFareText: estimatedFareText,
                fareIQD: fareIQD,
                fareUSD: fareUSD,
                currency: currency,
                scheduledForEpoch: scheduledForEpoch
            )
            .presentationDetents([.fraction(0.55), .large])
            .presentationDragIndicator(.visible)
        }
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $showRideConfirmed, onDismiss: {
            // A completed or cancelled live ride should not return to a disabled payment form.
            if createdRideId != nil && !createdWasScheduled { dismiss() }
        }) {
            if createdWasScheduled {
                RideScheduledView(
                    pickupAddress: pickupAddress,
                    dropoffAddress: dropoffAddress,
                    scheduledForEpoch: createdScheduledForEpoch,
                    onDone: {
                        showRideConfirmed = false
                        dismiss()
                    }
                )
            } else {
                if let rideId = createdRideId {
                    NavigationStack {
                        SearchingForDriverView(
                            rideId: rideId,
                            pickupAddress: pickupAddress,
                            dropoffAddress: dropoffAddress,
                            rideTypeLabel: rideTypeLabel,
                            priceText: priceTextForSearching,
                            isTestRide: selectedPayment == .test && simulatedPaymentEnabled,
                            supabase: LumoSupabaseConfig(
                                baseURL: URL(string: supabaseProjectURL)!,
                                anonKey: supabaseAnonKey,
                                accessToken: nil
                            )
                        )
                    }
                    .onAppear {
                        print("[Ride navigation] Passing Supabase ride ID to SearchingForDriverView: \(rideId.uuidString)")
                    }
                }
            }
        }
        .onAppear {
            StripeAPI.defaultPublishableKey = StripeConfig.publishableKey

            if scheduledForEpoch <= 0 {
                let defaults = UserDefaults.standard
                var saved = defaults.double(forKey: "lumo_scheduled_for_epoch")
                if saved <= 0 { saved = defaults.double(forKey: "lumo_scheduled_for_epoch_to_pass") }
                if saved <= 0 { saved = defaults.double(forKey: "scheduledForEpochToPass") }
                if saved <= 0 { saved = defaults.double(forKey: "scheduled_for_epoch") }

                if saved > 0 { scheduledForEpoch = saved }
            }
        }
    }

    private var canConfirm: Bool {
        switch selectedPayment {
        case .none:
            return false
        case .applePay:
            return true
        case .cash:
            return true
        case .savedCard:
            return savedCard != nil
        case .newCard:
            return true
        case .test:
            return simulatedPaymentEnabled
        }
    }

    func paymentOptionRow(
        icon: String,
        title: String,
        subtitle: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {

                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 42, height: 42)
                    .background(Color.white.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .foregroundColor(.white)
                        .font(.system(size: 16, weight: .semibold))

                    Text(subtitle)
                        .foregroundColor(.white.opacity(0.6))
                        .font(.system(size: 13))
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.white)
                        .font(.system(size: 18, weight: .semibold))
                } else {
                    Image(systemName: "chevron.right")
                        .foregroundColor(.white.opacity(0.6))
                        .font(.system(size: 14, weight: .semibold))
                }
            }
            .padding()
            .background(Color.white.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(isSelected ? Color.white.opacity(0.35) : Color.clear, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
    }

    @MainActor
    private func handleConfirmTapped() async {
        guard !isConfirming, !rideInsertStarted, createdRideId == nil else { return }
        confirmRideError = nil

        switch selectedPayment {
        case .applePay:
            // Ride creation currently rejects electronic payment. Do not authorize
            // a legacy intent before that rejection: it can leave a charge with no ride.
            confirmRideError = "Apple Pay ride checkout is unavailable until secure ride-linked payment is configured. No payment was requested."

        case .savedCard, .newCard:
            showCardSheet = true

        case .cash:
            await confirmRide()

        case .test:
            guard simulatedPaymentEnabled else {
                confirmRideError = languageStore.settingsText(.addPaymentChooseMethodError)
                return
            }
            await confirmRide()

        case .none:
            confirmRideError = languageStore.settingsText(.addPaymentChooseMethodError)
        }
    }

    @MainActor
    private func startCashRideFlow() {
        guard !isConfirming, !rideInsertStarted, createdRideId == nil else { return }
        selectedPayment = .cash
        confirmRideError = nil
    }

    @MainActor
    private func startApplePayFlow() async {
        confirmRideError = nil
        isConfirming = true

        guard PKPaymentAuthorizationViewController.canMakePayments() else {
            confirmRideError = languageStore.settingsText(.addPaymentApplePayUnavailableError)
            isConfirming = false
            return
        }

        guard let amountCents = applePayAmountCents else {
            confirmRideError = languageStore.settingsText(.addPaymentFareUnavailableError)
            isConfirming = false
            return
        }

        let paymentRequest = StripeAPI.paymentRequest(
            withMerchantIdentifier: StripeConfig.applePayMerchantId,
            country: StripeConfig.applePayCountryCode,
            currency: StripeConfig.applePayCurrency
        )

        paymentRequest.paymentSummaryItems = [
            PKPaymentSummaryItem(
                label: StripeConfig.merchantDisplayName,
                amount: NSDecimalNumber(value: Double(amountCents) / 100.0)
            )
        ]

        guard let presentingVC = topMostViewController() else {
            confirmRideError = languageStore.settingsText(.addPaymentCouldNotPresentApplePayError)
            isConfirming = false
            return
        }

        let coordinator = ApplePayCoordinator(
            amountCents: amountCents,
            failedMessage: languageStore.settingsText(.addPaymentApplePayFailedError),
            cancelledMessage: languageStore.settingsText(.addPaymentApplePayCancelledError),
            onSuccess: {
                Task { @MainActor in
                    self.isConfirming = false
                    await self.confirmRide()
                }
            },
            onError: { message in
                DispatchQueue.main.async {
                    self.confirmRideError = message
                    self.isConfirming = false
                }
            }
        )

        guard let context = STPApplePayContext(paymentRequest: paymentRequest, delegate: coordinator) else {
            confirmRideError = languageStore.settingsText(.addPaymentApplePayConfigError)
            isConfirming = false
            return
        }

        applePayCoordinator = coordinator
        applePayContext = context

        context.presentApplePay(on: presentingVC)
    }

    private func topMostViewController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
        else { return nil }

        var top = root
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }

    final class ApplePayCoordinator: NSObject, STPApplePayContextDelegate {
        private let amountCents: Int
        private let failedMessage: String
        private let cancelledMessage: String
        private let onSuccess: () -> Void
        private let onError: (String) -> Void

        init(
            amountCents: Int,
            failedMessage: String,
            cancelledMessage: String,
            onSuccess: @escaping () -> Void,
            onError: @escaping (String) -> Void
        ) {
            self.amountCents = amountCents
            self.failedMessage = failedMessage
            self.cancelledMessage = cancelledMessage
            self.onSuccess = onSuccess
            self.onError = onError
        }

        func applePayContext(
            _ context: STPApplePayContext,
            didCreatePaymentMethod paymentMethod: STPPaymentMethod,
            paymentInformation: PKPayment
        ) async throws -> String {
            return try await createPaymentIntentClientSecret(
                paymentMethodId: paymentMethod.stripeId,
                amountCents: amountCents,
                currency: StripeConfig.applePayCurrency
            )
        }

        func applePayContext(
            _ context: STPApplePayContext,
            didCreatePaymentMethod paymentMethod: STPPaymentMethod,
            paymentInformation: PKPayment,
            completion: @escaping STPIntentClientSecretCompletionBlock
        ) {
            Task {
                do {
                    let clientSecret = try await createPaymentIntentClientSecret(
                        paymentMethodId: paymentMethod.stripeId,
                        amountCents: amountCents,
                        currency: StripeConfig.applePayCurrency
                    )
                    completion(clientSecret, nil)
                } catch {
                    completion(nil, error)
                }
            }
        }

        func applePayContext(
            _ context: STPApplePayContext,
            didCompleteWith status: STPPaymentStatus,
            error: Error?
        ) {
            switch status {
            case .success:
                onSuccess()
            case .error:
                onError(error?.localizedDescription ?? failedMessage)
            case .userCancellation:
                onError(cancelledMessage)
            @unknown default:
                onError(failedMessage)
            }
        }

        private func createPaymentIntentClientSecret(paymentMethodId: String, amountCents: Int, currency: String) async throws -> String {
            guard StripeConfig.createPaymentIntentURLString != "REPLACE_ME",
                  let url = URL(string: StripeConfig.createPaymentIntentURLString) else {
                throw NSError(domain: "ApplePay", code: 0, userInfo: [NSLocalizedDescriptionKey: failedMessage])
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let body: [String: Any] = [
                "paymentMethodId": paymentMethodId,
                "amount": amountCents,
                "currency": currency
            ]

            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let text = String(data: data, encoding: .utf8) ?? failedMessage
                throw NSError(domain: "ApplePay", code: 0, userInfo: [NSLocalizedDescriptionKey: text])
            }

            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let clientSecret = json?["clientSecret"] as? String else {
                throw NSError(domain: "ApplePay", code: 0, userInfo: [NSLocalizedDescriptionKey: failedMessage])
            }
            return clientSecret
        }
    }

    @MainActor
    private func confirmRide() async {
        guard !rideInsertStarted, createdRideId == nil else { return }
        logRideDispatchTrace("confirm tapped scheduledEpoch=\(scheduledForEpoch) pickupValid=\(CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(latitude: pickupLat, longitude: pickupLng))) dropoffValid=\(CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(latitude: dropoffLat, longitude: dropoffLng)))")
        print("[Ride creation] Local ride ID before Supabase insert: \(createdRideId?.uuidString ?? "none")")
        confirmRideError = nil
        rideInsertStarted = true
        isConfirming = true
        defer { isConfirming = false }

        if scheduledForEpoch <= 0 {
            let defaults = UserDefaults.standard
            var saved = defaults.double(forKey: "lumo_scheduled_for_epoch")
            if saved <= 0 { saved = defaults.double(forKey: "lumo_scheduled_for_epoch_to_pass") }
            if saved <= 0 { saved = defaults.double(forKey: "scheduledForEpochToPass") }
            if saved <= 0 { saved = defaults.double(forKey: "scheduled_for_epoch") }
            if saved > 0 { scheduledForEpoch = saved }
        }

        let now = Date()
        let effectiveIsScheduled: Bool = {
            guard scheduledForEpoch > 0 else { return false }
            let d = Date(timeIntervalSince1970: scheduledForEpoch)
            return d.timeIntervalSince(now) > 0
        }()

        let scheduledISO: String? = {
            guard effectiveIsScheduled else { return nil }
            let d = Date(timeIntervalSince1970: scheduledForEpoch)
            return iso8601(d)
        }()

        do {
            let ride = try await supabaseInsertRide(isScheduled: effectiveIsScheduled, scheduledISO: scheduledISO)
            print("[Ride creation] Supabase INSERT returned id: \(ride.id ?? "nil"), status: \(ride.status ?? "nil")")
            guard let parsedRideId = UUID(uuidString: ride.id ?? "") else {
                throw NSError(domain: "AddPaymentView", code: 2, userInfo: [NSLocalizedDescriptionKey: languageStore.settingsText(.addPaymentCouldNotConfirmRideError)])
            }

            createdRideId = parsedRideId
            print("[Ride creation] Using database ride ID: \(parsedRideId.uuidString)")
            SupabaseRideService.shared.beginObservingRideStatus(rideId: parsedRideId.uuidString)
            createdWasScheduled = effectiveIsScheduled
            createdScheduledForEpoch = effectiveIsScheduled ? scheduledForEpoch : 0

            if effectiveIsScheduled {
                UserDefaults.standard.set(parsedRideId.uuidString, forKey: "lumo_scheduled_ride_id")
                UserDefaults.standard.set(true, forKey: "lumo_scheduled_ride_id_is_database")
            }

            UserDefaults.standard.set(0, forKey: "lumo_scheduled_for_epoch")

            showRideConfirmed = true
        } catch {
            rideInsertStarted = false
            #if DEBUG
            let ns = error as NSError
            print("[Ride confirmation] failed domain=\(ns.domain) code=\(ns.code) message=\(ns.localizedDescription)")
            #endif
            confirmRideError = mapConfirmRideError(error)
        }
    }

    private func supabaseInsertRide(isScheduled: Bool, scheduledISO: String?) async throws -> SupabaseRideRow {
        if selectedPayment == .cash {
            return try await createAuthoritativeCashRide(scheduledISO: isScheduled ? scheduledISO : nil)
        }
        if selectedPayment == .test, simulatedPaymentEnabled {
            // The loopback-only test service has no payment provider. Its test
            // ride deliberately uses the cash-due server contract, so it can
            // exercise ride creation and dispatch without a charge or paid state.
            return try await createAuthoritativeCashRide(scheduledISO: isScheduled ? scheduledISO : nil)
        }
        // Electronic payments must be created by the server-owned payment flow.
        // This remains fail-closed for Card and Apple Pay, and for every hosted backend.
        throw NSError(domain: "AddPaymentView", code: 503,
                      userInfo: [NSLocalizedDescriptionKey: "Secure electronic ride payment is not configured."])
    }

    private func createAuthoritativeCashRide(scheduledISO: String?) async throws -> SupabaseRideRow {
        guard let user = Auth.auth().currentUser,
              let baseURL = URL(string: supabaseProjectURL) else { throw URLError(.userAuthenticationRequired) }
        let token = try await user.getIDToken()
        let rideType = rideTypeLabel?.caseInsensitiveCompare("Share") == .orderedSame ? "SHARE" : "STANDARD"
        let points: [String: Any] = [
            "p_pickup_lat": pickupLat, "p_pickup_lng": pickupLng,
            "p_dropoff_lat": dropoffLat, "p_dropoff_lng": dropoffLng,
            "p_ride_type": rideType, "p_passenger_count": 1
        ]
        func rpc(_ name: String, body: [String: Any]) async throws -> Any {
            var request = URLRequest(url: baseURL.appendingPathComponent("rest/v1/rpc/\(name)"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            guard (200...299).contains(http.statusCode) else {
                let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                throw RideCreationContract.rpcError(status: http.statusCode, payload: payload, operation: name)
            }
            return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        }
        var quoteBody = points
        quoteBody["p_client_quote_id"] = authoritativeQuoteRequestID.uuidString
        guard let quote = try await rpc("create_passenger_fare_quote_v1", body: quoteBody) as? [String: Any] else {
            throw URLError(.cannotParseResponse)
        }
        guard let quoteID = quote["quote_id"] as? String else { throw URLError(.cannotParseResponse) }
        let quoteAmount = (quote["estimated_total"] as? NSNumber)?.doubleValue
            ?? Double(quote["estimated_total"] as? String ?? "")
        guard let quoteAmount, quoteAmount > 0,
              let quoteCurrency = quote["currency"] as? String else { throw URLError(.cannotParseResponse) }
        let verifiedFare = quoteCurrency == "USD"
            ? String(format: "$%.2f", quoteAmount)
            : String(format: "%@ %.2f", quoteCurrency, quoteAmount)
        authoritativeCashFareText = verifiedFare
        if selectedPayment != .test, let displayedFare = estimatedFareAmount,
           abs(displayedFare - quoteAmount) > 0.01,
           approvedQuoteID != quoteID {
            approvedQuoteID = quoteID
            throw NSError(domain: "AddPaymentView", code: 409,
                          userInfo: [NSLocalizedDescriptionKey:
                            "Fare updated to \(verifiedFare). Review it, then tap Confirm ride again."])
        }
        var rideBody = points
        rideBody["p_client_request_id"] = authoritativeRideRequestID.uuidString
        rideBody["p_quote_id"] = quoteID
        rideBody["p_pickup_address"] = pickupAddress
        rideBody["p_dropoff_address"] = dropoffAddress
        rideBody["p_payment_method"] = "cash"
        if let scheduledISO { rideBody["p_scheduled_for"] = scheduledISO }
        else { rideBody["p_scheduled_for"] = NSNull() }
        let isTestPayment = selectedPayment == .test && simulatedPaymentEnabled
        let createOperation = isTestPayment ? "create_jiylo_local_test_ride_v1" : "create_passenger_ride_for_payment_v1"
        guard let ride = try await rpc(createOperation, body: rideBody) as? [String: Any] else {
            throw URLError(.cannotParseResponse)
        }
        try RideCreationContract.validate(ride, scheduled: scheduledISO != nil)
        if isTestPayment {
            // Creation, dispatch and the TEST marker commit together. A failed
            // marker can no longer leave an unmarked, already dispatched ride.
            guard ride["environment"] as? String == "TEST",
                  (ride["amount_charged_minor"] as? NSNumber)?.intValue == 0,
                  ride["receipt_currency"] as? String == "USD" else {
                throw URLError(.cannotParseResponse)
            }
        }
        return SupabaseRideRow(id: ride["id"] as? String, status: ride["status"] as? String)
    }

    private func legacyRideInsertDisabled(isScheduled: Bool, scheduledISO: String?) async throws -> SupabaseRideRow {
        guard let baseURL = URL(string: supabaseProjectURL), baseURL.host != nil else {
            throw URLError(.badURL)
        }

        var url = baseURL.appendingPathComponent("rest/v1/\(ridesTableName)")
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        comps?.queryItems = [URLQueryItem(name: "select", value: "*")]
        if let built = comps?.url {
            url = built
        }

        guard let user = Auth.auth().currentUser, !user.uid.isEmpty else {
            throw NSError(domain: "AddPaymentView", code: 401, userInfo: [NSLocalizedDescriptionKey: languageStore.settingsText(.addPaymentCouldNotConfirmRideError)])
        }
        let uid = user.uid

        let estimatedFare = estimatedFareAmount

        if !isScheduled, estimatedFare == nil {
            throw NSError(domain: "AddPaymentView", code: 422, userInfo: [NSLocalizedDescriptionKey: languageStore.settingsText(.addPaymentFareUnavailableError)])
        }

        var payload: [String: Any] = [
            "rider_id": uid,
            "status": isScheduled ? "scheduled" : "requested",
            "driver_id": NSNull(),
            "pickup_address": pickupAddress,
            "dropoff_address": dropoffAddress,
            "pickup_lat": pickupLat,
            "pickup_lng": pickupLng,
            "dropoff_lat": dropoffLat,
            "dropoff_lng": dropoffLng
        ]

        if let rideTypeLabel, !rideTypeLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if rideTypeLabel.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare("Share") == .orderedSame {
                payload["ride_mode"] = "SHARE"
            }
        }

        if isScheduled, let scheduledISO {
            payload["scheduled_for"] = scheduledISO
        }

        if let currency = normalizedCurrency {
            payload["currency"] = currency
        }

        if let estimatedFare {
            payload["estimated_fare"] = estimatedFare
        }

        if selectedPayment == .applePay, let estimatedFare {
            payload["paid_amount"] = estimatedFare
        }

        if selectedPayment == .cash {
            payload["payment_method"] = "cash"
            payload["payment_status"] = "cash_due"
        }

        let rideMode = (payload["ride_mode"] as? String) ?? "STANDARD"
        logRideDispatchTrace("insert prepared table=\(ridesTableName) rider=\(uid) status=\(payload["status"] as? String ?? "unknown") driver=nil rideMode=\(rideMode) pickup=(\(pickupLat),\(pickupLng)) dropoff=(\(dropoffLat),\(dropoffLng)) scheduled=\(isScheduled)")

        let body = try JSONSerialization.data(withJSONObject: payload, options: [])

        func perform(accessToken: String) async throws -> (Data, HTTPURLResponse) {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
            req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            req.setValue("return=representation", forHTTPHeaderField: "Prefer")
            req.httpBody = body

            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            return (data, http)
        }

        func firebaseIDToken(forcingRefresh: Bool = false) async throws -> String {
            let token = try await user.getIDToken(forcingRefresh: forcingRefresh)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty else {
                throw NSError(domain: "AddPaymentView", code: 401, userInfo: [NSLocalizedDescriptionKey: languageStore.settingsText(.addPaymentCouldNotConfirmRideError)])
            }
            return token
        }

        var result = try await perform(accessToken: firebaseIDToken())
        if result.1.statusCode == 401 {
            result = try await perform(accessToken: firebaseIDToken(forcingRefresh: true))
        }

        let data = result.0
        let code = result.1.statusCode
        let responseBody = String(data: data, encoding: .utf8) ?? "<non-UTF8 body>"
        print("[Ride creation] Supabase INSERT HTTP \(code): \(responseBody)")
        logRideDispatchTrace("insert response http=\(code)")

        guard (200...299).contains(code) else {
            throw NSError(domain: "Supabase", code: code, userInfo: [NSLocalizedDescriptionKey: responseBody.isEmpty ? languageStore.settingsText(.addPaymentCouldNotConfirmRideError) : responseBody])
        }

        let rows = try JSONDecoder().decode([SupabaseRideRow].self, from: data)
        let ride = rows.first ?? SupabaseRideRow(id: nil, status: nil)
        logRideDispatchTrace("insert succeeded ride=\(ride.id ?? "nil") status=\(ride.status ?? "nil") expectedDispatch=\(!isScheduled && ride.status == "requested" && rideMode == "STANDARD")")
        return ride
    }

    private var normalizedCurrency: String? {
        let trimmed = (currency ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return ["USD", "IQD"].contains(trimmed) ? trimmed : nil
    }

    private var estimatedFareAmount: Double? {
        if let fareUSD {
            return fareUSD
        }

        if let fareIQD {
            return Double(fareIQD)
        }

        return parseFareAmount(from: estimatedFareText)
    }

    private var applePayAmountCents: Int? {
        guard (normalizedCurrency == "USD" || fareUSD != nil),
              let amount = estimatedFareAmount,
              amount > 0 else {
            return nil
        }

        return Int((amount * 100).rounded())
    }

    private func parseFareAmount(from text: String?) -> Double? {
        guard let text else {
            return nil
        }

        let cleaned = text.replacingOccurrences(of: ",", with: "")
        let parts = cleaned.split { character in
            !(character.isNumber || character == ".")
        }

        for part in parts {
            if let value = Double(part), value > 0 {
                return value
            }
        }

        return nil
    }

    private var priceTextForSearching: String? {
        if selectedPayment == .test && simulatedPaymentEnabled { return "$0.00" }
        if let authoritativeCashFareText { return authoritativeCashFareText }
        if let estimatedFareText, !estimatedFareText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return estimatedFareText
        }

        if let fareUSD {
            return String(format: "$%.2f", fareUSD)
        }

        if let fareIQD {
            return "\(fareIQD) IQD"
        }

        return nil
    }

    private func mapConfirmRideError(_ error: Error) -> String {
        let ns = error as NSError

        if ns.domain == NSURLErrorDomain {
            let code = URLError.Code(rawValue: ns.code)
            switch code {
            case .cannotFindHost, .cannotConnectToHost:
                return languageStore.settingsText(.addPaymentServerReachError)
            case .notConnectedToInternet:
                return languageStore.settingsText(.addPaymentNoInternetError)
            case .timedOut:
                return languageStore.settingsText(.addPaymentRequestTimedOutError)
            default:
                return languageStore.settingsText(.addPaymentCouldNotConfirmRideError)
            }
        }

        let msg = ns.localizedDescription
        if !msg.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "\(languageStore.settingsText(.addPaymentCouldNotConfirmRidePrefix)) \(msg)"
        }

        return languageStore.settingsText(.addPaymentCouldNotConfirmRideError)
    }
}
