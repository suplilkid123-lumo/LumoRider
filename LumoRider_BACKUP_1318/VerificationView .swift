import SwiftUI
import FirebaseAuth

struct VerificationView: View {
    @State private var code: String = ""
    @State private var isVerifying: Bool = false
    @State private var errorMessage: String? = nil

    // 👇 NEW: when true, we navigate to HomeView
    @State private var goToHome: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Color.black
                    .ignoresSafeArea()

                VStack(spacing: 24) {

                    // MARK: - Title
                    Text("Enter your code")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.top, 40)

                    Text("We’ve sent a 6-digit code to your phone.")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    // MARK: - Code input
                    HStack(spacing: 12) {
                        Image(systemName: "key.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.black)

                        ZStack(alignment: .leading) {
                            if code.isEmpty {
                                Text("123456")
                                    .foregroundColor(.gray.opacity(0.8))
                            }

                            TextField("", text: $code)
                                .keyboardType(.numberPad)
                                .foregroundColor(.black)
                        }
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 56)
                    .frame(maxWidth: .infinity)
                    .background(Color.white)
                    .cornerRadius(20)
                    .padding(.horizontal, 32)

                    // MARK: - Verify button
                    Button(action: verifyCode) {
                        Text(isVerifying ? "Verifying..." : "Continue")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Color.white.opacity(isVerifying ? 0.6 : 1))
                            .cornerRadius(28)
                    }
                    .disabled(isVerifying)
                    .padding(.horizontal, 32)

                    // Error text
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 13))
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }

                    Spacer()
                }
            }
            // 👇 NEW: when goToHome = true, push HomeView
            .navigationDestination(isPresented: $goToHome) {
                HomeView()
            }
        }
    }

    // MARK: - Verify SMS code with Firebase
    private func verifyCode() {
        errorMessage = nil

        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCode.isEmpty else {
            errorMessage = "Please enter the code."
            return
        }

        // Get verificationID we saved in GetStartedView
        guard let verificationID = UserDefaults.standard.string(forKey: "authVerificationID") else {
            errorMessage = "Missing verification ID. Please go back and resend the code."
            return
        }

        isVerifying = true

        let credential = PhoneAuthProvider.provider().credential(
            withVerificationID: verificationID,
            verificationCode: trimmedCode
        )

        Auth.auth().signIn(with: credential) { result, error in
            DispatchQueue.main.async {
                self.isVerifying = false

                if let error = error {
                    print("Error verifying code:", error)
                    self.errorMessage = error.localizedDescription
                    return
                }

                // ✅ Successfully signed in
                print("✅ Logged in successfully as \(result?.user.uid ?? "unknown user")")

                // 👇 NEW: go to HomeView
                self.goToHome = true
            }
        }
    }
}

#Preview {
    VerificationView()
}
