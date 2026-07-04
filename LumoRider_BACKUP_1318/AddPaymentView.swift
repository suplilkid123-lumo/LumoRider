import SwiftUI

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

struct AddPaymentView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var showCardSheet: Bool = false
    @State private var savedCard = loadSavedCardInfo()
    @State private var showRideConfirmed: Bool = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 24) {

                // ===== TOP BAR (down arrow button) =====
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

                // ===== TITLE =====
                Text("Add payment")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)

                // ===== PAYMENT OPTIONS =====
                VStack(spacing: 16) {

                    // Apple Pay
                    paymentOptionRow(
                        icon: "applelogo",
                        title: "Apple Pay",
                        subtitle: "Pay instantly with Apple Wallet",
                        action: {
                            print("Apple Pay tapped")
                        }
                    )

                    // If user has a saved card, show it as an option
                    if let savedCard {
                        // Saved card row
                        paymentOptionRow(
                            icon: "creditcard",
                            title: "\(savedCard.brand) •••• \(savedCard.last4)",
                            subtitle: "Use saved card",
                            action: {
                                // Directly show the RideConfirmedView full screen
                                showRideConfirmed = true
                            }
                        )

                        // Also show “use a different card”
                        paymentOptionRow(
                            icon: "plus.circle",
                            title: "Use a different card",
                            subtitle: "Add new credit or debit card",
                            action: {
                                showCardSheet = true
                            }
                        )
                    } else {
                        // No saved card yet: just show the normal card option
                        paymentOptionRow(
                            icon: "creditcard",
                            title: "Card",
                            subtitle: "Use a credit or debit card",
                            action: {
                                showCardSheet = true
                            }
                        )
                    }
                }
                .padding(.horizontal, 24)

                Spacer()
            }
        }
        .sheet(isPresented: $showCardSheet, onDismiss: {
            // When the sheet closes, reload saved card info
            savedCard = loadSavedCardInfo()
        }) {
            CardPaymentView()
                .presentationDetents([.fraction(0.55), .large])
                .presentationDragIndicator(.visible)
        }
        // 🔹 Hide the system back button so only ONE arrow shows
        .navigationBarBackButtonHidden(true)
        .fullScreenCover(isPresented: $showRideConfirmed) {
            RideConfirmedView()
        }
    }

    // MARK: - Payment Row Component
    func paymentOptionRow(
        icon: String,
        title: String,
        subtitle: String,
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

                Image(systemName: "chevron.right")
                    .foregroundColor(.white.opacity(0.6))
                    .font(.system(size: 14, weight: .semibold))
            }
            .padding()
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
    }
}
