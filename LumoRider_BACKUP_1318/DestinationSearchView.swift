import SwiftUI
import MapKit
import Combine

// MARK: - Autocomplete helper

@MainActor
class AddressSearchCompleter: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var results: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
    }

    func update(query: String) {
        completer.queryFragment = query
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        results = completer.results
    }
}

// MARK: - DestinationSearchView

struct DestinationSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var locationManager: LumoLocationManager
    @StateObject private var completer = AddressSearchCompleter()

    @State private var destinationText: String = ""
    @FocusState private var isFocused: Bool
    @State private var isSelectingSuggestion: Bool = false

    @State private var showRideOptions: Bool = false   // 👈 new

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 20) {

                // Grabber
                Capsule()
                    .fill(Color.white.opacity(0.4))
                    .frame(width: 40, height: 5)
                    .padding(.top, 14)

                // Top bar
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.down")
                            .foregroundColor(.white)
                            .padding(8)
                            .background(Color.white.opacity(0.2))
                            .clipShape(Circle())
                    }

                    Spacer()

                    Text("Set your trip")
                        .foregroundColor(.white)
                        .font(.system(size: 17, weight: .semibold))

                    Spacer().frame(width: 32)
                }
                .padding(.horizontal, 24)

                // Card with pickup + destination
                VStack(spacing: 0) {

                    // Pickup
                    HStack(spacing: 12) {
                        Image(systemName: "smallcircle.filled.circle.fill")
                            .foregroundColor(.green)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Pickup")
                                .font(.system(size: 13))
                                .foregroundColor(.gray)

                            Text(locationManager.currentAddress)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.black)
                                .lineLimit(2)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                    .padding(.bottom, 12)

                    Divider().padding(.horizontal, 18)

                    // Destination
                    HStack(spacing: 12) {
                        Image(systemName: "mappin.circle.fill")
                            .foregroundColor(.black)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Destination")
                                .font(.system(size: 13))
                                .foregroundColor(.gray)

                            TextField("Where to?", text: $destinationText)
                                .font(.system(size: 16))
                                .foregroundColor(.black)
                                .focused($isFocused)
                                .onChange(of: destinationText) { newValue in
                                    // Ignore programmatic changes from selection
                                    if isSelectingSuggestion {
                                        isSelectingSuggestion = false
                                        return
                                    }

                                    guard isFocused else { return }

                                    let trimmed = newValue.trimmingCharacters(in: .whitespaces)
                                    if trimmed.isEmpty {
                                        completer.results = []
                                    } else {
                                        completer.update(query: trimmed)
                                    }
                                }
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                }
                .background(Color.white)
                .cornerRadius(20)
                .padding(.horizontal, 16)

                // Suggestions
                if !completer.results.isEmpty {
                    ScrollView {
                        VStack(spacing: 14) {
                            ForEach(completer.results, id: \.self) { item in
                                Button {
                                    isSelectingSuggestion = true
                                    isFocused = false
                                    destinationText = "\(item.title), \(item.subtitle)"
                                    completer.results = []
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.title)
                                            .foregroundColor(.white)
                                            .font(.system(size: 16, weight: .medium))

                                        if !item.subtitle.isEmpty {
                                            Text(item.subtitle)
                                                .foregroundColor(.white.opacity(0.7))
                                                .font(.system(size: 13))
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)

                                Divider().background(Color.white.opacity(0.2))
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                }

                Spacer()

                // Continue button at the bottom
                Button {
                    showRideOptions = true
                } label: {
                    Text("Continue")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(destinationText.isEmpty ? Color.white.opacity(0.3) : Color.white)
                        .foregroundColor(.black)
                        .cornerRadius(30)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .disabled(destinationText.isEmpty)
            }
        }
        .sheet(isPresented: $showRideOptions) {
            // fall back to SF center if we somehow lack a coordinate
            let pickupCoord = locationManager.region?.center
                ?? CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)

            RideOptionsView(
                pickupAddress: locationManager.currentAddress,
                destinationAddress: destinationText,
                pickupCoordinate: pickupCoord
            )
        }
    }
}

#Preview {
    DestinationSearchView(locationManager: LumoLocationManager())
}

