import Foundation
import FirebaseFirestore

func sendTestRide() {
    let db = Firestore.firestore()
    
    let rideData: [String: Any] = [
        "riderName": "Test Rider",
        "pickup": "123 Main St",
        "dropoff": "456 Market St",
        "timestamp": Timestamp(date: Date())
    ]
    
    db.collection("test_rides").addDocument(data: rideData) { error in
        if let error = error {
            print("❌ Failed to send ride:", error.localizedDescription)
        } else {
            print("✅ Test ride sent successfully")
        }
    }
}
