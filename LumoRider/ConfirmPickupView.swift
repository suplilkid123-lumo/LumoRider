import SwiftUI
import CoreLocation
import GoogleMaps

// MARK: - Confirm Pickup (Skipped)
// This screen is intentionally bypassed. We keep the same view signature so
// existing navigation continues to work, but we immediately show AddPaymentView.

struct ConfirmPickupView: View {
    @Environment(\.dismiss) private var dismiss

    let pickupAddress: String
    let pickupCoordinate: CLLocationCoordinate2D

    let dropoffAddress: String
    let dropoffCoordinate: CLLocationCoordinate2D

    let fareIQD: Int?
    let fareUSD: Double?
    let currency: String
    let rideId: UUID?
    let rideTypeLabel: String?
    let estimatedFareText: String?

    private var pickupAddressFinal: String {
        pickupAddress.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var dropoffAddressFinal: String {
        dropoffAddress.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        AddPaymentView(
            pickupAddress: pickupAddressFinal,
            dropoffAddress: dropoffAddressFinal,
            pickupLat: pickupCoordinate.latitude,
            pickupLng: pickupCoordinate.longitude,
            dropoffLat: dropoffCoordinate.latitude,
            dropoffLng: dropoffCoordinate.longitude,
            rideTypeLabel: rideTypeLabel,
            estimatedFareText: estimatedFareText,
            fareIQD: fareIQD,
            fareUSD: fareUSD,
            currency: currency
        )
        .onAppear {
            print("[CONFIRM PICKUP] pickup:", pickupAddressFinal)
            print("[CONFIRM PICKUP] dropoff:", dropoffAddressFinal)
        }
        .overlay(alignment: .topLeading) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.black.opacity(0.55))
                    .clipShape(Circle())
            }
            .padding(12)
        }
    }
}

// MARK: - Google Maps View for Confirm Pickup (kept for potential reuse)

struct ConfirmPickupMapView: UIViewRepresentable {
    @Binding var centerCoordinate: CLLocationCoordinate2D

    func makeUIView(context: Context) -> GMSMapView {
        let camera = GMSCameraPosition(
            latitude: centerCoordinate.latitude,
            longitude: centerCoordinate.longitude,
            zoom: 16
        )

        let mapView = GMSMapView(frame: .zero, camera: camera)
        mapView.isMyLocationEnabled = false
        mapView.settings.myLocationButton = false
        mapView.settings.compassButton = false

        mapView.delegate = context.coordinator

        // Apply your custom dark style
        mapView.applyLumoStyle()

        return mapView
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, GMSMapViewDelegate {
        var parent: ConfirmPickupMapView

        init(_ parent: ConfirmPickupMapView) {
            self.parent = parent
        }

        func mapView(_ mapView: GMSMapView, idleAt position: GMSCameraPosition) {
            parent.centerCoordinate = position.target
        }

        func mapView(_ mapView: GMSMapView, didChange position: GMSCameraPosition) {
            parent.centerCoordinate = position.target
        }
    }

    func updateUIView(_ mapView: GMSMapView, context: Context) {
        let camera = GMSCameraPosition(
            latitude: centerCoordinate.latitude,
            longitude: centerCoordinate.longitude,
            zoom: mapView.camera.zoom
        )
        mapView.animate(to: camera)

        // keep style applied in case Google resets it
        mapView.applyLumoStyle()
    }
}
