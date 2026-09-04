// RideConfirmedView.swift

import SwiftUI
// Legacy compatibility type. Active-ride navigation is now owned by
// SearchingForDriverView or HomeView and must not be recreated here.
struct RideConfirmedView: View {
    let rideId: UUID
    let pickupAddress: String
    let dropoffAddress: String

    init(rideId: UUID, pickupAddress: String = "", dropoffAddress: String = "") {
        self.rideId = rideId
        self.pickupAddress = pickupAddress
        self.dropoffAddress = dropoffAddress
    }

    var body: some View {
        EmptyView()
    }
}
