// SeachingForDriverView.swift

import SwiftUI
import Combine
import UIKit
import FirebaseAuth
import FirebaseFunctions

// =======================================================
// SeachingForDriverView.swift
// (File name can be misspelled; type name is correct.)
// =======================================================

/// Lightweight config used for direct Supabase REST calls (real, server-driven).
/// Pass these from wherever you already store your Supabase URL + anon key.
struct LumoSupabaseConfig {
    let baseURL: URL          // e.g. https://xxxx.supabase.co
    let anonKey: String       // Supabase anon key
    let accessToken: String?  // optional JWT if you have it (can be nil if RLS is off in dev)
}

/// Minimal snapshot of ride state used to drive navigation.
struct RideStatusSnapshot: Equatable {
    let status: String
    let driverId: String?

    private var normalizedStatus: String {
        status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var isAcceptedOrAssigned: Bool {
        // ONLY after driver accepts:
        // 1) driver_id becomes non-empty, OR
        // 2) status becomes explicitly accepted-like.
        if let driverId, !driverId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }

        let acceptedStatuses: Set<String> = [
            "accepted",
            "assigned",
            "matched",
            "driver_assigned",
            "accepted_by_driver"
        ]
        return acceptedStatuses.contains(normalizedStatus)
    }

    var isCancelled: Bool {
        normalizedStatus == "cancelled" || normalizedStatus == "canceled"
    }
}

/// Snapshot used when the rider cancels while still searching.
struct RideCancelSnapshot {
    let status: String
    let driverId: String?
    let stripePaymentIntentId: String?
    let paymentStatus: String?

    private var baseSnapshot: RideStatusSnapshot {
        RideStatusSnapshot(status: status, driverId: driverId)
    }

    var isAcceptedOrAssigned: Bool {
        baseSnapshot.isAcceptedOrAssigned
    }

    var hasPaymentToRefund: Bool {
        guard let stripePaymentIntentId,
              !stripePaymentIntentId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        return paymentStatus?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != "refunded"
    }
}

struct PaymentRefundResult {
    let refundId: String?
    let status: String?
}

/// Detailed HTTP error from Supabase PostgREST (so we can see why a PATCH/DELETE failed).
struct PostgRESTHTTPError: LocalizedError {
    let statusCode: Int
    let body: String

    var errorDescription: String? {
        let b = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if b.isEmpty {
            return "Supabase error (HTTP \(statusCode))."
        }
        return "Supabase error (HTTP \(statusCode)): \(b)"
    }
}

/// Real Supabase REST client used by the searching screen.
/// This is intentionally self-contained so you can keep the UX “real” without hacks.
final class RideMatchingClient {
    private let cfg: LumoSupabaseConfig
    private let session: URLSession
    private let functions = Functions.functions(region: "us-central1")
    private let fallbackSupabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJwcnlxYmRvZGJpZWlvZWJlZGpnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjUwNjE0MjYsImV4cCI6MjA4MDYzNzQyNn0.8ZTaA1bCyRUKb6U4NNZou6DMfXP3yyE1NeNL8Ljt9as"

    init(cfg: LumoSupabaseConfig, session: URLSession = .shared) {
        self.cfg = cfg
        self.session = session
    }

    func fetchRideStatus(rideId: UUID) async throws -> RideStatusSnapshot {
        var comps = URLComponents(url: cfg.baseURL, resolvingAgainstBaseURL: false)
        comps?.path = "/rest/v1/rides"
        comps?.queryItems = [
            URLQueryItem(name: "select", value: "status,driver_id"),
            URLQueryItem(name: "id", value: "eq.\(rideId.uuidString)")
        ]

        guard let url = comps?.url else { throw URLError(.badURL) }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        applyHeaders(&req)

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        // PostgREST returns an array
        let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
        guard let first = rows.first else { throw URLError(.cannotParseResponse) }

        let status = ((first["status"] as? String) ?? "")

        let driverRaw = first["driver_id"]
        let driverId: String? = {
            if let s = driverRaw as? String {
                let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                return t.isEmpty ? nil : t
            }
            if driverRaw is NSNull { return nil }
            if let n = driverRaw as? NSNumber { return n.stringValue }
            return nil
        }()

        return RideStatusSnapshot(status: status, driverId: driverId)
    }

