import Foundation
import CoreLocation

struct FoodMarket: Codable, Identifiable, Hashable {
    let id: String
    let marketCode: String
    let countryCode: String
    let city: String
    let currency: String
    let timezone: String
    let language: String
    let isActive: Bool
    let cashEnabled: Bool
    let onlinePaymentEnabled: Bool
    let minimumOrderAmountMinor: Int64
    let deliveryFeeMinor: Int64
    let serviceFeeMinor: Int64
    let taxRate: Double
}

struct FoodRestaurant: Codable, Identifiable, Hashable {
    let id: String
    let marketId: String
    let restaurantCode: String
    let nameEn: String
    let nameAr: String
    let descriptionEn: String
    let descriptionAr: String
    let cuisineEn: String
    let cuisineAr: String
    let countryCode: String
    let city: String
    let currency: String
    let timezone: String
    let language: String
    let isActive: Bool
    let cashEnabled: Bool
    let onlinePaymentEnabled: Bool
    let minimumOrderAmountMinor: Int64
    let deliveryFeeMinor: Int64
    let serviceFeeMinor: Int64
    let taxRate: Double
    let rating: Double
    let estimatedDeliveryMinutes: Int

    var displayName: String { FoodLocale.isArabic ? nameAr : nameEn }
    var displayDescription: String { FoodLocale.isArabic ? descriptionAr : descriptionEn }
    var displayCuisine: String { FoodLocale.isArabic ? cuisineAr : cuisineEn }
}

struct FoodRestaurantHour: Codable, Identifiable, Hashable {
    let id: String
    let restaurantId: String
    let dayOfWeek: Int
    let opensAt: String?
    let closesAt: String?
    let isClosed: Bool
    let is24Hours: Bool
}

struct FoodMenuCategory: Codable, Identifiable, Hashable {
    let id: String
    let restaurantId: String
    let categoryCode: String
    let nameEn: String
    let nameAr: String
    let displayOrder: Int
    let isActive: Bool

    var displayName: String { FoodLocale.isArabic ? nameAr : nameEn }
}

struct FoodMenuItem: Codable, Identifiable, Hashable {
    let id: String
    let restaurantId: String
    let categoryId: String
    let itemCode: String
    let nameEn: String
    let nameAr: String
    let descriptionEn: String
    let descriptionAr: String
    let priceMinor: Int64
    let currency: String
    let displayOrder: Int
    let isActive: Bool
    let isAvailable: Bool

    var displayName: String { FoodLocale.isArabic ? nameAr : nameEn }
    var displayDescription: String { FoodLocale.isArabic ? descriptionAr : descriptionEn }
}

struct FoodCartLine: Codable, Identifiable, Hashable {
    var item: FoodMenuItem
    var quantity: Int
    var customerNotes: String
    var id: String { item.id }
    var lineTotalMinor: Int64 { item.priceMinor * Int64(quantity) }
}

struct FoodCartSnapshot: Codable {
    var restaurant: FoodRestaurant
    var lines: [FoodCartLine]
}

struct FoodDeliveryAddress: Codable, Equatable {
    var formattedAddress = ""
    var latitude: Double = 0
    var longitude: Double = 0
    var district = ""
    var landmark = ""
    var building = ""
    var floor = ""
    var apartment = ""
    var instructions = ""
    var recipientName = ""
    var recipientPhone = ""

    var isValid: Bool {
        formattedAddress.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3 &&
        (-90...90).contains(latitude) && (-180...180).contains(longitude) &&
        !recipientName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        recipientPhone.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3
    }
}

struct FoodOrder: Codable, Identifiable, Hashable {
    let id: String
    let clientRequestId: String
    let riderFirebaseUid: String
    let marketId: String
    let marketCountryCode: String
    let marketCity: String
    let restaurantId: String
    let restaurantName: String
    let currency: String
    let subtotalMinor: Int64
    let deliveryFeeMinor: Int64
    let serviceFeeMinor: Int64
    let appliedTaxRate: Double
    let taxMinor: Int64
    let totalMinor: Int64
    let paymentMethod: String
    let paymentStatus: String
    let orderStatus: String
    let deliveryLatitude: Double
    let deliveryLongitude: Double
    let formattedAddress: String
    let district: String?
    let landmark: String?
    let building: String?
    let floor: String?
    let apartment: String?
    let deliveryInstructions: String?
    let recipientName: String
    let recipientPhone: String
    let createdAt: String
    let updatedAt: String
    let stripePaymentIntentId: String?
}

struct FoodOrderItem: Codable, Identifiable, Hashable {
    let id: String
    let orderId: String
    let menuItemId: String
    let itemName: String
    let unitPriceMinor: Int64
    let quantity: Int
    let lineTotalMinor: Int64
    let customerNotes: String?
    let createdAt: String
}

struct FoodOrderStatusEvent: Codable, Identifiable, Hashable {
    let id: String
    let orderId: String
    let orderStatus: String
    let actorType: String
    let actorId: String?
    let note: String?
    let createdAt: String
}

struct FoodDriverSummary: Codable, Hashable {
    let displayName: String?
    let vehicleMake: String?
    let vehicleModel: String?
    let vehicleColor: String?
    let vehiclePlate: String?
}

struct FoodDriverLocation: Codable, Hashable {
    let latitude: Double
    let longitude: Double
    let updatedAt: String
}

struct FoodDeliveryAssignment: Codable, Hashable {
    let jobId: String
    let dispatchStatus: String
    let driver: FoodDriverSummary?
    let location: FoodDriverLocation?
    let assignedAt: String?
    let arrivedRestaurantAt: String?
    let pickedUpAt: String?
    let onTheWayAt: String?
    let deliveredAt: String?
}

struct FoodOrderTracking: Codable {
    let order: FoodOrder
    let items: [FoodOrderItem]
    let statusHistory: [FoodOrderStatusEvent]
    let deliveryAssignment: FoodDeliveryAssignment?
}

struct FoodPaymentPreparation: Codable {
    let checkoutId: String
    let paymentIntentId: String
    let clientSecret: String
}

enum FoodLocale {
    static var isArabic: Bool { Locale.current.languageCode == "ar" }

    static func scale(for currency: String) -> Double {
        currency.uppercased() == "USD" ? 100 : 1_000
    }

    static func amount(_ minor: Int64, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency.uppercased()
        formatter.maximumFractionDigits = currency.uppercased() == "USD" ? 2 : 0
        return formatter.string(from: NSNumber(value: Double(minor) / scale(for: currency)))
            ?? "\(Double(minor) / scale(for: currency)) \(currency.uppercased())"
    }

    static func status(_ raw: String) -> String {
        switch raw {
        case "placed": return "Order placed"
        case "confirmed", "accepted": return "Restaurant accepted"
        case "preparing": return "Preparing your order"
        case "ready_for_pickup": return "Ready for pickup"
        case "driver_assigned": return "Driver assigned"
        case "driver_at_restaurant": return "Driver at restaurant"
        case "picked_up": return "Picked up"
        case "on_the_way", "out_for_delivery": return "On the way"
        case "delivered": return "Delivered"
        case "rejected": return "Restaurant declined"
        case "cancelled": return "Cancelled"
        default: return raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

