import SwiftUI
import MapKit
import CoreLocation
import Stripe
import UIKit

struct DeliveryRequestView: View {
    var body: some View { DeliveryRootView() }
}

struct DeliveryRootView: View {
    @StateObject private var store = FoodDeliveryStore()
    @StateObject private var locationManager = LumoLocationManager()
    @State private var activeOrder: FoodOrder?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if store.isLoading && store.markets.isEmpty {
                    ProgressView().tint(.white)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 18) {
                            header
                            if let activeOrder { activeOrderCard(activeOrder) }
                            restaurantList
                        }
                        .padding(.horizontal, 18)
                        .padding(.bottom, store.cart.isEmpty ? 24 : 100)
                    }
                }
            }
            .navigationTitle("Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(destination: FoodOrderHistoryView()) {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundStyle(.white)
                    }
                    .accessibilityLabel("Food orders")
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !store.cart.isEmpty {
                    NavigationLink(destination: FoodCartView().environmentObject(store)) {
                        HStack {
                            Text("\(store.totalQuantity) item\(store.totalQuantity == 1 ? "" : "s")")
                            Spacer()
                            Text("View cart")
                            Text(FoodLocale.amount(store.subtotalMinor, currency: store.cartRestaurant?.currency ?? "USD"))
                        }
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 18)
                        .frame(height: 58)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                    }
                    .buttonStyle(.plain)
                }
            }
            .environmentObject(store)
            .task {
                await store.loadCatalog(coordinate: locationManager.coordinate)
                activeOrder = try? await FoodDeliveryService.shared.activeOrder()
            }
            .alert("Food delivery", isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } }
            )) { Button("OK", role: .cancel) {} } message: {
                Text(store.errorMessage ?? "")
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Restaurants near you")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.55))
                TextField("Search restaurants or cuisine", text: $store.searchText)
                    .foregroundStyle(.white)
                    .textInputAutocapitalization(.never)
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 15))

            if store.markets.count > 1 {
                Menu {
                    ForEach(store.markets) { market in
                        Button("\(market.city), \(market.countryCode)") { store.selectMarket(market) }
                    }
                } label: {
                    Label(store.selectedMarket.map { "\($0.city), \($0.countryCode)" } ?? "Choose market",
                          systemImage: "location.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
        }
        .padding(.top, 10)
    }

    @ViewBuilder
    private var restaurantList: some View {
        if store.visibleRestaurants.isEmpty {
            ContentUnavailableView("No restaurants available", systemImage: "fork.knife",
                                   description: Text("Try another supported market."))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.top, 50)
        } else {
            ForEach(store.visibleRestaurants) { restaurant in
                NavigationLink(destination: FoodRestaurantView(restaurant: restaurant).environmentObject(store)) {
                    FoodRestaurantCard(restaurant: restaurant, isOpen: store.isOpen(restaurant))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func activeOrderCard(_ order: FoodOrder) -> some View {
        NavigationLink(destination: FoodOrderTrackingView(orderId: order.id, onStatusChanged: { updated in
            activeOrder = updated.orderStatus == "cancelled" ? nil : updated
        })) {
            HStack(spacing: 14) {
                Image(systemName: "takeoutbag.and.cup.and.straw.fill")
                    .font(.system(size: 22)).foregroundStyle(.black)
                    .frame(width: 44, height: 44).background(.white).clipShape(Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text("Active order").font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.6))
                    Text(FoodLocale.status(order.orderStatus)).font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                    Text(order.restaurantName).font(.system(size: 13)).foregroundStyle(.white.opacity(0.65))
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.white.opacity(0.45))
            }
            .padding(16)
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }
}

private struct FoodRestaurantCard: View {
    let restaurant: FoodRestaurant
    let isOpen: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(restaurant.displayName).font(.system(size: 19, weight: .bold)).foregroundStyle(.white)
                    Text(restaurant.displayCuisine).font(.system(size: 14)).foregroundStyle(.white.opacity(0.62))
                }
                Spacer()
                Text(isOpen ? "Open" : "Closed")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(isOpen ? .white : .white.opacity(0.45))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.white.opacity(isOpen ? 0.13 : 0.06)).clipShape(Capsule())
            }
            HStack(spacing: 14) {
                Label("\(restaurant.estimatedDeliveryMinutes) min", systemImage: "clock")
                Label(FoodLocale.amount(restaurant.deliveryFeeMinor, currency: restaurant.currency), systemImage: "bicycle")
                if restaurant.rating > 0 { Label(String(format: "%.1f", restaurant.rating), systemImage: "star.fill") }
            }
            .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.72))
        }
        .padding(17)
        .background(Color.white.opacity(0.065))
        .overlay(RoundedRectangle(cornerRadius: 19).stroke(Color.white.opacity(0.08)))
        .clipShape(RoundedRectangle(cornerRadius: 19))
    }
}