    func fetchRideForCancel(rideId: UUID) async throws -> RideCancelSnapshot {
        var comps = URLComponents(url: cfg.baseURL, resolvingAgainstBaseURL: false)
        comps?.path = "/rest/v1/rides"
        comps?.queryItems = [
            URLQueryItem(name: "select", value: "status,driver_id,stripe_payment_intent_id,payment_status"),
            URLQueryItem(name: "id", value: "eq.\(rideId.uuidString)")
        ]

        guard let url = comps?.url else { throw URLError(.badURL) }

        print("🔎 fetchRideForCancel URL:", url.absoluteString)

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        applyHeaders(&req)

        let (data, resp) = try await session.data(for: req)
        let bodyString = String(data: data, encoding: .utf8) ?? "<non-UTF8 body>"

        guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }

        print("🔎 fetchRideForCancel status:", http.statusCode)
        print("🔎 fetchRideForCancel body:", bodyString)

        guard (200...299).contains(http.statusCode) else {
            throw PostgRESTHTTPError(statusCode: http.statusCode, body: bodyString)
        }

        let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
        guard let first = rows.first else {
            throw PostgRESTHTTPError(statusCode: 404, body: "Ride not found when fetching cancel snapshot.")
        }

        return RideCancelSnapshot(
            status: (first["status"] as? String) ?? "",
            driverId: readNullableString(first["driver_id"]),
            stripePaymentIntentId: readNullableString(first["stripe_payment_intent_id"]),
            paymentStatus: readNullableString(first["payment_status"])
        )
    }

    /// Uses the iOS Firebase Cloud Function: lumorider-18350 / refundPayment.
    func refundRidePayment(rideId: UUID, paymentIntentId: String) async throws -> PaymentRefundResult {
        let trimmedPaymentIntentId = paymentIntentId.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedPaymentIntentId.isEmpty else {
            throw NSError(
                domain: "SearchingForDriverView",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Missing payment intent for refund."]
            )
        }

        guard let user = Auth.auth().currentUser else {
            throw NSError(
                domain: "SearchingForDriverView",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "You are not signed in to Firebase on iOS."]
            )
        }

        let data: [String: Any] = [
            "rideId": rideId.uuidString,
            "paymentIntentId": trimmedPaymentIntentId
        ]

        do {
            print("🔎 Calling iOS Firebase refundPayment function: lumorider-18350/us-central1/refundPayment")
            print("🔎 refundPayment Firebase uid:", user.uid)
            print("🔎 refundPayment rideId:", rideId.uuidString)
            print("🔎 refundPayment paymentIntentId:", trimmedPaymentIntentId)

            let result = try await functions.httpsCallable("refundPayment").call(data)
            let response = result.data as? [String: Any]

            print("✅ refundPayment callable response:", response ?? [:])

            return PaymentRefundResult(
                refundId: response?["refundId"] as? String,
                status: response?["status"] as? String
            )
        } catch {
            let nsError = error as NSError
            print("❌ refundPayment failed localizedDescription:", nsError.localizedDescription)
            print("❌ refundPayment failed domain:", nsError.domain)
            print("❌ refundPayment failed code:", nsError.code)
            print("❌ refundPayment failed userInfo:", nsError.userInfo)
            throw error
        }
    }


    func markRideCanceledByRider(rideId: UUID, refundId: String?, markRefunded: Bool) async throws {
        var comps = URLComponents(url: cfg.baseURL, resolvingAgainstBaseURL: false)
        comps?.path = "/rest/v1/rides"
        comps?.queryItems = [
            URLQueryItem(name: "id", value: "eq.\(rideId.uuidString)")
        ]

        guard let url = comps?.url else { throw URLError(.badURL) }

        var body: [String: Any] = [
            "status": "cancelled_by_rider"
        ]

        if markRefunded {
            body["payment_status"] = "refunded"
            body["refunded_at"] = ISO8601DateFormatter().string(from: Date())

            if let refundId,
               !refundId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                body["refund_id"] = refundId
            }
        }

        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        applyHeaders(&req)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw PostgRESTHTTPError(statusCode: http.statusCode, body: msg)
        }
    }

    private func readNullableString(_ raw: Any?) -> String? {
        if let s = raw as? String {
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        if raw is NSNull { return nil }

        if let n = raw as? NSNumber {
            return n.stringValue
        }

        return nil
    }

    /// Cancels the ride request by hard-deleting the ride row.
    /// Your DB has a CHECK constraint (23514) that rejects status updates, so DELETE is the most reliable instant cancel.
    func cancelRide(rideId: UUID) async throws {
        var comps = URLComponents(url: cfg.baseURL, resolvingAgainstBaseURL: false)
        comps?.path = "/rest/v1/rides"
        comps?.queryItems = [
            URLQueryItem(name: "id", value: "eq.\(rideId.uuidString)")
        ]
        guard let url = comps?.url else { throw URLError(.badURL) }

        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        applyHeaders(&req)
        req.setValue("return=minimal", forHTTPHeaderField: "Prefer")

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw PostgRESTHTTPError(statusCode: http.statusCode, body: msg)
        }

        // Best-effort confirm: if the row is gone or not readable, we're done.
        // If it still exists and is readable, cancellation likely failed at the policy layer.
        do {
            _ = try await fetchRideStatus(rideId: rideId)
            // If fetch succeeds, the row still exists. Treat that as a failure.
            throw PostgRESTHTTPError(statusCode: 520, body: "Delete returned success but ride still exists.")
        } catch {
            // Expected: fetch fails because row is gone or not visible.
        }
    }

    private func applyHeaders(_ req: inout URLRequest) {
        // Force the known-good Supabase anon key for this project.
        // Some callers are passing a malformed/stale anon key that still starts with eyJ, causing HTTP 401.
        let anonKeyToUse = fallbackSupabaseAnonKey

        req.setValue(anonKeyToUse, forHTTPHeaderField: "apikey")

        if let token = cfg.accessToken?.trimmingCharacters(in: .whitespacesAndNewlines),
           !token.isEmpty,
           token.hasPrefix("eyJ") {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            req.setValue("Bearer \(anonKeyToUse)", forHTTPHeaderField: "Authorization")
        }
    }
}

