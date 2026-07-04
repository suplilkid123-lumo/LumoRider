import SwiftUI

struct DeliveryRequestView: View {
    @State private var pickupLocation: String = ""
    @State private var dropoffLocation: String = ""
    @State private var packageDetails: String = ""

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Text("Request a Delivery")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.top, 20)

                Group {
                    TextField("Pickup Location", text: $pickupLocation)
                    TextField("Drop-off Location", text: $dropoffLocation)
                    TextField("Package / Food Details", text: $packageDetails)
                }
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal)

                Button {
                    // 🔗 Later: send this data to Firestore / Supabase
                    print("Delivery from \(pickupLocation) to \(dropoffLocation). Details: \(packageDetails)")
                } label: {
                    Text("Confirm Delivery Request")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.white)
                        .foregroundColor(.black)
                        .cornerRadius(12)
                        .padding(.horizontal)
                }

                Spacer()
            }
        }
        .navigationTitle("Delivery")
        .navigationBarTitleDisplayMode(.inline)
    }
}
