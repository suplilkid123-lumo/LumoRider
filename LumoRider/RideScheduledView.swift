import SwiftUI

struct RideScheduledView: View {
    let pickupAddress: String
    let dropoffAddress: String
    let scheduledForEpoch: Double
    let onDone: () -> Void
    @AppStorage("lumo_scheduled_payment_done") private var scheduledPaymentDoneFlag: Bool = false

    private var scheduledText: String {
        let d = Date(timeIntervalSince1970: scheduledForEpoch)
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: d)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 18) {
                Spacer()

                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundColor(.white)

                Text("Ride scheduled")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.white)

                Text("We’ll start finding a driver closer to your pickup time.")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 26)

                VStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Pickup")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white.opacity(0.7))
                        Text(pickupAddress.isEmpty ? "(not set)" : pickupAddress)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 18))

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Dropoff")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white.opacity(0.7))
                        Text(dropoffAddress.isEmpty ? "(not set)" : dropoffAddress)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 18))

                    HStack {
                        Text("Pickup time")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white.opacity(0.7))
                        Spacer()
                        Text(scheduledText)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 2)
                }
                .padding(.horizontal, 22)

                Spacer()

                Button {
                    // ✅ Finish scheduled flow and return to Home
                    scheduledPaymentDoneFlag = true
                    onDone()
                } label: {
                    Text("Done")
                        .font(.system(size: 18, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.white)
                        .foregroundColor(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 999))
                        .padding(.horizontal, 24)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 18)
            }
        }
    }
}

#Preview {
    RideScheduledView(
        pickupAddress: "Current location",
        dropoffAddress: "2155 W 22nd St, Oak Brook, IL",
        scheduledForEpoch: Date().addingTimeInterval(3600).timeIntervalSince1970,
        onDone: {}
    )
}