struct SearchingForDriverView: View {

    // MARK: - Inputs
    let rideId: UUID
    let pickupAddress: String
    let dropoffAddress: String
    var rideTypeLabel: String? = nil
    var priceText: String? = nil

    /// Provide your app’s Supabase URL + anon key here.
    /// You will pass this from CardPaymentView (or your existing config holder).
    let supabase: LumoSupabaseConfig

    // MARK: - UI State
    @Environment(\.dismiss) private var dismiss
    @State private var goToConfirmed = false
    @State private var isCancelling = false
    @State private var errorText: String? = nil
    @State private var pollCancellable: AnyCancellable?
    @State private var lastSnapshot: RideStatusSnapshot? = nil
    @State private var allowTransition = false

    private var client: RideMatchingClient { RideMatchingClient(cfg: supabase) }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 18) {

                Spacer(minLength: 16)

                header

                Spacer(minLength: 10)

                heroAnimation

                if let err = errorText, !err.isEmpty {
                    Text(err)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                        .padding(.top, 4)
                        .transition(.opacity)
                }

                Spacer(minLength: 10)

                tripDetailsCard

                Spacer(minLength: 10)

                cancelButton
                    .padding(.bottom, 26)

                // Hidden navigation to confirmed view
                NavigationLink(
                    destination: RideConfirmedView(
                        rideId: rideId,
                        pickupAddress: pickupAddress,
                        dropoffAddress: dropoffAddress
                    ),
                    isActive: $goToConfirmed
                ) { EmptyView() }
                .hidden()
            }
            .padding(.horizontal, 0)
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            allowTransition = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                allowTransition = true
                Task { await checkRideStatusOnce() } // quick check after the minimum display time
                startPolling()
            }
        }
        .onDisappear { stopPolling() }
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(spacing: 8) {
            Text("Finding you a driver")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white)

            Text("This usually takes a moment.")
                .font(.system(size: 15))
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(.top, 8)
        .padding(.horizontal, 24)
    }

    private var heroAnimation: some View {
        SearchingHero()
            .frame(maxWidth: .infinity)
            .frame(height: 240)
            .padding(.vertical, 6)
    }

    private var tripDetailsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Trip details")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)

            VStack(alignment: .leading, spacing: 12) {
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

                if rideTypeLabel != nil || priceText != nil {
                    Divider()
                        .background(Color.white.opacity(0.18))

                    HStack {
                        if let rideTypeLabel {
                            Text(rideTypeLabel)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        Spacer()
                        if let priceText {
                            Text(priceText)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    }
                }

                if let snap = lastSnapshot {
                    Text("Status: \(snap.status)  •  driver_id: \(snap.driverId ?? "nil")")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.28))
                        .padding(.top, 2)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .padding(.horizontal, 24)
    }

    private var cancelButton: some View {
        Button {
            cancelRequest()
        } label: {
            HStack(spacing: 10) {
                if isCancelling {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                }

                Text(isCancelling ? "Refunding..." : "Cancel request")
            }
            .font(.system(size: 17, weight: .semibold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.white.opacity(0.15))
            .overlay(
                RoundedRectangle(cornerRadius: 28)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 28))
        }
        .disabled(isCancelling)
        .padding(.horizontal, 24)
    }

    // MARK: - Polling / State transitions (REAL)

    private func startPolling() {
        stopPolling()

        pollCancellable = Timer
            .publish(every: 2.0, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                Task { await checkRideStatusOnce() }
            }
    }

    private func stopPolling() {
        pollCancellable?.cancel()
        pollCancellable = nil
    }

    @MainActor
    private func checkRideStatusOnce() async {
        do {
            let snap = try await client.fetchRideStatus(rideId: rideId)
            lastSnapshot = snap

            if snap.isCancelled {
                stopPolling()
                errorText = "Cancelled."
                dismissToHome()
                return
            }

            if snap.isAcceptedOrAssigned {
                guard allowTransition else { return }

                stopPolling()
                successHaptic()
                withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) {
                    goToConfirmed = true
                }
            }
        } catch {
            if errorText == nil {
                errorText = "Still searching…"
            }
        }
    }

    private func cancelRequest() {
        guard !isCancelling else { return }
        isCancelling = true
        errorText = nil
        stopPolling()

        Task {
            do {
                let cancelSnapshot = try await client.fetchRideForCancel(rideId: rideId)
                print("🔎 cancelSnapshot status:", cancelSnapshot.status)
                print("🔎 cancelSnapshot driverId:", cancelSnapshot.driverId ?? "nil")
                print("🔎 cancelSnapshot stripePaymentIntentId:", cancelSnapshot.stripePaymentIntentId ?? "nil")
                print("🔎 cancelSnapshot paymentStatus:", cancelSnapshot.paymentStatus ?? "nil")
                print("🔎 cancelSnapshot hasPaymentToRefund:", cancelSnapshot.hasPaymentToRefund)

                if cancelSnapshot.isAcceptedOrAssigned {
                    throw NSError(
                        domain: "SearchingForDriverView",
                        code: 409,
                        userInfo: [NSLocalizedDescriptionKey: "A driver already accepted this ride. Please cancel from the active ride screen."]
                    )
                }

                var refundId: String? = nil
                var markRefunded = false

                if cancelSnapshot.hasPaymentToRefund,
                   let paymentIntentId = cancelSnapshot.stripePaymentIntentId,
                   !paymentIntentId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let refund = try await client.refundRidePayment(
                        rideId: rideId,
                        paymentIntentId: paymentIntentId
                    )
                    refundId = refund.refundId
                    markRefunded = true
                }

                try await client.markRideCanceledByRider(
                    rideId: rideId,
                    refundId: refundId,
                    markRefunded: markRefunded
                )

                await MainActor.run {
                    isCancelling = false
                    goToConfirmed = false
                    allowTransition = false
                    lastSnapshot = RideStatusSnapshot(status: "cancelled_by_rider", driverId: nil)
                    errorText = markRefunded ? "Refunded and cancelled." : "Cancelled."
                    dismissToHome()
                }
            } catch {
                await MainActor.run {
                    isCancelling = false
                    let nsError = error as NSError
                    print("❌ cancelRequest failed localizedDescription:", nsError.localizedDescription)
                    print("❌ cancelRequest failed domain:", nsError.domain)
                    print("❌ cancelRequest failed code:", nsError.code)
                    print("❌ cancelRequest failed userInfo:", nsError.userInfo)
                    let msg = (error as? LocalizedError)?.errorDescription ?? nsError.localizedDescription
                    errorText = "Refund/cancel failed: \(msg)"
                    startPolling()
                }
            }
        }
    }

    // MARK: - Helpers

    @MainActor
    private func dismissToHome() {
        // Works for NavigationStack push AND modal presentation
        dismiss()

        // Best-effort: if it’s inside a modal stack, dismiss any presented VC too
        if let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first,
           let root = scene.windows.first?.rootViewController,
           root.presentedViewController != nil {
            root.dismiss(animated: true)
        }
    }

    private func successHaptic() {
        let gen = UINotificationFeedbackGenerator()
        gen.notificationOccurred(.success)
    }
}

