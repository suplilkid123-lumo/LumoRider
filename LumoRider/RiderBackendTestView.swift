import SwiftUI

struct RiderBackendTestView: View {
    @State private var isLoading = false
    @State private var resultText: String = "No request yet"

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 20) {
                Text("Rider Backend Test")
                    .font(.title2)
                    .foregroundColor(.white)

                Button(action: {
                    Task { await testCreateRide() }
                }) {
                    Text(isLoading ? "Sending..." : "Create Test Ride")
                        .foregroundColor(.black)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.white)
                        .cornerRadius(12)
                }
                .disabled(isLoading)
                .padding(.horizontal, 24)

                Text(resultText)
                    .foregroundColor(.white.opacity(0.8))
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Spacer()
            }
            .padding(.top, 60)
        }
    }

    // MARK: - Test

    private func testCreateRide() async {
        await MainActor.run {
            isLoading = true
            resultText = "Sending request..."
        }

        do {
            let api = LumoAPI()

            // Dummy coordinates (Chicago)
            let request = CreateRideRequest(
                riderId: "test-rider-1",
                pickupLat: 41.8781,
                pickupLng: -87.6298,
                dropoffLat: 41.8810,
                dropoffLng: -87.6278,
                pickupAddress: "Chicago Downtown",
                dropoffAddress: "Chicago Riverwalk"
            )

            let ride = try await api.createRide(request)

            await MainActor.run {
                isLoading = false
                resultText = "✅ Created ride with id:\n\(ride.id)\nstatus: \(ride.status)"
            }
        } catch {
            await MainActor.run {
                isLoading = false
                resultText = "❌ Error: \(error.localizedDescription)"
            }
        }
    }
}

#Preview {
    RiderBackendTestView()
}
