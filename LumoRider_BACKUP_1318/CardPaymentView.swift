import SwiftUI
import UIKit
import Stripe

// 🔗 Your deployed Firebase HTTPS Function URL
// (Leave this as-is if it's already working for POST requests.)
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

    // Now this only controls the fullScreenCover, not the sheet content.
    @State private var showRideConfirmed = false
    @State private var isProcessing = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 24) {

                // Top bar with close button
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

                // Title
                Text("Card details")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)

                // Stripe card entry field
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
                        .font(.system(size: 13))
                        .foregroundColor(.red)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 24)
                }

                Spacer()

                // Save + confirm button
                Button {
                    Task { await saveCardAndConfirm() }
                } label: {
                    HStack {
                        if isProcessing {
                            ProgressView()
                        } else {
                            Text(isCardValid ? "Save card & confirm ride" : "Enter a valid card")
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
                .disabled(!isCardValid || isProcessing)
            }
        }
        .animation(.easeInOut, value: showRideConfirmed)
        // 🚀 Show the RideConfirmedView FULL SCREEN on success
        .fullScreenCover(isPresented: $showRideConfirmed) {
            RideConfirmedView()
        }
    }

    // --------------------------------------------------
    // MARK: - Networking / Stripe logic
    // --------------------------------------------------

    private struct SetupIntentResponse: Decodable {
        let clientSecret: String
        let customerId: String?
    }

    private func saveCardAndConfirm() async {
        guard let cardParams = cardParams else {
            await MainActor.run { errorMessage = "Please enter a valid card." }
            return
        }

        await MainActor.run {
            isProcessing = true
            errorMessage = nil
        }

        do {
            // 1️⃣ Call your Firebase HTTPS function to create a SetupIntent
            var request = URLRequest(url: setupIntentURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let body: [String: Any] = [
                "userId": "demo-user-id"   // TODO: replace with your real user id later
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse else {
                throw NSError(
                    domain: "CardPaymentView",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid server response."]
                )
            }

            print("DEBUG /createSetupIntent status:", http.statusCode)

            if !(200...299).contains(http.statusCode) {
                let bodyString = String(data: data, encoding: .utf8) ?? "<non-UTF8 body>"
                print("DEBUG /createSetupIntent error body:", bodyString)
                throw NSError(
                    domain: "CardPaymentView",
                    code: http.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: "Server error (\(http.statusCode))."]
                )
            }

            let decoded = try JSONDecoder().decode(SetupIntentResponse.self, from: data)
            print("DEBUG /createSetupIntent decoded:", decoded)

            // 2️⃣ Confirm the SetupIntent on the device
            await confirmSetupIntent(clientSecret: decoded.clientSecret,
                                     paymentMethodParams: cardParams)

        } catch {
            print("DEBUG saveCardAndConfirm error:", error)
            await MainActor.run {
                errorMessage = error.localizedDescription
                isProcessing = false
            }
        }
    }

    private func confirmSetupIntent(clientSecret: String,
                                    paymentMethodParams: STPPaymentMethodParams) async {

        let params = STPSetupIntentConfirmParams(clientSecret: clientSecret)
        params.paymentMethodParams = paymentMethodParams

        // Find the top-most view controller for Stripe's 3DS flows
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
                            case .visa: brand = "Visa"
                            case .mastercard: brand = "Mastercard"
                            case .amex: brand = "American Express"
                            case .discover: brand = "Discover"
                            case .JCB: brand = "JCB"
                            case .dinersClub: brand = "Diners Club"
                            case .unionPay: brand = "UnionPay"
                            default: brand = "Card"
                            }

                            let saved: [String: String] = [
                                "brand": brand,
                                "last4": last4
                            ]

                            if let data = try? JSONSerialization.data(withJSONObject: saved, options: []) {
                                UserDefaults.standard.set(data, forKey: savedCardInfoKey)
                            }
                        }
                        // Mark that this user now has a saved card
                        UserDefaults.standard.set(true, forKey: "hasSavedCard")

                        // ✅ Show full-screen RideConfirmedView
                        showRideConfirmed = true
                        errorMessage = nil

                    case .failed:
                        errorMessage = error?.localizedDescription ?? "Failed to save card."

                    case .canceled:
                        errorMessage = "Card saving was cancelled."

                    @unknown default:
                        errorMessage = "Unexpected Stripe status."
                    }

                    isProcessing = false
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

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, STPPaymentCardTextFieldDelegate {
        let parent: StripeCardField

        init(_ parent: StripeCardField) { self.parent = parent }

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