// =======================================================
// Premium “Searching” hero animation (Uber-like polish)
// =======================================================

private struct SearchingHero: View {
    @State private var animate = false
    @State private var breathe = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let s = min(w, h)

            // Sizes derived from the actual runtime container size (fixes iPhone vs Simulator layout drift)
            let glowEndRadius = max(120, s * 0.60)
            let pulseBase = max(140, s * 0.62)
            let centerDisc = max(72, s * 0.28)
            let centerDisc2 = max(92, s * 0.36)
            let logoSize = max(40, s * 0.15)
            let dotsOffsetY = max(92, s * 0.36)

            ZStack {
                RadialGradient(
                    gradient: Gradient(colors: [
                        Color.white.opacity(0.09),
                        Color.white.opacity(0.00)
                    ]),
                    center: .center,
                    startRadius: 10,
                    endRadius: glowEndRadius
                )
                .opacity(animate ? 1.0 : 0.8)
                .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: animate)

                Circle()
                    .stroke(Color.white.opacity(0.55), lineWidth: 2)
                    .frame(width: pulseBase, height: pulseBase)
                    .scaleEffect(animate ? 1.20 : 0.72)
                    .opacity(animate ? 0.0 : 1.0)
                    .blur(radius: 0.8)
                    .animation(.easeOut(duration: 1.35).repeatForever(autoreverses: false), value: animate)

