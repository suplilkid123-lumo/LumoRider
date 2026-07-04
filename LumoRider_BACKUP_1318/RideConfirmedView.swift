import SwiftUI
import CoreLocation
import UIKit   // 👈 Needed for UIApplication

struct RideConfirmedView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showTracking = false      // controls Track driver screen

    // You can override these when you present the view if you want:
    // RideConfirmedView(pickupAddress: "105 W First St", dropoffAddress: "O'Hare Airport")
    var pickupAddress: String = "Pickup location"
    var dropoffAddress: String = "Drop-off location"

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 32) {

                Spacer()

                // Checkmark icon
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 110, height: 110)

                    Circle()
                        .fill(Color.black)
                        .frame(width: 72, height: 72)

                    Image(systemName: "checkmark")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundColor(.white)
                }

                // Title and subtitle
                VStack(spacing: 8) {
                    Text("Ride confirmed")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.white)

                    Text("A driver will be assigned shortly for your trip.")
                        .font(.system(size: 15))
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                // Trip details card
                VStack(alignment: .leading, spacing: 16) {
                    Text("Trip details")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)

                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 8))
                                .foregroundColor(.white)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Pickup")
                                    .font(.system(size: 13))
                                    .foregroundColor(.white.opacity(0.6))

                                Text(pickupAddress)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.white)
                            }
                        }

                        Divider()
                            .background(Color.white.opacity(0.18))

                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "key.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.white)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Drop-off")
                                    .font(.system(size: 13))
                                    .foregroundColor(.white.opacity(0.6))

                                Text(dropoffAddress)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.white)
                            }
                        }
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .padding(.horizontal, 24)

                Spacer()

                // Primary button: Track driver (full-screen sheet)
                Button(action: {
                    showTracking = true
                }) {
                    Text("Track driver")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 28))
                }
                .padding(.horizontal, 24)

                // Secondary: Back to home (dismiss ALL presented screens)
                Button(action: {
                    dismissToHome()
                }) {
                    Text("Back to home")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.top, 10)
                }
                .padding(.bottom, 30)
            }
        }
        .navigationBarBackButtonHidden(true)
        .fullScreenCover(isPresented: $showTracking) {
            DriverTrackingView()
        }
    }

    /// Dismisses all presented view controllers so the user returns to the root
    private func dismissToHome() {
        // Try to dismiss all UIKit presentations (sheets / fullScreenCovers, etc.)
        if let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first,
           let root = scene.windows.first?.rootViewController {
            root.dismiss(animated: true)
        } else {
            // Fallback: just dismiss the nearest presentation
            dismiss()
        }
    }
}

#Preview {
    NavigationStack {
        RideConfirmedView()
    }
}
