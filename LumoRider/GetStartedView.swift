import SwiftUI
import UIKit
import FirebaseAuth
import FirebaseCore
import GoogleSignIn
import AuthenticationServices
import CryptoKit

// Helper: format as 3-3-4 (e.g. 425-345-2691)
func formatPhoneNumber(_ number: String) -> String {
    // Remove all non-digits
    let digits = number.filter { $0.isNumber }
    
    var result = ""
    var index = digits.startIndex
    
    // First 3 digits
    if digits.count > 0 {
        let end = digits.index(index, offsetBy: min(3, digits.count))
        result.append(contentsOf: digits[index..<end])
        if digits.count > 3 { result.append("-") }
        index = end
    }
    
    // Next 3 digits
    if digits.count > 3 {
        let end = digits.index(index, offsetBy: min(3, digits.count - 3))
        result.append(contentsOf: digits[index..<end])
        if digits.count > 6 { result.append("-") }
        index = end
    }
    
    // Last 4 digits
    if digits.count > 6 {
        let end = digits.index(index, offsetBy: min(4, digits.count - 6))
        result.append(contentsOf: digits[index..<end])
    }
    
    return result
}

// Simple model for the picker list
struct CountryOption: Identifiable {
    let id = UUID()
    let label: String    // e.g. "Germany"
    let code: String     // e.g. "+49"
}

struct GetStartedView: View {
    @State private var phoneNumber: String = ""
    @State private var isSending: Bool = false
    @State private var errorMessage: String? = nil
    @State private var goToVerify: Bool = false
    @State private var verificationIDState: String? = nil

    // navigate to HomeView after Google or Email login
    @State private var goToHome: Bool = false
    @State private var goToEmail: Bool = false

    // country code + picker
    @State private var countryCode: String = "+1"
    @State private var showCodePicker: Bool = false

    // Social sign-in state (Apple / Google)
    @State private var isAppleSigningIn: Bool = false
    @State private var isGoogleSigningIn: Bool = false
    @State private var showAlert: Bool = false
    @State private var alertMessage: String = ""

    // Apple Sign In nonce
    @State private var currentNonce: String? = nil

    @FocusState private var isPhoneFieldFocused: Bool

    // ALL Middle East + Europe (+ USA at top)
    private let countryOptions: [CountryOption] = [
        // --- Extra: USA (keep at top)
        CountryOption(label: "United States (USA)", code: "+1"),

        // --- Middle East ---
        CountryOption(label: "Bahrain", code: "+973"),
        CountryOption(label: "Cyprus", code: "+357"),
        CountryOption(label: "Egypt", code: "+20"),
        CountryOption(label: "Iran", code: "+98"),
        CountryOption(label: "Iraq", code: "+964"),
        CountryOption(label: "Israel", code: "+972"),
        CountryOption(label: "Jordan", code: "+962"),
        CountryOption(label: "Kuwait", code: "+965"),
        CountryOption(label: "Lebanon", code: "+961"),
        CountryOption(label: "Oman", code: "+968"),
        CountryOption(label: "Palestine", code: "+970"),
        CountryOption(label: "Qatar", code: "+974"),
        CountryOption(label: "Saudi Arabia", code: "+966"),
        CountryOption(label: "Syria", code: "+963"),
        CountryOption(label: "Turkey", code: "+90"),
        CountryOption(label: "United Arab Emirates", code: "+971"),
        CountryOption(label: "Yemen", code: "+967"),

        // --- Europe ---
        CountryOption(label: "Albania", code: "+355"),
        CountryOption(label: "Andorra", code: "+376"),
        CountryOption(label: "Armenia", code: "+374"),
        CountryOption(label: "Austria", code: "+43"),
        CountryOption(label: "Azerbaijan", code: "+994"),
        CountryOption(label: "Belarus", code: "+375"),
        CountryOption(label: "Belgium", code: "+32"),
        CountryOption(label: "Bosnia and Herzegovina", code: "+387"),
        CountryOption(label: "Bulgaria", code: "+359"),
        CountryOption(label: "Croatia", code: "+385"),
        CountryOption(label: "Czech Republic", code: "+420"),
        CountryOption(label: "Denmark", code: "+45"),
        CountryOption(label: "Estonia", code: "+372"),
        CountryOption(label: "Finland", code: "+358"),
        CountryOption(label: "France", code: "+33"),
        CountryOption(label: "Georgia", code: "+995"),
        CountryOption(label: "Germany", code: "+49"),
        CountryOption(label: "Greece", code: "+30"),
        CountryOption(label: "Hungary", code: "+36"),
        CountryOption(label: "Iceland", code: "+354"),
        CountryOption(label: "Ireland", code: "+353"),
        CountryOption(label: "Italy", code: "+39"),
        CountryOption(label: "Kosovo", code: "+383"),
        CountryOption(label: "Latvia", code: "+371"),
        CountryOption(label: "Liechtenstein", code: "+423"),
        CountryOption(label: "Lithuania", code: "+370"),
        CountryOption(label: "Luxembourg", code: "+352"),
        CountryOption(label: "Malta", code: "+356"),
        CountryOption(label: "Moldova", code: "+373"),
        CountryOption(label: "Monaco", code: "+377"),
        CountryOption(label: "Montenegro", code: "+382"),
        CountryOption(label: "Netherlands", code: "+31"),
        CountryOption(label: "North Macedonia", code: "+389"),
        CountryOption(label: "Norway", code: "+47"),
        CountryOption(label: "Poland", code: "+48"),
        CountryOption(label: "Portugal", code: "+351"),
        CountryOption(label: "Romania", code: "+40"),
        CountryOption(label: "Russia", code: "+7"),
        CountryOption(label: "San Marino", code: "+378"),
        CountryOption(label: "Serbia", code: "+381"),
        CountryOption(label: "Slovakia", code: "+421"),
        CountryOption(label: "Slovenia", code: "+386"),
        CountryOption(label: "Spain", code: "+34"),
        CountryOption(label: "Sweden", code: "+46"),
        CountryOption(label: "Switzerland", code: "+41"),
        CountryOption(label: "Ukraine", code: "+380"),
        CountryOption(label: "United Kingdom (UK)", code: "+44"),
        CountryOption(label: "Vatican City", code: "+39")
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black
                    .ignoresSafeArea()

                VStack(spacing: 24) {

                    // MARK: - Top: Car
                    Image("speedCar")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 140)
                        .padding(.top, 40)

                    // MARK: - Title
                    Text("Get started with Lumo")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.top, -60)