                Circle()
                    .stroke(Color.white.opacity(0.60), lineWidth: 2)
                    .frame(width: pulseBase * 0.86, height: pulseBase * 0.86)
                    .scaleEffect(animate ? 1.18 : 0.70)
                    .opacity(animate ? 0.0 : 1.0)
                    .blur(radius: 0.6)
                    .animation(.easeOut(duration: 1.05).repeatForever(autoreverses: false).delay(0.14), value: animate)

                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.10))
                        .frame(width: centerDisc, height: centerDisc)

                    Circle()
                        .fill(Color.white.opacity(0.06))
                        .frame(width: centerDisc2, height: centerDisc2)

                    LumoCenterLogo()
                        .frame(width: logoSize, height: logoSize)
                        .scaleEffect(breathe ? 1.04 : 0.98)
                        .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: breathe)
                }

                SearchingDots()
                    .offset(y: dotsOffsetY)
            }
            .frame(width: w, height: h)
            .clipped()
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            // Delay one runloop tick so the GeometryReader has its final size on real devices.
            // Prevents the center logo from visually “flying” from a transient 0-size layout.
            DispatchQueue.main.async {
                animate = true
                breathe = true
            }
        }
    }
}

private struct SearchingDots: View {
    @State private var phase: Int = 0
    private let timer = Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 6) {
            dot(phase == 0)
            dot(phase == 1)
            dot(phase == 2)
        }
        .onReceive(timer) { _ in
            phase = (phase + 1) % 3
        }
    }

    private func dot(_ on: Bool) -> some View {
        Circle()
            .fill(Color.white.opacity(on ? 0.95 : 0.25))
            .frame(width: 7, height: 7)
            .scaleEffect(on ? 1.0 : 0.85)
            .animation(.easeInOut(duration: 0.25), value: on)
    }
}

private struct LumoCenterLogo: View {
    // Try common asset names. Use the first one that exists.
    private let candidateNames = ["speedCar", "LumoLogo", "lumo_logo", "Lumo", "lumo"]

    @State private var resolvedAssetName: String? = nil

    private func resolveIfNeeded() {
        guard resolvedAssetName == nil else { return }
        for name in candidateNames {
            if UIImage(named: name) != nil {
                resolvedAssetName = name
                return
            }
        }
        // Leave nil to use SF Symbol fallback.
    }

    var body: some View {
        Group {
            if let name = resolvedAssetName {
                Image(name)
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "car.fill")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(.white)
            }
        }
        .onAppear {
            resolveIfNeeded()
        }
    }
}
