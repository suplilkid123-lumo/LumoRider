import Foundation

struct IraqLaunchFareCalculator {

    static func calculateFare(
        distanceMeters: Double,
        durationSeconds: Int
    ) -> Int {

        let baseFareIQD = 700
        let perKmIQD = 260
        let perMinuteIQD = 90
        let minimumFareIQD = 2800
        let roundingIQD = 250

        let distanceKm = distanceMeters / 1000.0
        let durationMinutes = Double(durationSeconds) / 60.0

        let rawFare =
            Double(baseFareIQD) +
            (distanceKm * Double(perKmIQD)) +
            (durationMinutes * Double(perMinuteIQD))

        let roundedFare =
            Int((rawFare / Double(roundingIQD)).rounded()) * roundingIQD

        return max(roundedFare, minimumFareIQD)
    }
}

struct USDLaunchFareCalculator {

    static func calculateFare(
        distanceMeters: Double,
        durationSeconds: Int
    ) -> Double {

        let baseFareUSD = 0.99
        let perKmUSD = 0.45
        let perMinuteUSD = 0.24
        let minimumFareUSD = 5.99
        let roundingUSD = 0.01

        let distanceKm = distanceMeters / 1000.0
        let durationMinutes = Double(durationSeconds) / 60.0

        let rawFare =
            baseFareUSD +
            (distanceKm * perKmUSD) +
            (durationMinutes * perMinuteUSD)

        let roundedFare =
            (rawFare / roundingUSD).rounded() * roundingUSD

        return max(roundedFare, minimumFareUSD)
    }
}

// MARK: - Auto currency selection (IQD in Iraq, USD elsewhere)

struct FareQuote: Equatable {
    let amount: Double
    let currencyCode: String
}

struct AutoFareCalculator {

    /// Chooses IQD when `countryCode` is "IQ" (Iraq). Defaults to USD otherwise.
    static func calculateFare(
        distanceMeters: Double,
        durationSeconds: Int,
        countryCode: String?
    ) -> FareQuote {

        let code = (countryCode ?? "").uppercased()

        if code == "IQ" {
            let iqd = IraqLaunchFareCalculator.calculateFare(
                distanceMeters: distanceMeters,
                durationSeconds: durationSeconds
            )
            return FareQuote(amount: Double(iqd), currencyCode: "IQD")
        } else {
            let usd = USDLaunchFareCalculator.calculateFare(
                distanceMeters: distanceMeters,
                durationSeconds: durationSeconds
            )
            return FareQuote(amount: usd, currencyCode: "USD")
        }
    }

    /// Convenience for when you haven't geocoded a country code yet.
    /// Uses the device region to choose IQD vs USD.
    static func calculateFareUsingDeviceRegion(
        distanceMeters: Double,
        durationSeconds: Int
    ) -> FareQuote {

        // iOS 16+ prefers Locale.Region; regionCode is fine as fallback.
        let deviceCountryCode =
            Locale.current.region?.identifier ?? Locale.current.regionCode

        return calculateFare(
            distanceMeters: distanceMeters,
            durationSeconds: durationSeconds,
            countryCode: deviceCountryCode
        )
    }
}

