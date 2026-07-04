import SwiftUI
import FirebaseAuth

struct VerificationView: View {
    @State private var code: String = ""
    @State private var isVerifying: Bool = false
    @State private var errorMessage: String? = nil

    // 👇 NEW: when true, we navigate to HomeView
    @State private var goToHome: Bool = false

    // 👇 NEW: resend support state
    @State private var canResend: Bool = false
    @State private var resendSeconds: Int = 30
    @State private var resendTimer: Timer? = nil

    @State private var verificationIDState: String

    init(verificationID: String) {
        _verificationIDState = State(initialValue: verificationID)
    }

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
                                .onChange(of: code) { newValue in
                                    let filtered = newValue.filter { $0.isNumber }
                                    if filtered.count > 6 {
                                        code = String(filtered.prefix(6))
                                    } else if filtered != newValue {
                                        code = filtered
                                    }
                                }
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
                    .disabled(isVerifying || code.count != 6)
                    .padding(.horizontal, 32)

                    // Error text
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 13))
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }

                    // Resend code button + countdown
                    Button(action: resendCode) {
                        Text(canResend ? "Resend code" : "Resend in \(resendSeconds)s")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(canResend ? 0.95 : 0.55))
                    }
                    .disabled(!canResend)
                    
                    Spacer()
                }
            }
            .onAppear {
                startResendCooldown(30)
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

        // Simple validation: must be 6 digits
        guard trimmedCode.count == 6, trimmedCode.allSatisfy({ $0.isNumber }) else {
            errorMessage = "Please enter the 6-digit code."
            return
        }

        isVerifying = true

        let credential = PhoneAuthProvider.provider().credential(
            withVerificationID: verificationIDState,
            verificationCode: trimmedCode
        )

        Auth.auth().signIn(with: credential) { authResult, error in
            DispatchQueue.main.async {
                self.isVerifying = false
                if let error = error as NSError? {
                    if let code = AuthErrorCode(rawValue: error.code) {
                        switch code {
                        case .invalidVerificationCode:
                            self.errorMessage = "The code you entered is incorrect."
                        case .sessionExpired:
                            self.errorMessage = "The code has expired. Please request a new one."
                        case .quotaExceeded:
                            self.errorMessage = "Too many attempts. Try again later."
                        case .invalidVerificationID:
                            self.errorMessage = "Verification session is invalid. Please restart sign in."
                        default:
                            self.errorMessage = error.localizedDescription
                        }
                    } else {
                        self.errorMessage = error.localizedDescription
                    }
                    return
                }

                // Success
                UserDefaults.standard.set(true, forKey: "lumo_has_completed_login")
                self.goToHome = true
            }
        }
    }

    private func startResendCooldown(_ seconds: Int = 30) {
        resendTimer?.invalidate()
        resendSeconds = seconds
        canResend = false

        resendTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if resendSeconds > 0 {
                resendSeconds -= 1
            }
            if resendSeconds <= 0 {
                resendTimer?.invalidate()
                resendTimer = nil
                canResend = true
            }
        }
        if let t = resendTimer { RunLoop.main.add(t, forMode: .common) }
    }

    private func resendCode() {
        guard canResend else { return }
        canResend = false
        errorMessage = nil

        let phone = UserDefaults.standard.string(forKey: "auth_phone_e164") ?? ""
        guard !phone.isEmpty else {
            errorMessage = "Missing phone number. Please go back and try again."
            canResend = true
            return
        }

        PhoneAuthProvider.provider().verifyPhoneNumber(phone, uiDelegate: nil) { id, error in
            DispatchQueue.main.async {
                if let error = error as NSError? {
                    if let code = AuthErrorCode(rawValue: error.code) {
                        switch code {
                        case .quotaExceeded:
                            self.errorMessage = "Too many attempts. Try again later."
                        case .invalidPhoneNumber:
                            self.errorMessage = "Invalid phone number."
                        default:
                            self.errorMessage = error.localizedDescription
                        }
                    } else {
                        self.errorMessage = error.localizedDescription
                    }
                    self.canResend = true
                    return
                }

                guard let id else {
                    self.errorMessage = "Couldn’t resend code. Please try again."
                    self.canResend = true
                    return
                }

                self.verificationIDState = id
                self.startResendCooldown()
            }
        }
    }
}

#Preview {
    VerificationView(verificationID: "")
}