struct FoodRestaurantView: View {
    @EnvironmentObject private var store: FoodDeliveryStore
    let restaurant: FoodRestaurant

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 9) {
                        Text(restaurant.displayName).font(.system(size: 30, weight: .bold)).foregroundStyle(.white)
                        Text(restaurant.displayDescription).font(.system(size: 14)).foregroundStyle(.white.opacity(0.65))
                        HStack(spacing: 15) {
                            Label("\(restaurant.estimatedDeliveryMinutes) min", systemImage: "clock")
                            Label(FoodLocale.amount(restaurant.deliveryFeeMinor, currency: restaurant.currency), systemImage: "bicycle")
                        }.font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
                        if !store.isOpen(restaurant) {
                            Text("Currently closed").font(.system(size: 13, weight: .bold)).foregroundStyle(.white.opacity(0.5))
                        }
                    }
                    ForEach(store.categories(for: restaurant)) { category in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(category.displayName).font(.system(size: 21, weight: .bold)).foregroundStyle(.white)
                            ForEach(store.items(for: category)) { item in
                                HStack(alignment: .top, spacing: 14) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(item.displayName).font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                                        if !item.displayDescription.isEmpty {
                                            Text(item.displayDescription).font(.system(size: 13)).foregroundStyle(.white.opacity(0.58)).lineLimit(3)
                                        }
                                        Text(FoodLocale.amount(item.priceMinor, currency: item.currency))
                                            .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
                                    }
                                    Spacer()
                                    Button { store.add(item, restaurant: restaurant) } label: {
                                        Image(systemName: "plus").font(.system(size: 15, weight: .bold)).foregroundStyle(.black)
                                            .frame(width: 36, height: 36).background(.white).clipShape(Circle())
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(!store.isOpen(restaurant))
                                }
                                .padding(15).background(Color.white.opacity(0.055)).clipShape(RoundedRectangle(cornerRadius: 17))
                            }
                        }
                    }
                }
                .padding(18).padding(.bottom, store.cart.isEmpty ? 12 : 80)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            if !store.cart.isEmpty && store.cartRestaurant?.id == restaurant.id {
                NavigationLink(destination: FoodCartView().environmentObject(store)) {
                    HStack { Text("View cart"); Spacer(); Text(FoodLocale.amount(store.subtotalMinor, currency: restaurant.currency)) }
                        .font(.system(size: 16, weight: .bold)).foregroundStyle(.black)
                        .padding(.horizontal, 18).frame(height: 56).background(.white).clipShape(RoundedRectangle(cornerRadius: 17))
                        .padding(.horizontal, 16).padding(.bottom, 6)
                }.buttonStyle(.plain)
            }
        }
    }
}

