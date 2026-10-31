import Foundation
import FirebaseAuth
import CoreLocation
import Combine

enum FoodDeliveryError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        if case .message(let text) = self { return text }
        return "Food delivery request failed."
    }
}

final class FoodDeliveryService {
    static let shared = FoodDeliveryService()

    private let supabaseURL = URL(string: "https://rpryqbdodbieioebedjg.supabase.co")!
    private let foodURL = URL(string: "https://us-central1-lumorider-18350.cloudfunctions.net/food")!
    private let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJwcnlxYmRvZGJpZWlvZWJlZGpnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjUwNjE0MjYsImV4cCI6MjA4MDYzNzQyNn0.8ZTaA1bCyRUKb6U4NNZou6DMfXP3yyE1NeNL8Ljt9as"

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    private init() {}

    func loadCatalog() async throws -> (
        markets: [FoodMarket], restaurants: [FoodRestaurant],
        hours: [FoodRestaurantHour], categories: [FoodMenuCategory], items: [FoodMenuItem]
    ) {
        async let markets: [FoodMarket] = catalog("food_markets", query: [
            .init(name: "select", value: "*"), .init(name: "order", value: "city")
        ])
        async let restaurants: [FoodRestaurant] = catalog("food_restaurants", query: [
            .init(name: "select", value: "*"), .init(name: "order", value: "name_en")
        ])
        async let hours: [FoodRestaurantHour] = catalog("food_restaurant_hours", query: [
            .init(name: "select", value: "*"), .init(name: "order", value: "day_of_week")
        ])
        async let categories: [FoodMenuCategory] = catalog("food_menu_categories", query: [
            .init(name: "select", value: "*"), .init(name: "order", value: "display_order")
        ])
        async let items: [FoodMenuItem] = catalog("food_menu_items", query: [
            .init(name: "select", value: "*"), .init(name: "order", value: "display_order")
        ])
        return try await (markets, restaurants, hours, categories, items)
    }

    func createCashOrder(
        requestId: String, marketId: String, restaurantId: String,
        address: FoodDeliveryAddress, lines: [FoodCartLine]
    ) async throws -> FoodOrder {
        let response: OrderEnvelope = try await authenticated(
            path: "cash-order", method: "POST",
            body: orderBody(id: requestId, marketId: marketId, restaurantId: restaurantId,
                            address: address, lines: lines)
        )
        return response.order
    }

    func prepareCardPayment(
        checkoutId: String, marketId: String, restaurantId: String,
        address: FoodDeliveryAddress, lines: [FoodCartLine]
    ) async throws -> FoodPaymentPreparation {
        let response: PaymentEnvelope = try await authenticated(
            path: "payment-intent", method: "POST",
            body: orderBody(id: checkoutId, marketId: marketId, restaurantId: restaurantId,
                            address: address, lines: lines, idKey: "checkout_id")
        )
        return FoodPaymentPreparation(
            checkoutId: response.checkoutId,
            paymentIntentId: response.paymentIntentId,
            clientSecret: response.clientSecret
        )
    }

    func finalizeCardPayment(checkoutId: String, paymentIntentId: String) async throws -> FoodOrder {
        let response: OrderEnvelope = try await authenticated(
            path: "finalize-payment", method: "POST",
            body: ["checkout_id": checkoutId, "payment_intent_id": paymentIntentId]
        )
        return response.order
    }

    func activeOrder() async throws -> FoodOrder? {
        let response: OptionalOrderEnvelope = try await authenticated(path: "active", method: "GET")
        return response.order
    }

    func orders() async throws -> [FoodOrder] {
        let response: OrdersEnvelope = try await authenticated(path: "orders", method: "GET")
        return response.orders
    }

    func tracking(orderId: String) async throws -> FoodOrderTracking {
        try await authenticated(path: "orders/\(orderId)", method: "GET")
    }

    func cancel(orderId: String) async throws -> FoodOrder {
        let response: OrderEnvelope = try await authenticated(
            path: "orders/\(orderId)/cancel", method: "POST", body: [:]
        )
        return response.order
    }