                    // MARK: - Phone input
                    VStack(spacing: 16) {
                        HStack(spacing: 12) {

                            // country code button on the left
                            Button {
                                showCodePicker = true
                            } label: {
                                Text(countryCode)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.black)
                            }

                            // small divider between code + phone
                            Rectangle()
                                .fill(Color.black.opacity(0.2))
                                .frame(width: 1, height: 24)

                            // phone icon
                            Image(systemName: "phone.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.black)

                            // phone text field
                            TextField("201-555-0123", text: $phoneNumber)
                                .keyboardType(.phonePad)
                                .textContentType(.telephoneNumber)
                                .foregroundColor(.black)
                                .focused($isPhoneFieldFocused)
                                .onChange(of: phoneNumber) { newValue in
                                    let formatted = formatPhoneNumber(newValue)
                                    if formatted != newValue {
                                        phoneNumber = formatted
                                    }
                                }
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 56)
                        .frame(maxWidth: .infinity)
                        .background(Color.white)
                        .cornerRadius(20)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            isPhoneFieldFocused = true
                        }
                    }
                    .padding(.horizontal, 32)

                    // MARK: - Continue button (send SMS)
                    Button(action: sendCode) {
                        Text(isSending ? "Sending..." : "Continue")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Color.white.opacity(isSending ? 0.6 : 1))
                            .cornerRadius(28)
                    }
                    .disabled(isSending)
                    .padding(.horizontal, 32)

                    // Error text (if any)
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 13))
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }

                    // MARK: - "or" separator
                    HStack {
                        Rectangle()
                            .fill(Color.white.opacity(0.5))
                            .frame(height: 1)
                        Text("or")
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                        Rectangle()
                            .fill(Color.white.opacity(0.5))
                            .frame(height: 1)
                    }
                    .padding(.horizontal, 48)
                    .padding(.top, 4)

                    // MARK: - Social / email buttons
                    VStack(spacing: 14) {
                        SocialButton(
                            icon: Image(systemName: "apple.logo"),
                            text: isAppleSigningIn ? "Signing in..." : "Continue with Apple",
                            action: handleApple
                        )

                        SocialButton(
                            icon: Image(systemName: "g.circle"),
                            text: isGoogleSigningIn ? "Signing in..." : "Continue with Google",
                            action: handleGoogle
                        )

                        SocialButton(
                            icon: Image(systemName: "envelope.fill"),
                            text: "Continue with Email",
                            action: handleEmail
                        )
                    }
                    .padding(.horizontal, 32)
                    .padding(.top, 4)

                    Spacer()

                    // MARK: - Terms text
                    Text("By continuing, you agree to\nour Terms & Privacy Policy.")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 24)
                }
            }
            // navigate to verification
            .navigationDestination(isPresented: $goToVerify) {
                if let id = verificationIDState {
                    VerificationView(verificationID: id)
                } else {
                    Text("Missing verification ID.")
                }
            }
            // navigate to HomeView (Google or Email success)
            .navigationDestination(isPresented: $goToHome) {
                HomeView()
            }
            // navigate to EmailAuthView when "Continue with Email" is tapped
            .navigationDestination(isPresented: $goToEmail) {
                EmailAuthView {
                    // when email auth succeeds, close this screen and go to HomeView
                    goToEmail = false
                    goToHome = true
                }
            }
            // black sheet + X + scrollable country list
            .sheet(isPresented: $showCodePicker) {
                ZStack {
                    Color.black
                        .ignoresSafeArea()

                    VStack(spacing: 20) {

                        // top bar with X button
                        HStack {
                            Spacer()
                            Button {
                                showCodePicker = false
                            } label: {
                                Image(systemName: "xmark")
                                    .foregroundColor(.white)
                                    .font(.system(size: 20, weight: .semibold))
                                    .padding()
                            }
                        }

                        Text("Select Country Code")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.bottom, 10)

                        ScrollView {
                            VStack(spacing: 16) {
                                ForEach(countryOptions) { country in
                                    Button {
                                        countryCode = country.code
                                        showCodePicker = false
                                    } label: {
                                        Text("\(country.code)  \(country.label)")
                                            .foregroundColor(.white)
                                            .font(.system(size: 18))
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            }
                        }

                        Spacer()
                    }
                    .padding(.top, 20)
                    .padding(.horizontal, 24)
                }
            }
            .alert(isPresented: $showAlert) {
                Alert(
                    title: Text("Sign-in error"),
                    message: Text(alertMessage),
                    dismissButton: .default(Text("OK"))
                )
            }
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: - Send SMS code (TEMP: no Firebase, just navigate)
    private func sendCode() {
        // Clear old error
        errorMessage = nil

        let raw = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let digitsOnly = raw.filter { $0.isNumber }
        let formatted = countryCode + digitsOnly

        // Basic presence check
        guard !digitsOnly.isEmpty else {
            errorMessage = "Please enter your phone number."
            return
        }

        isSending = true

        // Save phone to UserDefaults for VerificationView (resend flow)
        UserDefaults.standard.set(formatted, forKey: "auth_phone_e164")

        PhoneAuthProvider.provider().verifyPhoneNumber(formatted, uiDelegate: nil) { id, error in
            DispatchQueue.main.async {
                self.isSending = false
                if let error = error as NSError? {
                    if let code = AuthErrorCode(rawValue: error.code) {
                        switch code {
                        case .invalidPhoneNumber:
                            self.errorMessage = "Invalid phone number. Check the format and try again."
                        case .quotaExceeded:
                            self.errorMessage = "Too many attempts. Try again later."
                        default:
                            self.errorMessage = error.localizedDescription
                        }
                    } else {
                        self.errorMessage = error.localizedDescription
                    }
                    return
                }

                guard let id else {
                    self.errorMessage = "Couldn’t start verification. Please try again."
                    return
                }

                self.verificationIDState = id
                self.goToVerify = true
            }
        }
    }

    // MARK: - Social button handlers

    private func handleApple() {
        guard !isAppleSigningIn else { return }
        isAppleSigningIn = true

        let nonce = randomNonceString()
        currentNonce = nonce

        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)

        let controller = ASAuthorizationController(authorizationRequests: [request])
        let coordinator = AppleSignInCoordinator(
            onSuccess: { idTokenString, fullName in
                guard let nonce = self.currentNonce else {
                    self.alertMessage = "Missing Apple Sign-In nonce."
                    self.showAlert = true
                    self.isAppleSigningIn = false
                    return
                }

                let credential = OAuthProvider.appleCredential(
                    withIDToken: idTokenString,
                    rawNonce: nonce,
                    fullName: fullName
                )
                Auth.auth().signIn(with: credential) { authResult, error in
                    DispatchQueue.main.async {
                        self.isAppleSigningIn = false

                        if let error = error {
                            self.alertMessage = error.localizedDescription
                            self.showAlert = true
                            return
                        }

                        if let user = authResult?.user {
                            print("✅ Signed in with Apple as \(user.uid)")
                            self.goToHome = true
                        } else {
                            self.alertMessage = "Apple sign-in succeeded but no user was returned."
                            self.showAlert = true
                        }
                    }
                }
            },
            onError: { error in
                self.alertMessage = error.localizedDescription
                self.showAlert = true
                self.isAppleSigningIn = false
            }
        )

        controller.delegate = coordinator
        controller.presentationContextProvider = coordinator

        // Keep coordinator alive for the duration of the request
        AppleSignInCoordinatorHolder.shared.coordinator = coordinator

        controller.performRequests()
    }
