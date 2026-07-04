import SwiftUI

struct SplashScreen: View {
    @State private var isActive = false

    var body: some View {
        Group {
            if isActive {
                GetStartedView()          // 👈 go to sign-in screen
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

                            Image("speedCar")      // your car asset name
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
    }
}

#Preview {
    SplashScreen()
}
