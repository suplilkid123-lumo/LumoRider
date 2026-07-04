import SwiftUI
import Combine
import FirebaseAuth

final class AuthSession: ObservableObject {
    @Published var user: User? = Auth.auth().currentUser
    private var handle: AuthStateDidChangeListenerHandle?

    init() {
        handle = Auth.auth().addStateDidChangeListener { _, user in
            DispatchQueue.main.async {
                self.user = user
            }
        }
    }

    deinit {
        if let handle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }
}

struct SplashScreen: View {
    @State private var isActive = false
    @StateObject private var session = AuthSession()

    // ✅ This prevents "fresh install" from jumping straight to HomeView due to Keychain-persisted Firebase sessions.
    // Set this to true only after a successful login/verification.
    @AppStorage("lumo_has_completed_login") private var hasCompletedLogin: Bool = false

    private var shouldShowHome: Bool {
        session.user != nil && hasCompletedLogin
    }

    var body: some View {
        Group {
            if shouldShowHome {
                HomeView()
            } else if isActive {
                GetStartedView()
                    .transition(.opacity)
            } else {
                ZStack {
                    Color.black
                        .ignoresSafeArea()

                    VStack {
                        // TOP: Title + Car
                        VStack(spacing: 40) {
                            Text("Lumo")
                                .font(.system(size: 52,
                                              weight: .regular,
                                              design: .serif))
                                .foregroundColor(.white)

                            Image("speedCar")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 260)
                                .padding(.top, 10)
                        }
                        .padding(.top, 80)

                        Spacer()

                        // BOTTOM: Tagline + Button
                        VStack(spacing: 28) {
                            Text("Fast, smooth rides whenever\nyou need them.")
                                .font(.system(size: 17))
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)

                            Button(action: {
                                withAnimation(.easeOut(duration: 0.4)) {
                                    isActive = true
                                }
                            }) {
                                Text("Get started")
                                    .font(.system(size: 22,
                                                  weight: .semibold,
                                                  design: .serif))
                                    .foregroundColor(.black)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 64)
                                    .background(Color.white)
                                    .cornerRadius(32)
                            }
                            .padding(.horizontal, 40)
                            .shadow(color: Color.black.opacity(0.3),
                                    radius: 12, x: 0, y: 4)
                        }
                        .padding(.bottom, 40)
                    }
                }
            }
        }
        .onChange(of: shouldShowHome) { newValue in
            if newValue {
                isActive = false
            }
        }
    }
}

#Preview {
    SplashScreen()
}
