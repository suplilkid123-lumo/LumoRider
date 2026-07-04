// RideConfirmedView.swift

import SwiftUI
import FirebaseAuth
import CoreLocation
import UIKit

// Compatibility shim:
// If anything navigates to RideConfirmedView, we SKIP this screen and go straight to tracking.
struct RideConfirmedView: View {
    let rideId: UUID
    let pickupAddress: String
    let dropoffAddress: String

    private var riderId: String {
        Auth.auth().currentUser?.uid ?? ""
    }

    init(rideId: UUID, pickupAddress: String = "", dropoffAddress: String = "") {
        self.rideId = rideId
        self.pickupAddress = pickupAddress
        self.dropoffAddress = dropoffAddress
    }

    var body: some View {
        DriverTrackingView(rideId: rideId.uuidString)
            .navigationBarBackButtonHidden(true)
    }
}

#Preview {
    NavigationStack {
        RideConfirmedView(
            rideId: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!,
            pickupAddress: "Pickup",
            dropoffAddress: "Drop-off"
        )
    }
}