struct FoodCartView: View {
    @EnvironmentObject private var store: FoodDeliveryStore

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 14) {
                    ForEach(store.cart) { line in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(line.item.displayName).font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                                    Text(FoodLocale.amount(line.lineTotalMinor, currency: line.item.currency))
                                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.65))
                                }
                                Spacer()
                                HStack(spacing: 14) {
                                    Button { store.changeQuantity(itemId: line.id, by: -1) } label: { Image(systemName: "minus") }
                                    Text("\(line.quantity)").fontWeight(.bold)
                                    Button { store.changeQuantity(itemId: line.id, by: 1) } label: { Image(systemName: "plus") }
                                }
                                .foregroundStyle(.black).padding(.horizontal, 12).frame(height: 36).background(.white).clipShape(Capsule())
                            }
                            TextField("Item notes (optional)", text: Binding(
                                get: { store.cart.first(where: { $0.id == line.id })?.customerNotes ?? "" },
                                set: { store.updateNotes(itemId: line.id, notes: $0) }
                            ))
                            .foregroundStyle(.white).padding(.horizontal, 12).frame(height: 42)
                            .background(Color.white.opacity(0.07)).clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .padding(15).background(Color.white.opacity(0.055)).clipShape(RoundedRectangle(cornerRadius: 17))
                    }
                    FoodPriceBreakdown(store: store)
                }
                .padding(18).padding(.bottom, 90)
            }
        }
        .navigationTitle("Cart")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            if !store.cart.isEmpty {
                NavigationLink(destination: FoodCheckoutView().environmentObject(store)) {
                    HStack { Text("Checkout"); Spacer(); Text(FoodLocale.amount(store.totalMinor, currency: store.cartRestaurant?.currency ?? "USD")) }
                        .font(.system(size: 16, weight: .bold)).foregroundStyle(.black)
                        .padding(.horizontal, 18).frame(height: 56).background(.white).clipShape(RoundedRectangle(cornerRadius: 17))
                        .padding(.horizontal, 16).padding(.bottom, 6)
                }.buttonStyle(.plain)
            }
        }
    }
}

private struct FoodPriceBreakdown: View {
    @ObservedObject var store: FoodDeliveryStore
    private var currency: String { store.cartRestaurant?.currency ?? "USD" }
    var body: some View {
        VStack(spacing: 11) {
            row("Subtotal", store.subtotalMinor)
            row("Delivery fee", store.deliveryFeeMinor)
            row("Service fee", store.serviceFeeMinor)
            if store.taxMinor > 0 { row("Tax", store.taxMinor) }
            Divider().overlay(Color.white.opacity(0.18))
            HStack { Text("Total"); Spacer(); Text(FoodLocale.amount(store.totalMinor, currency: currency)) }
                .font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
        }
        .padding(16).background(Color.white.opacity(0.055)).clipShape(RoundedRectangle(cornerRadius: 17))
    }
    private func row(_ title: String, _ amount: Int64) -> some View {
        HStack { Text(title); Spacer(); Text(FoodLocale.amount(amount, currency: currency)) }
            .font(.system(size: 14, weight: .medium)).foregroundStyle(.white.opacity(0.72))
    }
}

private enum FoodPaymentChoice: String { case cash, card }

struct FoodCheckoutView: View {
    @EnvironmentObject private var store: FoodDeliveryStore
    @State private var showAddressPicker = false
    @State private var payment: FoodPaymentChoice = .cash
    @State private var cardParams: STPPaymentMethodParams?
    @State private var cardIsValid = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var placedOrder: FoodOrder?
    @State private var orderAttemptId = UserDefaults.standard.string(forKey: "lumo.food.order.attempt.id")
        ?? UUID().uuidString.lowercased()
    @State private var orderAttemptSignature = UserDefaults.standard.string(forKey: "lumo.food.order.attempt.signature")

