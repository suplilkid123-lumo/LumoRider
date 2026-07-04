// CardPaymentView.swift

import SwiftUI
import UIKit
import Stripe
import FirebaseAuth
import CoreLocation

// Legacy SetupIntent endpoint kept only for reference. Ride payments now use StripeConfig.createPaymentIntentURLString.
private let setupIntentURL = URL(string: "https://createsetupintent-d6466zkzmq-uc.a.run.app")!
private let savedCardInfoKey = "savedCardInfo"

// ------------------------------------------------------
// MARK: - Stripe Authentication Context Wrapper
// ------------------------------------------------------
final class PaymentAuthContext: NSObject, STPAuthenticationContext {
    private weak var presentingVC: UIViewController?

    init(presenting: UIViewController) {
        self.presentingVC = presenting
    }

    func authenticationPresentingViewController() -> UIViewController {
        presentingVC ?? UIViewController()
    }
}

// ------------------------------------------------------
// MARK: - Card Payment View
// ------------------------------------------------------
struct CardPaymentView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var isCardValid: Bool = false
    @State private var cardParams: STPPaymentMethodParams?
    @State private var createdRideId: UUID? = nil

    @State private var showRideConfirmed = false
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var debugStep: String?
    @State private var createdWasScheduled = false
    @State private var createdScheduledForEpoch: Double = 0
    @State private var scheduledForEpoch: Double
    @State private var rideInsertStarted = false
    @State private var stripePaymentIntentId: String? = nil

    let pickupAddress: String
    let dropoffAddress: String
    let pickupCoordinate: CLLocationCoordinate2D
    let dropoffCoordinate: CLLocationCoordinate2D
    let rideTypeLabel: String?
    let estimatedFareText: String?
    let fareIQD: Int?
    let fareUSD: Double?
    let currency: String?

    init(
        pickupAddress: String,
        dropoffAddress: String,
        pickupCoordinate: CLLocationCoordinate2D,
        dropoffCoordinate: CLLocationCoordinate2D,
        rideTypeLabel: String? = nil,
        estimatedFareText: String? = nil,
        fareIQD: Int? = nil,
        fareUSD: Double? = nil,
        currency: String? = nil,
        scheduledForEpoch: Double = 0
    ) {
        self.pickupAddress = pickupAddress
        self.dropoffAddress = dropoffAddress
        self.pickupCoordinate = pickupCoordinate
        self.dropoffCoordinate = dropoffCoordinate
        self.rideTypeLabel = rideTypeLabel
        self.estimatedFareText = estimatedFareText
        self.fareIQD = fareIQD
        self.fareUSD = fareUSD
        self.currency = currency
        _scheduledForEpoch = State(initialValue: scheduledForEpoch)
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

                Text("Card details")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)

                VStack(spacing: 16) {
                    Text("Enter your card information")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)

                    StripeCardField(cardParams: $cardParams, isValid: $isCardValid)
                        .frame(height: 50)
                        .padding(.horizontal, 24)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                        .multilineTextAlignment(.leading)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .padding(.horizontal, 24)
                }

                if let debugStep {
                    Text(debugStep)
                        .font(.system(size: 12))
                        .foregroundColor(.yellow)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 24)
                }

                Spacer()

                Button {
                    Task { await saveCardAndConfirm() }
                } label: {
                    HStack {
                        if isProcessing {
                            ProgressView()
                        } else {
                            Text(isCardValid ? "Confirm ride" : "Enter a valid card")
                        }
                    }
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(isCardValid ? Color.white : Color.white.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 30)
                .disabled(!isCardValid || isProcessing || rideInsertStarted)
            }
        }
        .animation(.easeInOut, value: showRideConfirmed)
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
            } else if let rideId = createdRideId {
                NavigationStack {
                    SearchingForDriverView(
                        rideId: rideId,
                        pickupAddress: pickupAddress,
                        dropoffAddress: dropoffAddress,
                        rideTypeLabel: rideTypeLabel,
                        priceText: priceTextForSearching,
                        supabase: LumoSupabaseConfig(
                            baseURL: URL(string: "https://rpryqbdodbieioebedjg.supabase.co")!,
                            anonKey: "eyJhbGciOiJIUzI1NiIsInJlZiI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJwcnlxYmRvZGJpZWlvZWJlZGpnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjUwNjE0MjYsImV4cCI6MjA4MDYzNzQyNn0.8ZTaA1bCyRUKb6U4NNZou6DMfXP3yyE1NeNL8Ljt9as",
                            accessToken: nil
                        )
                    )
                }
            }
        }
        .onAppear {
            Task {
                await configureStripeForCardPayment()
            }
        }
    }

    private struct SetupIntentResponse: Decodable {
        let clientSecret: String
        let customerId: String?
    }

    private struct PaymentIntentResponse: Decodable {
        let clientSecret: String?
        let client_secret: String?
        let paymentIntentId: String?
        let payment_intent_id: String?

        var resolvedClientSecret: String? {
            clientSecret ?? client_secret
        }

        var resolvedPaymentIntentId: String? {
            paymentIntentId ?? payment_intent_id
        }
    }

    private var normalizedCurrency: String? {
        let trimmed = (currency ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return trimmed == "USD" ? "USD" : nil
    }

    private var paymentAmountCents: Int? {
        guard (normalizedCurrency == "USD" || fareUSD != nil),
              let amount = estimatedFareAmount,
              amount > 0 else {
            return nil
        }

        return Int((amount * 100).rounded())
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

    private func parseFareAmount(from text: String?) -> Double? {
        guard let text else { return nil }

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

    private func iso8601(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }

    private func createRideInSupabase() async {
        let shouldInsert = await MainActor.run { () -> Bool in
            guard !rideInsertStarted, createdRideId == nil, !showRideConfirmed else { return false }
            rideInsertStarted = true
            isProcessing = true
            errorMessage = nil
            debugStep = "Step 5: inserting ride into Supabase"
            return true
        }

        guard shouldInsert else { return }

        guard let riderId = Auth.auth().currentUser?.uid, !riderId.isEmpty else {
            await MainActor.run {
                rideInsertStarted = false
                isProcessing = false
                errorMessage = "Please sign in before confirming a ride."
            }
            return
        }

        let displayName = Auth.auth().currentUser?.displayName
        let photoURL = Auth.auth().currentUser?.photoURL?.absoluteString

        let fallbackName = UserDefaults.standard.string(forKey: "lumo_profile_name")
        let fallbackPhoto = UserDefaults.standard.string(forKey: "lumo_profile_photo_url")

        let riderNameToSend: String = {
            if let n = displayName, !n.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return n
            }

            if let n = fallbackName, !n.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return n
            }

            return "Rider"
        }()

        let riderPhotoToSend: String = {
            if let p = photoURL, !p.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return p
            }

            if let p = fallbackPhoto, !p.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return p
            }

            return ""
        }()

        let now = Date()

        let effectiveIsScheduled: Bool = {
            guard scheduledForEpoch > 0 else { return false }
            let d = Date(timeIntervalSince1970: scheduledForEpoch)
            return d.timeIntervalSince(now) > 0
        }()

        let estimatedFare = estimatedFareAmount

        if !effectiveIsScheduled, estimatedFare == nil {
            await MainActor.run {
                rideInsertStarted = false
                isProcessing = false
                errorMessage = "Trip fare is not available yet. Please go back and select the ride again."
            }
            return
        }

        var body: [String: Any] = [
            "rider_id": riderId,
            "rider_name": riderNameToSend,
            "rider_photo_url": riderPhotoToSend,
            "rider_snapshot": [
                "uid": riderId,
                "name": riderNameToSend,
                "photoURL": riderPhotoToSend,
                "photo_url": riderPhotoToSend
            ],
            "pickup_lat": pickupCoordinate.latitude,
            "pickup_lng": pickupCoordinate.longitude,
            "dropoff_lat": dropoffCoordinate.latitude,
            "dropoff_lng": dropoffCoordinate.longitude,
            "pickup_address": pickupAddress,
            "dropoff_address": dropoffAddress,
            "status": effectiveIsScheduled ? "scheduled" : "requested",
            "driver_id": NSNull()
        ]

        if effectiveIsScheduled {
            body["scheduled_for"] = iso8601(Date(timeIntervalSince1970: scheduledForEpoch))
        }

        if let currency = normalizedCurrency {
            body["currency"] = currency
        }

        if let estimatedFare {
            body["estimated_fare"] = estimatedFare
            body["paid_amount"] = estimatedFare
        }

        if let stripePaymentIntentId,
           !stripePaymentIntentId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body["stripe_payment_intent_id"] = stripePaymentIntentId
            body["payment_status"] = "paid"
        }

        do {
            guard let url = URL(string: "https://rpryqbdodbieioebedjg.supabase.co/rest/v1/rides") else {
                throw NSError(domain: "CardPaymentView", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid Supabase URL"])
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJwcnlxYmRvZGJpZWlvZWJlZGpnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjUwNjE0MjYsImV4cCI6MjA4MDYzNzQyNn0.8ZTaA1bCyRUKb6U4NNZou6DMfXP3yyE1NeNL8Ljt9as", forHTTPHeaderField: "Authorization")
            request.setValue("eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJwcnlxYmRvZGJpZWlvZWJlZGpnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjUwNjE0MjYsImV4cCI6MjA4MDYzNzQyNn0.8ZTaA1bCyRUKb6U4NNZou6DMfXP3yyE1NeNL8Ljt9as", forHTTPHeaderField: "apikey")
            request.setValue("return=representation", forHTTPHeaderField: "Prefer")
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse else {
                throw NSError(domain: "CardPaymentView", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid server response"])
            }

            guard (200...299).contains(http.statusCode) else {
                let bodyString = String(data: data, encoding: .utf8) ?? "<non-UTF8 body>"
                print("❌ Supabase create ride response body:", bodyString)
                throw NSError(domain: "CardPaymentView", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Couldn’t confirm ride. Please try again."])
            }

            let json = try JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]]
            let responseBodyString = String(data: data, encoding: .utf8) ?? "<non-UTF8 body>"

            print("🔎 createRideInSupabase response body:", responseBodyString)
            print("🔎 riderNameToSend:", riderNameToSend)
            print("🔎 riderPhotoToSend:", riderPhotoToSend)

            let idString = json?.first?["id"] as? String

            await MainActor.run {
                isProcessing = false

                if let idString, let parsed = UUID(uuidString: idString) {
                    createdRideId = parsed
                    createdWasScheduled = effectiveIsScheduled
                    createdScheduledForEpoch = effectiveIsScheduled ? scheduledForEpoch : 0
                    UserDefaults.standard.set(0, forKey: "lumo_scheduled_for_epoch")
                    errorMessage = nil
                    debugStep = "Done: ride created"

                    Task {
                        await forcePatchRiderIdentity(
                            rideId: parsed,
                            riderId: riderId,
                            riderName: riderNameToSend,
                            riderPhotoURL: riderPhotoToSend
                        )

                        await MainActor.run {
                            showRideConfirmed = true
                        }
                    }
                } else {
                    rideInsertStarted = false
                    createdRideId = nil
                    showRideConfirmed = false
                    errorMessage = "Couldn’t confirm ride. Please try again."
                    print("❌ Invalid ride.id (not a UUID):", idString ?? "nil")
                }
            }
        } catch {
            await MainActor.run {
                rideInsertStarted = false
                isProcessing = false
                errorMessage = "Couldn’t confirm ride. Please try again."
                debugStep = "Failed at Step 5: inserting ride into Supabase"
                print("❌ Supabase create ride error:", error.localizedDescription)
            }
        }
    }

    private func forcePatchRiderIdentity(
        rideId: UUID,
        riderId: String,
        riderName: String,
        riderPhotoURL: String
    ) async {
        guard let url = URL(string: "https://rpryqbdodbieioebedjg.supabase.co/rest/v1/rides?id=eq.\(rideId.uuidString)") else {
            return
        }

        let patchBody: [String: Any] = [
            "rider_id": riderId,
            "rider_name": riderName,
            "rider_photo_url": riderPhotoURL,
            "rider_snapshot": [
                "uid": riderId,
                "name": riderName,
                "photoURL": riderPhotoURL,
                "photo_url": riderPhotoURL
            ]
        ]

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "PATCH"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJwcnlxYmRvZGJpZWlvZWJlZGpnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjUwNjE0MjYsImV4cCI6MjA4MDYzNzQyNn0.8ZTaA1bCyRUKb6U4NNZou6DMfXP3yyE1NeNL8Ljt9as", forHTTPHeaderField: "Authorization")
            request.setValue("eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJwcnlxYmRvZGJpZWlvZWJlZGpnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjUwNjE0MjYsImV4cCI6MjA4MDYzNzQyNn0.8ZTaA1bCyRUKb6U4NNZou6DMfXP3yyE1NeNL8Ljt9as", forHTTPHeaderField: "apikey")
            request.setValue("return=representation", forHTTPHeaderField: "Prefer")
            request.httpBody = try JSONSerialization.data(withJSONObject: patchBody, options: [])

            let (data, response) = try await URLSession.shared.data(for: request)
            let bodyString = String(data: data, encoding: .utf8) ?? "<non-UTF8 body>"

            if let http = response as? HTTPURLResponse {
                print("🔎 PATCH rider identity status:", http.statusCode)
                print("🔎 PATCH rider identity body:", bodyString)
            }
        } catch {
            print("❌ forcePatchRiderIdentity error:", error.localizedDescription)
        }
    }

    private func saveCardAndConfirm() async {
        guard let cardParams = cardParams else {
            await MainActor.run {
                errorMessage = "Please enter a valid card."
            }
            return
        }

        let shouldStart = await MainActor.run { () -> Bool in
            guard !isProcessing, !rideInsertStarted, createdRideId == nil else { return false }
            isProcessing = true
            errorMessage = nil
            debugStep = "Step 1: preparing card payment"
            return true
        }

        guard shouldStart else { return }

        guard let amountCents = paymentAmountCents else {
            await MainActor.run {
                errorMessage = "Trip fare is not available yet. Please go back and select the ride again."
                isProcessing = false
            }
            return
        }

        guard Auth.auth().currentUser?.uid.isEmpty == false else {
            await MainActor.run {
                errorMessage = "Please sign in before confirming a ride."
                isProcessing = false
            }
            return
        }

        do {
            await configureStripeForCardPayment()

            await MainActor.run {
                debugStep = "Step 2: calling create-payment-intent"
            }

            let clientSecret = try await createPaymentIntentClientSecret(
                amountCents: amountCents,
                currency: "usd"
            )

            await MainActor.run {
                debugStep = "Step 3: confirming Stripe PaymentIntent"
            }

            await confirmPaymentIntent(
                clientSecret: clientSecret,
                paymentMethodParams: cardParams
            )
        } catch {
            print("DEBUG card payment error:", error)

            await MainActor.run {
                errorMessage = error.localizedDescription

                if debugStep == nil {
                    debugStep = "Failed before payment started"
                } else if !(debugStep ?? "").hasPrefix("Failed") {
                    debugStep = "Failed at \(debugStep ?? "unknown step")"
                }

                isProcessing = false
            }
        }
    }

    private func configureStripeForCardPayment() async {
        await MainActor.run {
            let publishableKey = StripeConfig.publishableKey
                .trimmingCharacters(in: .whitespacesAndNewlines)

            StripeAPI.defaultPublishableKey = publishableKey
            STPAPIClient.shared.publishableKey = publishableKey

            let mode = publishableKey.hasPrefix("pk_live_") ? "LIVE" : "TEST"
            print("✅ CardPaymentView Stripe key forced from StripeConfig (\(mode))")
        }
    }

    private func createPaymentIntentClientSecret(
        amountCents: Int,
        currency: String,
        paymentMethodId: String? = nil
    ) async throws -> String {
        guard StripeConfig.createPaymentIntentURLString != "REPLACE_ME",
              let url = URL(string: StripeConfig.createPaymentIntentURLString) else {
            throw NSError(
                domain: "CardPaymentView",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Missing createPaymentIntent URL in StripeConfig.swift"]
            )
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var requestBody: [String: Any] = [
            "amount": amountCents,
            "currency": currency
        ]

        if let paymentMethodId, !paymentMethodId.isEmpty {
            requestBody["paymentMethodId"] = paymentMethodId
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody, options: [])

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "CardPaymentView", code: 0, userInfo: [NSLocalizedDescriptionKey: text])
        }

        if let decoded = try? JSONDecoder().decode(PaymentIntentResponse.self, from: data),
           let clientSecret = decoded.resolvedClientSecret,
           !clientSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            await MainActor.run {
                stripePaymentIntentId = decoded.resolvedPaymentIntentId
            }
            return clientSecret
        }

        if let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
            if let clientSecret = json["clientSecret"] as? String,
               !clientSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                await MainActor.run {
                    stripePaymentIntentId = (json["paymentIntentId"] as? String) ?? (json["payment_intent_id"] as? String)
                }
                return clientSecret
            }

            if let clientSecret = json["client_secret"] as? String,
               !clientSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                await MainActor.run {
                    stripePaymentIntentId = (json["paymentIntentId"] as? String) ?? (json["payment_intent_id"] as? String)
                }
                return clientSecret
            }
        }

        let bodyString = String(data: data, encoding: .utf8) ?? "<non-UTF8 body>"

        throw NSError(
            domain: "CardPaymentView",
            code: 0,
            userInfo: [
                NSLocalizedDescriptionKey: "Backend did not return a Stripe clientSecret. Response: \(bodyString)"
            ]
        )
    }

    private func stripeFailureMessage(_ error: Error?) -> String {
        guard let error else {
            return "Payment declined. Please use a real valid card."
        }

        let nsError = error as NSError
        let message = nsError.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let reason = nsError.localizedFailureReason?.trimmingCharacters(in: .whitespacesAndNewlines)
        let suggestion = nsError.localizedRecoverySuggestion?.trimmingCharacters(in: .whitespacesAndNewlines)

        let lowerMessage = message.lowercased()
        let lowerReason = reason?.lowercased() ?? ""
        let lowerSuggestion = suggestion?.lowercased() ?? ""
        let combinedLower = [lowerMessage, lowerReason, lowerSuggestion].joined(separator: " ")

        if combinedLower.contains("test card") ||
            combinedLower.contains("unexpected error") ||
            combinedLower.contains("try again in a few seconds") ||
            message.isEmpty {
            return "Payment declined. Please use a real valid card."
        }

        var parts: [String] = []

        if !message.isEmpty {
            parts.append(message)
        }

        if let reason, !reason.isEmpty, reason != message {
            parts.append(reason)
        }

        if let suggestion, !suggestion.isEmpty {
            parts.append(suggestion)
        }

        if parts.isEmpty {
            return "Payment declined. Please use a real valid card."
        }

        return "Payment declined. " + parts.joined(separator: " ")
    }

    private func confirmPaymentIntent(
        clientSecret: String,
        paymentMethodParams: STPPaymentMethodParams
    ) async {
        let params = STPPaymentIntentParams(clientSecret: clientSecret)
        params.paymentMethodParams = paymentMethodParams

        guard let rootVC = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow })?
            .rootViewController else {

            await MainActor.run {
                errorMessage = "Unexpected error. Please try again."
                isProcessing = false
            }
            return
        }

        let authContext = PaymentAuthContext(presenting: rootVC)

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            STPPaymentHandler.shared().confirmPayment(params, with: authContext) { status, paymentIntent, error in
                DispatchQueue.main.async {
                    switch status {
                    case .succeeded:
                        if let card = paymentIntent?.paymentMethod?.card,
                           let last4 = card.last4 {
                            let brand: String

                            switch card.brand {
                            case .visa:
                                brand = "Visa"
                            case .mastercard:
                                brand = "Mastercard"
                            case .amex:
                                brand = "American Express"
                            case .discover:
                                brand = "Discover"
                            case .JCB:
                                brand = "JCB"
                            case .dinersClub:
                                brand = "Diners Club"
                            case .unionPay:
                                brand = "UnionPay"
                            default:
                                brand = "Card"
                            }

                            let saved: [String: String] = [
                                "brand": brand,
                                "last4": last4
                            ]

                            if let data = try? JSONSerialization.data(withJSONObject: saved, options: []) {
                                UserDefaults.standard.set(data, forKey: savedCardInfoKey)
                            }
                        }

                        if let confirmedIntentId = paymentIntent?.stripeId,
                           !confirmedIntentId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            stripePaymentIntentId = confirmedIntentId
                        }
                        UserDefaults.standard.set(true, forKey: "hasSavedCard")
                        debugStep = "Step 4: payment succeeded, creating ride"

                        Task {
                            await createRideInSupabase()
                        }

                    case .failed:
                        let message = stripeFailureMessage(error)
                        errorMessage = message
                        debugStep = "Payment declined — ride was not created"
                        isProcessing = false

                        print("❌ Stripe PaymentIntent confirm failed:", message)

                        if let error {
                            print("❌ Raw Stripe confirm error:", error.localizedDescription)
                        }

                    case .canceled:
                        errorMessage = "Payment was cancelled."
                        debugStep = "Cancelled at Step 3: confirming Stripe PaymentIntent"
                        isProcessing = false

                    @unknown default:
                        errorMessage = "Unexpected Stripe status."
                        debugStep = "Failed at Step 3: unexpected Stripe status"
                        isProcessing = false
                    }

                    continuation.resume()
                }
            }
        }
    }

    private func confirmSetupIntent(
        clientSecret: String,
        paymentMethodParams: STPPaymentMethodParams
    ) async {
        let params = STPSetupIntentConfirmParams(clientSecret: clientSecret)
        params.paymentMethodParams = paymentMethodParams

        guard let rootVC = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow })?
            .rootViewController else {

            await MainActor.run {
                errorMessage = "Unexpected error. Please try again."
                isProcessing = false
            }
            return
        }

        let authContext = PaymentAuthContext(presenting: rootVC)

        await withCheckedContinuation { continuation in
            STPPaymentHandler.shared().confirmSetupIntent(params, with: authContext) { status, setupIntent, error in
                DispatchQueue.main.async {
                    switch status {
                    case .succeeded:
                        if let card = setupIntent?.paymentMethod?.card,
                           let last4 = card.last4 {
                            let brand: String

                            switch card.brand {
                            case .visa:
                                brand = "Visa"
                            case .mastercard:
                                brand = "Mastercard"
                            case .amex:
                                brand = "American Express"
                            case .discover:
                                brand = "Discover"
                            case .JCB:
                                brand = "JCB"
                            case .dinersClub:
                                brand = "Diners Club"
                            case .unionPay:
                                brand = "UnionPay"
                            default:
                                brand = "Card"
                            }

                            let saved: [String: String] = [
                                "brand": brand,
                                "last4": last4
                            ]

                            if let data = try? JSONSerialization.data(withJSONObject: saved, options: []) {
                                UserDefaults.standard.set(data, forKey: savedCardInfoKey)
                            }
                        }

                        UserDefaults.standard.set(true, forKey: "hasSavedCard")

                        Task {
                            await createRideInSupabase()
                        }

                    case .failed:
                        errorMessage = error?.localizedDescription ?? "Failed to save card."
                        isProcessing = false

                    case .canceled:
                        errorMessage = "Card saving was cancelled."
                        isProcessing = false

                    @unknown default:
                        errorMessage = "Unexpected Stripe status."
                    }

                    continuation.resume()
                }
            }
        }
    }
}

// ------------------------------------------------------
// MARK: - Stripe Card Field Wrapper
// ------------------------------------------------------
struct StripeCardField: UIViewRepresentable {
    @Binding var cardParams: STPPaymentMethodParams?
    @Binding var isValid: Bool

    func makeUIView(context: Context) -> STPPaymentCardTextField {
        let field = STPPaymentCardTextField()
        field.backgroundColor = .clear
        field.textColor = .white
        field.borderWidth = 0
        field.cursorColor = .white
        field.delegate = context.coordinator
        return field
    }

    func updateUIView(_ uiView: STPPaymentCardTextField, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, STPPaymentCardTextFieldDelegate {
        let parent: StripeCardField

        init(_ parent: StripeCardField) {
            self.parent = parent
        }

        func paymentCardTextFieldDidChange(_ textField: STPPaymentCardTextField) {
            parent.isValid = textField.isValid

            guard textField.isValid else {
                parent.cardParams = nil
                return
            }

            let card = textField.cardParams
            let billingDetails = STPPaymentMethodBillingDetails()

            parent.cardParams = STPPaymentMethodParams(
                card: card,
                billingDetails: billingDetails,
                metadata: nil
            )
        }
    }
}