    private func catalog<T: Decodable>(_ table: String, query: [URLQueryItem]) async throws -> T {
        var components = URLComponents(
            url: supabaseURL.appendingPathComponent("rest/v1/\(table)"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = query
        guard let url = components?.url else { throw FoodDeliveryError.message("Invalid catalog request.") }
        var request = URLRequest(url: url)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(data: data, response: response)
        return try decoder.decode(T.self, from: data)
    }

    private func authenticated<T: Decodable>(
        path: String, method: String, body: [String: Any]? = nil
    ) async throws -> T {
        guard let user = Auth.auth().currentUser else {
            throw FoodDeliveryError.message("Please sign in to use food delivery.")
        }
        let token = try await user.getIDToken()
        var request = URLRequest(url: foodURL.appendingPathComponent(path))
        request.timeoutInterval = 20
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(data: data, response: response)
        return try decoder.decode(T.self, from: data)
    }

    private func validate(data: Data, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw FoodDeliveryError.message("The food service did not respond.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(ErrorEnvelope.self, from: data).error)
                ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw FoodDeliveryError.message(message)
        }
    }

    private func orderBody(
        id: String, marketId: String, restaurantId: String,
        address: FoodDeliveryAddress, lines: [FoodCartLine],
        idKey: String = "client_request_id"
    ) -> [String: Any] {
        var delivery: [String: Any] = [
            "address_confirmed": true,
            "delivery_latitude": address.latitude,
            "delivery_longitude": address.longitude,
            "formatted_address": address.formattedAddress,
            "recipient_name": address.recipientName,
            "recipient_phone": address.recipientPhone,
        ]
        let optional: [(String, String)] = [
            ("district", address.district), ("landmark", address.landmark),
            ("building", address.building), ("floor", address.floor),
            ("apartment", address.apartment),
            ("delivery_instructions", address.instructions),
        ]
        optional.forEach { key, value in
            let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty { delivery[key] = clean }
        }
        return [
            idKey: id,
            "market_id": marketId,
            "restaurant_id": restaurantId,
            "delivery": delivery,
            "items": lines.map {
                var item: [String: Any] = ["menu_item_id": $0.item.id, "quantity": $0.quantity]
                let notes = $0.customerNotes.trimmingCharacters(in: .whitespacesAndNewlines)
                if !notes.isEmpty { item["customer_notes"] = notes }
                return item
            },
        ]
    }
}

@MainActor
final class FoodDeliveryStore: ObservableObject {
    @Published private(set) var markets: [FoodMarket] = []
    @Published private(set) var restaurants: [FoodRestaurant] = []
    @Published private(set) var hours: [FoodRestaurantHour] = []
    @Published private(set) var categories: [FoodMenuCategory] = []
    @Published private(set) var menuItems: [FoodMenuItem] = []
    @Published var selectedMarket: FoodMarket?
    @Published var cartRestaurant: FoodRestaurant?
    @Published var cart: [FoodCartLine] = []
    @Published var address = FoodDeliveryAddress()
    @Published var searchText = ""
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let cartKey = "lumo.food.cart.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: cartKey),
           let saved = try? JSONDecoder().decode(FoodCartSnapshot.self, from: data) {
            cartRestaurant = saved.restaurant
            cart = saved.lines
        }
        if let user = Auth.auth().currentUser {
            address.recipientName = user.displayName ?? ""
            address.recipientPhone = user.phoneNumber ?? ""
        }
    }

    var visibleRestaurants: [FoodRestaurant] {
        restaurants.filter { restaurant in
            guard restaurant.marketId == selectedMarket?.id else { return false }
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            return query.isEmpty || restaurant.displayName.localizedCaseInsensitiveContains(query)
                || restaurant.displayCuisine.localizedCaseInsensitiveContains(query)
        }
    }

    var subtotalMinor: Int64 { cart.reduce(0) { $0 + $1.lineTotalMinor } }
    var deliveryFeeMinor: Int64 { cartRestaurant?.deliveryFeeMinor ?? 0 }
    var serviceFeeMinor: Int64 {
        var fee = Int64((Double(subtotalMinor) * 0.05).rounded())
        if cartRestaurant?.countryCode == "IQ" {
            fee = max(500_000, min(1_500_000, fee))
        }
        return fee
    }
    var taxMinor: Int64 {
        Int64((Double(subtotalMinor) * (cartRestaurant?.taxRate ?? 0)).rounded())
    }
    var totalMinor: Int64 { subtotalMinor + deliveryFeeMinor + serviceFeeMinor + taxMinor }
    var totalQuantity: Int { cart.reduce(0) { $0 + $1.quantity } }

    func loadCatalog(coordinate: CLLocationCoordinate2D? = nil) async {
        guard markets.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let catalog = try await FoodDeliveryService.shared.loadCatalog()
            markets = catalog.markets
            restaurants = catalog.restaurants
            hours = catalog.hours
            categories = catalog.categories
            menuItems = catalog.items
            selectedMarket = await bestMarket(for: coordinate) ?? catalog.markets.first
            if let restaurant = cartRestaurant,
               !catalog.restaurants.contains(where: { $0.id == restaurant.id }) {
                clearCart()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectMarket(_ market: FoodMarket) {
        selectedMarket = market
    }

    func categories(for restaurant: FoodRestaurant) -> [FoodMenuCategory] {
        categories.filter { $0.restaurantId == restaurant.id }.sorted { $0.displayOrder < $1.displayOrder }
    }

    func items(for category: FoodMenuCategory) -> [FoodMenuItem] {
        menuItems.filter { $0.categoryId == category.id }.sorted { $0.displayOrder < $1.displayOrder }
    }

    func isOpen(_ restaurant: FoodRestaurant, now: Date = Date()) -> Bool {
        guard let zone = TimeZone(identifier: restaurant.timezone) else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let weekday = calendar.component(.weekday, from: now) - 1
        let current = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        if let schedule = hours.first(where: { $0.restaurantId == restaurant.id && $0.dayOfWeek == weekday }),
           !schedule.isClosed {
            if schedule.is24Hours { return true }
            if let opens = minutes(schedule.opensAt), let closes = minutes(schedule.closesAt) {
                if closes > opens, current >= opens, current < closes { return true }
                if closes < opens, current >= opens { return true }
            }
        }
        let previousDay = (weekday + 6) % 7
        if let previous = hours.first(where: { $0.restaurantId == restaurant.id && $0.dayOfWeek == previousDay }),
           !previous.isClosed, !previous.is24Hours,
           let opens = minutes(previous.opensAt), let closes = minutes(previous.closesAt),
           closes < opens, current < closes {
            return true
        }
        return false
    }

    func add(_ item: FoodMenuItem, restaurant: FoodRestaurant) {
        guard item.restaurantId == restaurant.id else { return }
        if let existingRestaurant = cartRestaurant, existingRestaurant.id != restaurant.id {
            errorMessage = "Finish or clear your current restaurant cart first."
            return
        }
        cartRestaurant = restaurant
        if let index = cart.firstIndex(where: { $0.id == item.id }) {
            cart[index].quantity = min(25, cart[index].quantity + 1)
        } else {
            cart.append(.init(item: item, quantity: 1, customerNotes: ""))
        }
        persistCart()
    }

    func changeQuantity(itemId: String, by delta: Int) {
        guard let index = cart.firstIndex(where: { $0.id == itemId }) else { return }
        let quantity = cart[index].quantity + delta
        if quantity <= 0 { cart.remove(at: index) } else { cart[index].quantity = min(25, quantity) }
        if cart.isEmpty { cartRestaurant = nil }
        persistCart()
    }

    func updateNotes(itemId: String, notes: String) {
        guard let index = cart.firstIndex(where: { $0.id == itemId }) else { return }
        cart[index].customerNotes = String(notes.prefix(500))
        persistCart()
    }

    func clearCart() {
        cart = []
        cartRestaurant = nil
        UserDefaults.standard.removeObject(forKey: cartKey)
    }

    func orderPlaced() { clearCart() }

    private func persistCart() {
        guard let restaurant = cartRestaurant, !cart.isEmpty,
              let data = try? JSONEncoder().encode(FoodCartSnapshot(restaurant: restaurant, lines: cart)) else {
            UserDefaults.standard.removeObject(forKey: cartKey)
            return
        }
        UserDefaults.standard.set(data, forKey: cartKey)
    }

    private func minutes(_ value: String?) -> Int? {
        guard let value else { return nil }
        let pieces = value.split(separator: ":")
        guard pieces.count >= 2, let hour = Int(pieces[0]), let minute = Int(pieces[1]) else { return nil }
        return hour * 60 + minute
    }

    private func bestMarket(for coordinate: CLLocationCoordinate2D?) async -> FoodMarket? {
        guard let coordinate else { return nil }
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first,
              let countryCode = placemark.isoCountryCode else { return nil }
        if let city = placemark.locality,
           let exact = markets.first(where: {
               $0.countryCode.caseInsensitiveCompare(countryCode) == .orderedSame &&
               $0.city.caseInsensitiveCompare(city) == .orderedSame
           }) { return exact }
        return markets.first { $0.countryCode.caseInsensitiveCompare(countryCode) == .orderedSame }
    }
}

private struct ErrorEnvelope: Decodable { let error: String }
private struct OrderEnvelope: Decodable { let order: FoodOrder }
private struct OptionalOrderEnvelope: Decodable { let order: FoodOrder? }
private struct OrdersEnvelope: Decodable { let orders: [FoodOrder] }
private struct PaymentEnvelope: Decodable {
    let checkoutId: String
    let paymentIntentId: String
    let clientSecret: String
}