    private var restaurant: FoodRestaurant? { store.cartRestaurant }
    private var minimumReached: Bool { store.subtotalMinor >= (restaurant?.minimumOrderAmountMinor ?? 0) }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    Button { showAddressPicker = true } label: {
                        HStack(spacing: 13) {
                            Image(systemName: "mappin.and.ellipse").foregroundStyle(.black)
                                .frame(width: 40, height: 40).background(.white).clipShape(Circle())
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Delivery address").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.55))
                                Text(store.address.formattedAddress.isEmpty ? "Choose address" : store.address.formattedAddress)
                                    .font(.system(size: 15, weight: .bold)).foregroundStyle(.white).multilineTextAlignment(.leading)
                            }
                            Spacer(); Image(systemName: "chevron.right").foregroundStyle(.white.opacity(0.45))
                        }
                        .padding(15).background(Color.white.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 17))
                    }.buttonStyle(.plain)

                    contactFields
                    paymentSection
                    FoodPriceBreakdown(store: store)
                    if !minimumReached, let restaurant {
                        Text("Minimum order: \(FoodLocale.amount(restaurant.minimumOrderAmountMinor, currency: restaurant.currency))")
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.62))
                    }
                }
                .padding(18).padding(.bottom, 90)
            }
        }
        .navigationTitle("Checkout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            Button { Task { await placeOrder() } } label: {
                HStack {
                    if isSubmitting { ProgressView().tint(.black) } else { Text("Place order") }
                    Spacer(); Text(FoodLocale.amount(store.totalMinor, currency: restaurant?.currency ?? "USD"))
                }
                .font(.system(size: 16, weight: .bold)).foregroundStyle(.black)
                .padding(.horizontal, 18).frame(height: 56).background(.white).clipShape(RoundedRectangle(cornerRadius: 17))
                .padding(.horizontal, 16).padding(.bottom, 6)
            }
            .buttonStyle(.plain)
            .disabled(isSubmitting || !store.address.isValid || !minimumReached || (payment == .card && !cardIsValid))
            .opacity((!store.address.isValid || !minimumReached || (payment == .card && !cardIsValid)) ? 0.45 : 1)
        }
        .sheet(isPresented: $showAddressPicker) { FoodAddressPicker(address: $store.address) }
        .navigationDestination(item: $placedOrder) { order in
            FoodOrderTrackingView(orderId: order.id)
        }
        .alert("Unable to place order", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
        .onAppear {
            if restaurant?.cashEnabled != true && restaurant?.onlinePaymentEnabled == true { payment = .card }
        }
    }

    private var contactFields: some View {
        VStack(spacing: 11) {
            checkoutField("Recipient name", text: $store.address.recipientName)
            checkoutField("Phone number", text: $store.address.recipientPhone, keyboard: .phonePad)
            checkoutField("Building (optional)", text: $store.address.building)
            HStack { checkoutField("Floor", text: $store.address.floor); checkoutField("Apartment", text: $store.address.apartment) }
            checkoutField("Delivery instructions (optional)", text: $store.address.instructions)
        }
        .padding(15).background(Color.white.opacity(0.055)).clipShape(RoundedRectangle(cornerRadius: 17))
    }

    @ViewBuilder
    private var paymentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Payment").font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
            if restaurant?.cashEnabled == true { paymentButton(.cash, title: "Cash", icon: "banknote") }
            if restaurant?.onlinePaymentEnabled == true && restaurant?.currency == "USD" {
                paymentButton(.card, title: "Card", icon: "creditcard")
                if payment == .card {
                    StripeCardField(cardParams: $cardParams, isValid: $cardIsValid)
                        .frame(height: 46).padding(.horizontal, 12)
                        .background(Color.white.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding(15).background(Color.white.opacity(0.055)).clipShape(RoundedRectangle(cornerRadius: 17))
    }

    private func paymentButton(_ choice: FoodPaymentChoice, title: String, icon: String) -> some View {
        Button { payment = choice } label: {
            HStack { Image(systemName: icon); Text(title); Spacer(); Image(systemName: payment == choice ? "checkmark.circle.fill" : "circle") }
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
        }.buttonStyle(.plain)
    }

    private func checkoutField(_ title: String, text: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
        TextField(title, text: text)
            .keyboardType(keyboard).foregroundStyle(.white).padding(.horizontal, 12).frame(height: 44)
            .background(Color.white.opacity(0.07)).clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @MainActor
    private func placeOrder() async {
        guard !isSubmitting else { return }
        guard let restaurant, let market = store.markets.first(where: { $0.id == restaurant.marketId }),
              store.address.isValid, minimumReached, !store.cart.isEmpty else { return }
        let signature = submissionSignature(marketId: market.id, restaurantId: restaurant.id)
        if orderAttemptSignature != signature {
            orderAttemptId = UUID().uuidString.lowercased()
            orderAttemptSignature = signature
            UserDefaults.standard.set(orderAttemptId, forKey: "lumo.food.order.attempt.id")
            UserDefaults.standard.set(signature, forKey: "lumo.food.order.attempt.signature")
        }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let order: FoodOrder
            switch payment {
            case .cash:
                order = try await FoodDeliveryService.shared.createCashOrder(
                    requestId: orderAttemptId, marketId: market.id, restaurantId: restaurant.id,
                    address: store.address, lines: store.cart
                )
            case .card:
                guard let cardParams else { throw FoodDeliveryError.message("Enter a valid card.") }
                let prepared = try await FoodDeliveryService.shared.prepareCardPayment(
                    checkoutId: orderAttemptId, marketId: market.id, restaurantId: restaurant.id,
                    address: store.address, lines: store.cart
                )
                try await confirmCard(clientSecret: prepared.clientSecret, params: cardParams)
                order = try await FoodDeliveryService.shared.finalizeCardPayment(
                    checkoutId: prepared.checkoutId, paymentIntentId: prepared.paymentIntentId
                )
            }
            UserDefaults.standard.removeObject(forKey: "lumo.food.order.attempt.id")
            UserDefaults.standard.removeObject(forKey: "lumo.food.order.attempt.signature")
            store.orderPlaced()
            placedOrder = order
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func submissionSignature(marketId: String, restaurantId: String) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let address = (try? encoder.encode(store.address).base64EncodedString()) ?? ""
        let cart = (try? encoder.encode(store.cart).base64EncodedString()) ?? ""
        return [marketId, restaurantId, payment.rawValue, address, cart].joined(separator: "|")
    }

    @MainActor
    private func confirmCard(clientSecret: String, params: STPPaymentMethodParams) async throws {
        guard let root = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows }).first(where: { $0.isKeyWindow })?.rootViewController else {
            throw FoodDeliveryError.message("Unable to present secure card confirmation.")
        }
        let intent = STPPaymentIntentParams(clientSecret: clientSecret)
        intent.paymentMethodParams = params
        let context = PaymentAuthContext(presenting: root)
        try await withCheckedThrowingContinuation { continuation in
            STPPaymentHandler.shared().confirmPayment(intent, with: context) { status, _, error in
                switch status {
                case .succeeded: continuation.resume()
                case .canceled: continuation.resume(throwing: FoodDeliveryError.message("Payment was cancelled."))
                case .failed: continuation.resume(throwing: error ?? FoodDeliveryError.message("Card payment failed."))
                @unknown default: continuation.resume(throwing: FoodDeliveryError.message("Card payment could not be confirmed."))
                }
            }
        }
    }
}