#if true
// MARK: - Apple Sign In (Firebase) helpers

private final class AppleSignInCoordinatorHolder {
    static let shared = AppleSignInCoordinatorHolder()
    var coordinator: AppleSignInCoordinator?
}

private final class AppleSignInCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private let onSuccess: (String, PersonNameComponents?) -> Void
    private let onError: (Error) -> Void

    init(onSuccess: @escaping (String, PersonNameComponents?) -> Void, onError: @escaping (Error) -> Void) {
        self.onSuccess = onSuccess
        self.onError = onError
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            onError(NSError(domain: "AppleSignIn", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid Apple credential."]))
            return
        }

        guard let tokenData = appleIDCredential.identityToken,
              let tokenString = String(data: tokenData, encoding: .utf8) else {
            onError(NSError(domain: "AppleSignIn", code: -2, userInfo: [NSLocalizedDescriptionKey: "Unable to fetch Apple identity token."]))
            return
        }

        onSuccess(tokenString, appleIDCredential.fullName)

        // Release after success
        AppleSignInCoordinatorHolder.shared.coordinator = nil
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        onError(error)

        // Release after error
        AppleSignInCoordinatorHolder.shared.coordinator = nil
    }
}

private func sha256(_ input: String) -> String {
    let inputData = Data(input.utf8)
    let hashed = SHA256.hash(data: inputData)
    return hashed.map { String(format: "%02x", $0) }.joined()
}

