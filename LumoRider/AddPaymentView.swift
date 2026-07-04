import SwiftUI
import Foundation
import UIKit
import FirebaseAuth
import Stripe
import PassKit
import CoreLocation

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
    @State private var confirmRideError: String? = nil
    @State private var showRideConfirmed: Bool = false

    // MARK: - Apple Pay (Stripe)
    @State private var applePayCoordinator: ApplePayCoordinator? = nil
    @State private var applePayContext: STPApplePayContext? = nil

    // MARK: - Supabase config
    private let supabaseProjectURL = "https://rpryqbdodbieioebedjg.supabase.co"
    private let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJIUzI1NiIsInJlZiI6InJwcnlxYmRvZGJpZWlvZWJlZGpnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjUwNjE0MjYsImV4cCI6MjA4MDYzNzQyNn0.8ZTaA1bCyRUKb6U4NNZou6DMfXP3yyE1NeNL8Ljt9as"
    private let ridesTableName = "rides"

    enum PaymentChoice {
        case none
        case applePay
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
        isScheduledFlow ? "Schedule ride" : "Confirm ride"
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

                Text("Add payment")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)

                VStack(spacing: 16) {

                    paymentOptionRow(
                        icon: "applelogo",
                        title: "Apple Pay",
                        subtitle: "Pay instantly with Apple Wallet",
                        isSelected: selectedPayment == .applePay,
                        action: {
                            selectedPayment = .applePay
                            confirmRideError = nil
                        }
                    )

                    if let savedCard {
                        paymentOptionRow(
                            icon: "creditcard",
                            title: "\(savedCard.brand) •••• \(savedCard.last4)",
                            subtitle: "Card saved locally — re-enter to pay securely",
                            isSelected: selectedPayment == .savedCard,
                            action: {
                                selectedPayment = .savedCard
                                confirmRideError = nil
                                showCardSheet = true
                            }
                        )

                        paymentOptionRow(
                            icon: "plus.circle",
                            title: "Use a different card",
                            subtitle: "Add new credit or debit card",
                            isSelected: selectedPayment == .newCard,
                            action: {
                                selectedPayment = .newCard
                                confirmRideError = nil
                                showCardSheet = true
                            }
                        )

                        #if DEBUG
                        paymentOptionRow(
                            icon: "wrench.and.screwdriver",
                            title: "Test payment",
                            subtitle: "Skip payment (debug only)",
                            isSelected: selectedPayment == .test,
                            action: {
                                selectedPayment = .test
                                confirmRideError = nil
                            }
                        )
                        #endif
                    } else {
                        paymentOptionRow(
                            icon: "plus.circle",
                            title: "Use a different card",
                            subtitle: "Add new credit or debit card",
                            isSelected: selectedPayment == .newCard,
                            action: {
                                selectedPayment = .newCard
                                confirmRideError = nil
                                showCardSheet = true
                            }
                        )

                        #if DEBUG
                        paymentOptionRow(
                            icon: "wrench.and.screwdriver",
                            title: "Test payment",
                            subtitle: "Skip payment (debug only)",
                            isSelected: selectedPayment == .test,
                            action: {
                                selectedPayment = .test
                                confirmRideError = nil
                            }
                        )
                        #endif
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
        .fullScreenCover(isPresented: $showRideConfirmed) {
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
                            supabase: LumoSupabaseConfig(
                                baseURL: URL(string: supabaseProjectURL)!,
                                anonKey: supabaseAnonKey,
                                accessToken: nil
                            )
                        )
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
        case .savedCard:
            return savedCard != nil
        case .newCard:
            return true
        case .test:
            return true
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
            await startApplePayFlow()

        case .savedCard, .newCard:
            showCardSheet = true

        case .test:
            #if DEBUG
            await confirmRide()
            #else
            confirmRideError = "Please choose a payment method."
            #endif

        case .none:
            confirmRideError = "Please choose a payment method."
        }
    }

    @MainActor
    private func startApplePayFlow() async {
        confirmRideError = nil
        isConfirming = true

        guard PKPaymentAuthorizationViewController.canMakePayments() else {
            confirmRideError = "Apple Pay is not available on this device."
            isConfirming = false
            return
        }

        guard let amountCents = applePayAmountCents else {
            confirmRideError = "Trip fare is not available yet. Please go back and select the ride again."
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
            confirmRideError = "Could not present Apple Pay."
            isConfirming = false
            return
        }

        let coordinator = ApplePayCoordinator(
            amountCents: amountCents,
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
            confirmRideError = "Apple Pay is not configured correctly."
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
        private let onSuccess: () -> Void
        private let onError: (String) -> Void

        init(amountCents: Int, onSuccess: @escaping () -> Void, onError: @escaping (String) -> Void) {
            self.amountCents = amountCents
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
                onError(error?.localizedDescription ?? "Apple Pay failed.")
            case .userCancellation:
                onError("Apple Pay cancelled.")
            @unknown default:
                onError("Apple Pay failed.")
            }
        }

        private func createPaymentIntentClientSecret(paymentMethodId: String, amountCents: Int, currency: String) async throws -> String {
            guard StripeConfig.createPaymentIntentURLString != "REPLACE_ME",
                  let url = URL(string: StripeConfig.createPaymentIntentURLString) else {
                throw NSError(domain: "ApplePay", code: 0, userInfo: [NSLocalizedDescriptionKey: "Missing createPaymentIntent URL in StripeConfig.swift"])
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
                let text = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw NSError(domain: "ApplePay", code: 0, userInfo: [NSLocalizedDescriptionKey: text])
            }

            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let clientSecret = json?["clientSecret"] as? String else {
                throw NSError(domain: "ApplePay", code: 0, userInfo: [NSLocalizedDescriptionKey: "Backend did not return clientSecret"])
            }
            return clientSecret
        }
    }

    @MainActor
    private func confirmRide() async {
        guard !rideInsertStarted, createdRideId == nil else { return }
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
            guard let parsedRideId = UUID(uuidString: ride.id ?? "") else {
                throw NSError(domain: "AddPaymentView", code: 2, userInfo: [NSLocalizedDescriptionKey: "Supabase did not return a valid ride id."])
            }

            createdRideId = parsedRideId
            createdWasScheduled = effectiveIsScheduled
            createdScheduledForEpoch = effectiveIsScheduled ? scheduledForEpoch : 0

            UserDefaults.standard.set(0, forKey: "lumo_scheduled_for_epoch")

            showRideConfirmed = true
        } catch {
            rideInsertStarted = false
            confirmRideError = mapConfirmRideError(error)
        }
    }

    private func supabaseInsertRide(isScheduled: Bool, scheduledISO: String?) async throws -> SupabaseRideRow {
        guard let baseURL = URL(string: supabaseProjectURL), baseURL.host != nil else {
            throw URLError(.badURL)
        }

        var url = baseURL.appendingPathComponent("rest/v1/\(ridesTableName)")
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        comps?.queryItems = [URLQueryItem(name: "select", value: "*")]
        if let built = comps?.url {
            url = built
        }

        guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else {
            throw NSError(domain: "AddPaymentView", code: 401, userInfo: [NSLocalizedDescriptionKey: "Please sign in before confirming a ride."])
        }

        let estimatedFare = estimatedFareAmount

        if !isScheduled, estimatedFare == nil {
            throw NSError(domain: "AddPaymentView", code: 422, userInfo: [NSLocalizedDescriptionKey: "Trip fare is not available yet. Please go back and select the ride again."])
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

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        req.setValue("return=representation", forHTTPHeaderField: "Prefer")
        req.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, response) = try await URLSession.shared.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? -1

        guard (200...299).contains(code) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "Supabase", code: code, userInfo: [NSLocalizedDescriptionKey: body.isEmpty ? "Request failed." : body])
        }

        let rows = try JSONDecoder().decode([SupabaseRideRow].self, from: data)
        return rows.first ?? SupabaseRideRow(id: nil, status: nil)
    }

    private var normalizedCurrency: String? {
        let trimmed = (currency ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return trimmed == "USD" ? "USD" : nil
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
                return "Can’t reach the server. Check your Supabase Project URL and your internet connection."
            case .notConnectedToInternet:
                return "No internet connection. Please try again."
            case .timedOut:
                return "Request timed out. Please try again."
            default:
                return "Couldn’t confirm ride. Please try again."
            }
        }

        let msg = ns.localizedDescription
        if !msg.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Couldn’t confirm ride. \(msg)"
        }

        return "Couldn’t confirm ride. Please try again."
    }
}
