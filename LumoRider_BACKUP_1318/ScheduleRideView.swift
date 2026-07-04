import SwiftUI
import MapKit

struct ScheduleRideView: View {
    @Environment(\.dismiss) private var dismiss

    // Text fields
    @State private var pickupText: String = "Current location"
    @State private var dropoffText: String = ""

    // Time / type / notes
    @State private var pickupDate: Date = Date()
    @State private var selectedRideType: RideType = .standard
    @State private var notes: String = ""

    // 🔹 Autocomplete for DROPOFF only
    @StateObject private var dropoffCompleter = AddressSearchCompleter()
    @State private var showDropoffSuggestions: Bool = false
    @State private var isSelectingDropoffSuggestion: Bool = false

    // 🔹 Navigation to PAYMENT METHODS screen
    @State private var goToPayment: Bool = false

    enum RideType: String, CaseIterable {
        case standard = "Standard"
        case xl = "XL"
        case comfort = "Comfort"
        case luxury = "Luxury"
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Hidden navigation to "Add payment" (Apple Pay / Card) screen
            NavigationLink(
                destination: AddPaymentView(),   // ⬅️ CHANGED: was CardPaymentView()
                isActive: $goToPayment
            ) {
                EmptyView()
            }
            .hidden()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // TOP BAR
                    HStack {
                        Button { dismiss() } label: {
                            Circle()
                                .fill(Color.white.opacity(0.12))
                                .frame(width: 34, height: 34)
                                .overlay(
                                    Image(systemName: "chevron.left")
                                        .foregroundColor(.white)
                                )
                        }

                        Spacer()
                    }
                    .padding(.top, 8)

                    Text("Schedule a ride")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)

                    // PICKUP / DROPOFF CARD
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(spacing: 6) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 8, height: 8)

                                Rectangle()
                                    .fill(Color.white.opacity(0.4))
                                    .frame(width: 2, height: 18)

                                Image(systemName: "diamond.fill")
                                    .font(.system(size: 7))
                                    .foregroundColor(.white.opacity(0.7))
                            }

                            VStack(alignment: .leading, spacing: 12) {
                                // Pickup
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Pickup")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.white.opacity(0.6))

                                    TextField("Current location", text: $pickupText)
                                        .padding(10)
                                        .background(Color.white.opacity(0.06))
                                        .cornerRadius(10)
                                        .foregroundColor(.white.opacity(0.8))
                                }

                                // Dropoff
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Dropoff")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.white.opacity(0.6))

                                    ZStack(alignment: .leading) {
                                        if dropoffText.isEmpty {
                                            Text("Enter destination")
                                                .foregroundColor(Color.white.opacity(0.35))
                                                .padding(.horizontal, 16)
                                                .padding(.vertical, 12)
                                        }

                                        TextField("", text: $dropoffText)
                                            .foregroundColor(.white)
                                            .tint(.white)
                                            .padding(10)
                                            .onChange(of: dropoffText) { newValue in
                                                if isSelectingDropoffSuggestion {
                                                    isSelectingDropoffSuggestion = false
                                                    return
                                                }

                                                let trimmed = newValue.trimmingCharacters(in: .whitespaces)
                                                if trimmed.isEmpty {
                                                    showDropoffSuggestions = false
                                                    dropoffCompleter.results = []
                                                } else {
                                                    showDropoffSuggestions = true
                                                    dropoffCompleter.update(query: trimmed)
                                                }
                                            }
                                    }
                                    .background(Color.white.opacity(0.06))
                                    .cornerRadius(10)
                                }
                            }
                        }

                        // 🔽 Suggestions list for DROP-OFF
                        if showDropoffSuggestions && !dropoffCompleter.results.isEmpty {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(dropoffCompleter.results.indices, id: \.self) { index in
                                    let item = dropoffCompleter.results[index]
                                    Button {
                                        let full = item.title +
                                            (item.subtitle.isEmpty ? "" : ", \(item.subtitle)")

                                        // 👇 Mark this as a programmatic update so onChange ignores it
                                        isSelectingDropoffSuggestion = true
                                        dropoffText = full

                                        showDropoffSuggestions = false
                                        dropoffCompleter.results = []
                                    } label: {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.title)
                                                .font(.system(size: 14, weight: .medium))
                                                .foregroundColor(.white)

                                            if !item.subtitle.isEmpty {
                                                Text(item.subtitle)
                                                    .font(.system(size: 12))
                                                    .foregroundColor(.white.opacity(0.7))
                                            }
                                        }
                                        .padding(.vertical, 8)
                                        .padding(.horizontal, 8)
                                    }
                                    .buttonStyle(.plain)

                                    if index != dropoffCompleter.results.indices.last {
                                        Divider()
                                            .background(Color.white.opacity(0.15))
                                    }
                                }
                            }
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(12)
                        }
                    }
                    .padding(16)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(20)

                    // PICKUP TIME
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Pickup time")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.white)

                        DatePicker(
                            "",
                            selection: $pickupDate,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .labelsHidden()
                        .colorScheme(.dark)
                    }

                    // RIDE TYPE
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ride type")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.white)

                        HStack(spacing: 8) {
                            ForEach(RideType.allCases, id: \.self) { type in
                                Button {
                                    selectedRideType = type
                                } label: {
                                    Text(type.rawValue)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(
                                            selectedRideType == type ? .black : .white.opacity(0.7)
                                        )
                                        .padding(.vertical, 8)
                                        .padding(.horizontal, 14)
                                        .background(
                                            selectedRideType == type
                                            ? Color.white
                                            : Color.white.opacity(0.08)
                                        )
                                        .cornerRadius(16)
                                }
                            }
                        }
                    }

                    // NOTES
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notes for driver (optional)")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.white)

                        ZStack(alignment: .topLeading) {
                            if notes.isEmpty {
                                Text("E.g. “I have luggage” or “Pick me up from side entrance”")
                                    .foregroundColor(Color.white.opacity(0.35))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 14)
                            }

                            TextField(
                                "",
                                text: $notes,
                                axis: .vertical
                            )
                            .foregroundColor(.white)
                            .tint(.white)
                            .padding(10)
                        }
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(14)
                    }

                    // FARE / PAYMENT SUMMARY
                    VStack(spacing: 8) {
                        HStack {
                            Text("Estimated fare")
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.7))
                            Spacer()
                            Text("$18–24")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                        }

                        HStack {
                            Text("Payment")
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.7))
                            Spacer()
                            Text("•••• 3942 · Visa")
                                .font(.system(size: 15))
                                .foregroundColor(.white)
                        }
                    }
                    .padding(14)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(18)

                    // CONFIRM BUTTON
                    Button {
                        // Later you can add validation here (e.g., ensure dropoff is not empty)
                        goToPayment = true   // ⬅️ now opens AddPaymentView
                    } label: {
                        Text("Confirm ride")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.white)
                            .foregroundColor(.black)
                            .cornerRadius(28)
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .navigationBarBackButtonHidden(true)
    }
}

#Preview {
    NavigationStack {
        ScheduleRideView()
    }
}