private func randomNonceString(length: Int = 32) -> String {
    precondition(length > 0)
    let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
    var result = ""
    var remaining = length

    while remaining > 0 {
        var randomBytes = [UInt8](repeating: 0, count: 16)
        let status = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        if status != errSecSuccess {
            fatalError("Unable to generate nonce. SecRandomCopyBytes failed.")
        }

        randomBytes.forEach { byte in
            if remaining == 0 { return }
            if byte < charset.count {
                result.append(charset[Int(byte)])
                remaining -= 1
            }
        }
    }

    return result
}
#endif

    private func handleEmail() {
        print("✉️ Continue with Email tapped")
        goToEmail = true
    }

    private func handleGoogle() {
        guard !isGoogleSigningIn else { return }
        isGoogleSigningIn = true

        guard let clientID = FirebaseApp.app()?.options.clientID else {
            alertMessage = "Missing Firebase client ID."
            showAlert = true
            isGoogleSigningIn = false
            return
        }

        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config

        // Find a root view controller to present Google UI
        guard
            let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
            let rootVC = scene.windows.first?.rootViewController
        else {
            alertMessage = "Unable to find a window to present Google sign-in."
            showAlert = true
            isGoogleSigningIn = false
            return
        }

        GIDSignIn.sharedInstance.signIn(withPresenting: rootVC) { result, error in
            if let error = error {
                DispatchQueue.main.async {
                    self.alertMessage = error.localizedDescription
                    self.showAlert = true
                    self.isGoogleSigningIn = false
                }
                return
            }

            guard
                let user = result?.user,
                let idToken = user.idToken?.tokenString
            else {
                DispatchQueue.main.async {
                    self.alertMessage = "Failed to retrieve Google user."
                    self.showAlert = true
                    self.isGoogleSigningIn = false
                }
                return
            }

            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: user.accessToken.tokenString
            )

            Auth.auth().signIn(with: credential) { authResult, error in
                DispatchQueue.main.async {
                    self.isGoogleSigningIn = false

                    if let error = error {
                        self.alertMessage = error.localizedDescription
                        self.showAlert = true
                        return
                    }

                    if let user = authResult?.user {
                        print("✅ Signed in with Google as \(user.uid)")
                        // go to HomeView
                        self.goToHome = true
                    }
                }
            }
        }
    }
}