struct FoodAddressPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var address: FoodDeliveryAddress
    @StateObject private var completer = AddressSearchCompleter()
    @StateObject private var locator = DestinationPickupLocator()
    @State private var query = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.55))
                        TextField("Search delivery address", text: $query)
                            .foregroundStyle(.white).onChange(of: query) { _, value in completer.update(query: value) }
                    }
                    .padding(.horizontal, 14).frame(height: 48).background(Color.white.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 15))
                    Button { useCurrentLocation() } label: {
                        Label("Use my current location", systemImage: "location.fill")
                            .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.plain).padding(.vertical, 8)
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(completer.results.enumerated()), id: \.offset) { _, result in
                                Button { resolve(result) } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(result.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                                        Text(result.subtitle).font(.system(size: 13)).foregroundStyle(.white.opacity(0.55))
                                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 13)
                                }.buttonStyle(.plain)
                                Divider().overlay(Color.white.opacity(0.1))
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }.padding(18)
            }
            .navigationTitle("Delivery address").navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() }.foregroundStyle(.white) } }
            .onAppear { locator.start() }
            .alert("Address", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
        }
    }

    private func resolve(_ completion: MKLocalSearchCompletion) {
        MKLocalSearch(request: .init(completion: completion)).start { response, error in
            guard error == nil, let mapItem = response?.mapItems.first else {
                errorMessage = "Could not resolve that address."; return
            }
            address.formattedAddress = mapItem.placemark.title ?? completion.title
            address.latitude = mapItem.placemark.coordinate.latitude
            address.longitude = mapItem.placemark.coordinate.longitude
            address.district = mapItem.placemark.subLocality ?? mapItem.placemark.locality ?? ""
            dismiss()
        }
    }

    private func useCurrentLocation() {
        guard let coordinate = locator.coordinate else { errorMessage = "Current location is not available yet."; return }
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        CLGeocoder().reverseGeocodeLocation(location) { placemarks, _ in
            let placemark = placemarks?.first
            address.formattedAddress = placemark.map { [$0.name, $0.locality, $0.administrativeArea].compactMap { $0 }.joined(separator: ", ") }
                ?? "Current location"
            address.latitude = coordinate.latitude
            address.longitude = coordinate.longitude
            address.district = placemark?.subLocality ?? placemark?.locality ?? ""
            dismiss()
        }
    }
}

