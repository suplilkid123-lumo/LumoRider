import Foundation

struct StripeConfig {
    // Stripe publishable key (your current working key)
    static let publishableKey: String = "pk_live_51SYcoFQ6IGlq5XrepT1RjJd1Dh8Rus7xXirP7b3EIcFdUZFFATcZTcSRN1PKztPzrTAnimWMXYjPnKfkLStOWK4F00vhxUtuoa"

    // Apple Pay
    static let applePayMerchantId: String = "merchant.com.alyaa.RealLumo"
    static let applePayCountryCode: String = "US"
    static let applePayCurrency: String = "usd"
    static let merchantDisplayName: String = "RealLumo"

    // Supabase Edge Function URL (we will fill this after deploy)
    static let createPaymentIntentURLString: String = "https://rpryqbdodbieioebedjg.functions.supabase.co/create-payment-intent"
}