// Reusable pill button
struct SocialButton: View {
    let icon: Image
    let text: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                icon
                    .renderingMode(.template)
                    .foregroundColor(.black)
                    .font(.system(size: 20))

                Text(text)
                    .font(.system(size: 17))
                    .foregroundColor(.black)

                Spacer()
            }
            .padding(.horizontal, 18)
            .frame(height: 52)
            .frame(maxWidth: .infinity)
            .background(Color.white)
            .cornerRadius(26)
        }
    }
}

// MARK: - Email Authentication Screen
struct EmailAuthView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var email: String = ""
    @State private var password: String = ""
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil

    /// Called when the user successfully signs in or signs up with email.
    let onSuccess: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black
                    .ignoresSafeArea()

                VStack(spacing: 24) {
                    // Top bar with back button
                    HStack {
                        Button(action: { dismiss() }) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(10)
                                .background(Color.white.opacity(0.12))
                                .clipShape(Circle())
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)

                    // Title
                    Text("Continue with Email")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.top, 10)

                    // Email + password fields
                    VStack(spacing: 16) {
                        // Email
                        TextField("Email", text: $email)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .padding(.horizontal, 16)
                            .frame(height: 52)
                            .frame(maxWidth: .infinity)
                            .background(Color.white)
                            .cornerRadius(20)

                        // Password
                        SecureField("Password (min 6 characters)", text: $password)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .padding(.horizontal, 16)
                            .frame(height: 52)
                            .frame(maxWidth: .infinity)
                            .background(Color.white)
                            .cornerRadius(20)
                    }
                    .padding(.horizontal, 32)

                    // Error text
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 13))
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }

                    // Log in button
                    Button(action: signIn) {
                        Text(isLoading ? "Please wait..." : "Log in")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color.white.opacity(isLoading ? 0.6 : 1))
                            .cornerRadius(26)
                    }
                    .disabled(isLoading)
                    .padding(.horizontal, 32)
                    .padding(.top, 8)

                    // Sign up button
                    Button(action: signUp) {
                        Text("Create a new account")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                        }
                        .padding(.top, 4)

                    Spacer()
                }
            }
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: - Email auth helpers

    private func signIn() {
        errorMessage = nil

        guard !email.isEmpty, !password.isEmpty else {
            errorMessage = "Please enter your email and password."
            return
        }

        // Basic email format check before calling Firebase
        guard email.contains("@"), email.contains(".") else {
            errorMessage = "Please enter a valid email address."
            return
        }

        isLoading = true

        Auth.auth().signIn(withEmail: email, password: password) { _, error in
            DispatchQueue.main.async {
                isLoading = false
                if let error = error {
                    let nsError = error as NSError
                    if nsError.domain == AuthErrorDomain,
                       let code = AuthErrorCode(rawValue: nsError.code) {
                        switch code {
                        case .userNotFound:
                            errorMessage = "No account found for this email. Tap \"Create a new account\" first."
                        case .invalidCredential:
                            errorMessage = "Invalid email or password. Please try again."
                        case .wrongPassword:
                            errorMessage = "Incorrect password. Please try again."
                        case .invalidEmail:
                            errorMessage = "Please enter a valid email address."
                        default:
                            errorMessage = nsError.localizedDescription
                        }
                    } else {
                        errorMessage = error.localizedDescription
                    }
                } else {
                    onSuccess()
                }
            }
        }
    }

    private func signUp() {
        errorMessage = nil

        guard !email.isEmpty, !password.isEmpty else {
            errorMessage = "Please enter your email and password."
            return
        }

        // Basic email format check before calling Firebase
        guard email.contains("@"), email.contains(".") else {
            errorMessage = "Please enter a valid email address."
            return
        }

        guard password.count >= 6 else {
            errorMessage = "Password must be at least 6 characters."
            return
        }

        isLoading = true

        Auth.auth().createUser(withEmail: email, password: password) { _, error in
            DispatchQueue.main.async {
                isLoading = false
                if let error = error {
                    errorMessage = error.localizedDescription
                } else {
                    onSuccess()
                }
            }
        }
    }
}

#Preview {
    EmailAuthView {
        // preview only
    }
}

#Preview {
    GetStartedView()
}