struct FoodOrderTrackingView: View {
    @Environment(\.dismiss) private var dismiss
    let orderId: String
    var onStatusChanged: ((FoodOrder) -> Void)? = nil
    @State private var tracking: FoodOrderTracking?
    @State private var errorMessage: String?
    @State private var isCancelling = false
    @State private var isLoading = true
    @State private var cancellationConfirmed = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let tracking {
                ScrollView {
                    VStack(alignment: .leading, spacing: 17) {
                        trackingMap(tracking)
                        Text(FoodLocale.status(tracking.order.orderStatus))
                            .font(.system(size: 28, weight: .bold)).foregroundStyle(.white)
                        Text(tracking.order.restaurantName).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white.opacity(0.68))
                        if let assignment = tracking.deliveryAssignment, let driver = assignment.driver {
                            driverCard(driver)
                        }
                        orderCard(tracking)
                        if tracking.order.orderStatus == "placed" && !cancellationConfirmed {
                            Button(role: .destructive) { Task { await cancel() } } label: {
                                Text(isCancelling ? "Cancelling…" : "Cancel order")
                                    .font(.system(size: 15, weight: .bold)).frame(maxWidth: .infinity).frame(height: 50)
                                    .background(Color.white.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 15))
                            }.disabled(isCancelling)
                        }
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 14))
                                .foregroundStyle(.red)
                                .accessibilityIdentifier("foodTrackingError")
                        }
                    }.padding(18)
                }
            } else if isLoading {
                ProgressView().tint(.white)
            } else {
                ContentUnavailableView("Order unavailable", systemImage: "exclamationmark.triangle",
                                       description: Text(errorMessage ?? "Could not load this order."))
                    .foregroundStyle(.white)
                    .overlay(alignment: .bottom) {
                        Button("Try again") { Task { await refreshTracking() } }
                            .padding(.bottom, 24)
                    }
            }
        }
        .navigationTitle("Order tracking").navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("Back")
            }
        }
        .task(id: orderId) {
            while !Task.isCancelled {
                await refreshTracking()
                if cancellationConfirmed || ["delivered", "cancelled", "rejected"].contains(tracking?.order.orderStatus ?? "") { break }
                try? await Task.sleep(for: .seconds(3))
            }
        }
        .alert("Order tracking", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    @ViewBuilder private func trackingMap(_ tracking: FoodOrderTracking) -> some View {
        let delivery = CLLocationCoordinate2D(latitude: tracking.order.deliveryLatitude, longitude: tracking.order.deliveryLongitude)
        Map(initialPosition: .region(.init(center: tracking.deliveryAssignment?.location.map {
            .init(latitude: $0.latitude, longitude: $0.longitude)
        } ?? delivery, span: .init(latitudeDelta: 0.025, longitudeDelta: 0.025)))) {
            Marker("Delivery", systemImage: "house.fill", coordinate: delivery).tint(.black)
            if let location = tracking.deliveryAssignment?.location {
                Marker("Driver", systemImage: "car.fill", coordinate: .init(latitude: location.latitude, longitude: location.longitude)).tint(.white)
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .frame(height: 230).clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func driverCard(_ driver: FoodDriverSummary) -> some View {
        HStack(spacing: 13) {
            Image(systemName: "person.fill").foregroundStyle(.black).frame(width: 42, height: 42).background(.white).clipShape(Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(driver.displayName ?? "Your driver").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                let vehicle = [driver.vehicleColor, driver.vehicleMake, driver.vehicleModel, driver.vehiclePlate].compactMap { $0 }.joined(separator: " · ")
                if !vehicle.isEmpty { Text(vehicle).font(.system(size: 13)).foregroundStyle(.white.opacity(0.6)) }
            }
        }.padding(15).frame(maxWidth: .infinity, alignment: .leading).background(Color.white.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 17))
    }

    private func orderCard(_ tracking: FoodOrderTracking) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Order").font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
            ForEach(tracking.items) { item in
                HStack { Text("\(item.quantity)× \(item.itemName)"); Spacer(); Text(FoodLocale.amount(item.lineTotalMinor, currency: tracking.order.currency)) }
                    .font(.system(size: 14)).foregroundStyle(.white.opacity(0.72))
            }
            Divider().overlay(Color.white.opacity(0.15))
            HStack { Text("Total"); Spacer(); Text(FoodLocale.amount(tracking.order.totalMinor, currency: tracking.order.currency)) }
                .font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
            Label(tracking.order.formattedAddress, systemImage: "mappin.and.ellipse")
                .font(.system(size: 13)).foregroundStyle(.white.opacity(0.62))
        }.padding(16).background(Color.white.opacity(0.055)).clipShape(RoundedRectangle(cornerRadius: 17))
    }

    @MainActor
    private func cancel() async {
        guard !isCancelling, let previous = tracking else { return }
        isCancelling = true
        errorMessage = nil
        defer { isCancelling = false }
        do {
            let order = try await FoodDeliveryService.shared.cancel(orderId: orderId)
            guard order.orderStatus == "cancelled" else {
                throw FoodDeliveryError.message("The server did not confirm cancellation.")
            }
            cancellationConfirmed = true
            tracking = FoodOrderTracking(order: order, items: previous.items,
                                         statusHistory: previous.statusHistory,
                                         deliveryAssignment: previous.deliveryAssignment)
            onStatusChanged?(order)
            await refreshTracking()
        } catch {
            let cancellationError = error.localizedDescription
            errorMessage = "Could not cancel order: \(cancellationError)"
            // The backend may have committed cancellation before a later step
            // failed. Read the authoritative status rather than leaving stale UI.
            Task {
                await refreshTracking()
                if cancellationConfirmed {
                    errorMessage = "Order canceled, but the server also reported: \(cancellationError). Check payment with support if you were charged."
                }
            }
        }
    }

    @MainActor
    private func refreshTracking() async {
        do {
            let latest = try await FoodDeliveryService.shared.tracking(orderId: orderId)
            if !cancellationConfirmed || latest.order.orderStatus == "cancelled" {
                tracking = latest
            }
            if latest.order.orderStatus == "cancelled" {
                cancellationConfirmed = true
                errorMessage = nil
                onStatusChanged?(latest.order)
            }
        } catch {
            if tracking == nil {
                errorMessage = "Could not load order: \(error.localizedDescription)"
            } else if cancellationConfirmed {
                errorMessage = "Order canceled, but the latest details could not load: \(error.localizedDescription)"
            }
        }
        isLoading = false
    }
}

struct FoodOrderHistoryView: View {
    @State private var orders: [FoodOrder] = []
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if orders.isEmpty {
                ContentUnavailableView("No food orders", systemImage: "takeoutbag.and.cup.and.straw")
                    .foregroundStyle(.white)
            } else {
                List(orders) { order in
                    NavigationLink(destination: FoodOrderTrackingView(orderId: order.id, onStatusChanged: { updated in
                        if let index = orders.firstIndex(where: { $0.id == updated.id }) {
                            orders[index] = updated
                        }
                    })) {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack { Text(order.restaurantName).fontWeight(.bold); Spacer(); Text(FoodLocale.amount(order.totalMinor, currency: order.currency)).fontWeight(.semibold) }
                            Text(FoodLocale.status(order.orderStatus)).font(.system(size: 13)).foregroundStyle(.secondary)
                            Text(order.formattedAddress).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                        }.padding(.vertical, 5)
                    }.listRowBackground(Color.white.opacity(0.06))
                }.scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Food orders").navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            do { orders = try await FoodDeliveryService.shared.orders() }
            catch { errorMessage = error.localizedDescription }
        }
        .alert("Order history", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }
}
