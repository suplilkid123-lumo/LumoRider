import SwiftUI

struct LumoLaunchView: View {
    private enum Phase {
        case build
        case orbitalMotion
        case logoReveal
        case impact
        case release
        case finish
        case exit
    }

    @Binding var isPresented: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var phase: Phase = .build
    @State private var orbitTrim = 0.0
    @State private var orbitOpacity = 0.0
    @State private var orbitScale = 0.72
    @State private var outerRotation = 0.0
    @State private var innerRotation = 0.0
    @State private var orbitBrightness = 0.0
    @State private var atmosphereOpacity = 0.0
    @State private var logoOpacity = 0.0
    @State private var logoScale = 0.75
    @State private var logoOffset = 18.0
    @State private var logoGlow = 0.0
    @State private var pulseOpacity = 0.0
    @State private var pulseScale = 0.78
    @State private var screenOpacity = 1.0

    var body: some View {
        GeometryReader { proxy in
            let orbitSize = min(proxy.size.width * 0.86, 340)

            ZStack {
                Color.black
                    .ignoresSafeArea()

                RadialGradient(
                    colors: [
                        Color.white.opacity(0.13),
                        Color.white.opacity(0.045),
                        .clear
                    ],
                    center: .center,
                    startRadius: 4,
                    endRadius: orbitSize * 0.62
                )
                .frame(width: orbitSize * 1.18, height: orbitSize * 1.18)
                .opacity(atmosphereOpacity)
                .blur(radius: 10)

                LumoOrbitView(
                    trim: orbitTrim,
                    outerRotation: outerRotation,
                    innerRotation: innerRotation,
                    brightness: orbitBrightness
                )
                .frame(width: orbitSize, height: orbitSize)
                .scaleEffect(orbitScale)
                .opacity(orbitOpacity)

                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.3), lineWidth: 7)
                        .blur(radius: 9)

                    Circle()
                        .stroke(Color.white, lineWidth: 1.15)
                        .blur(radius: 0.2)
                }
                .frame(width: orbitSize * 0.57, height: orbitSize * 0.57)
                .scaleEffect(pulseScale)
                .opacity(pulseOpacity)

                logo
                    .opacity(logoOpacity)
                    .scaleEffect(logoScale)
                    .offset(y: logoOffset)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .opacity(screenOpacity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Jiylo")
        .accessibilityAddTraits(.isImage)
        .accessibilityHidden(phase == .exit)
        .task {
            await runAnimation()
        }
    }

    private var logo: some View {
        VStack(spacing: 14) {
            Text("Jiylo")
                .font(.system(size: 60, weight: .regular, design: .serif))
                .foregroundStyle(.white)

            Image("speedCar")
                .resizable()
                .scaledToFit()
                .frame(width: 240)
        }
        .shadow(color: Color.white.opacity(0.2 * logoGlow), radius: 12)
        .shadow(color: Color.white.opacity(0.1 * logoGlow), radius: 28)
    }

    @MainActor
    private func runAnimation() async {
        await Task.yield()

        if reduceMotion {
            await runReducedMotionAnimation()
            return
        }

        // Keep launch branding brief: the mounted app remains unavailable while
        // this overlay is visible, so the animation must not dominate launch.
        phase = .build
        withAnimation(.easeInOut(duration: 0.24)) {
            orbitTrim = 0.52
            orbitOpacity = 0.64
            orbitScale = 0.86
            orbitBrightness = 0.34
            atmosphereOpacity = 1
            outerRotation = 72
            innerRotation = -48
        }

        guard await pause(for: 0.12) else { return }

        phase = .orbitalMotion
        withAnimation(.easeInOut(duration: 0.42)) {
            orbitTrim = 0.94
            orbitOpacity = 0.94
            orbitScale = 1
            orbitBrightness = 0.82
            outerRotation = 430
            innerRotation = -315
        }

        guard await pause(for: 0.20) else { return }

        phase = .logoReveal
        withAnimation(.spring(duration: 0.38, bounce: 0.16)) {
            logoOpacity = 1
            logoScale = 1
            logoOffset = 0
            logoGlow = 0.5
        }

        guard await pause(for: 0.26) else { return }

        phase = .impact
        withAnimation(.easeInOut(duration: 0.16)) {
            logoScale = 1.018
            logoGlow = 1
            orbitTrim = 1
            orbitOpacity = 1
            orbitScale = 0.87
            orbitBrightness = 1
            outerRotation = 555
            innerRotation = -430
            atmosphereOpacity = 1
            pulseOpacity = 0.86
            pulseScale = 1.08
        }

        guard await pause(for: 0.10) else { return }

        withAnimation(.easeOut(duration: 0.16)) {
            logoScale = 1
            pulseOpacity = 0
            pulseScale = 1.48
            atmosphereOpacity = 0.7
        }

        guard await pause(for: 0.12) else { return }

        phase = .release
        withAnimation(.easeInOut(duration: 0.24)) {
            orbitOpacity = 0
            orbitScale = 1.58
            orbitBrightness = 0.58
            outerRotation = 690
            innerRotation = -555
            atmosphereOpacity = 0.3
            logoGlow = 0.36
        }

        guard await pause(for: 0.18) else { return }

        phase = .finish
        withAnimation(.easeOut(duration: 0.05)) {
            atmosphereOpacity = 0.16
            logoGlow = 0.22
        }

        guard await pause(for: 0.04) else { return }

        phase = .exit
        withAnimation(.easeInOut(duration: 0.20)) {
            screenOpacity = 0
            logoScale = 0.99
            logoGlow = 0
        }

        guard await pause(for: 0.20) else { return }
        isPresented = false
    }

    @MainActor
    private func runReducedMotionAnimation() async {
        phase = .build
        orbitScale = 1
        logoScale = 1
        logoOffset = 0

        // A static, low-motion ring replaces the rotating orbital choreography.
        withAnimation(.easeOut(duration: 0.40)) {
            orbitTrim = 0.76
            orbitOpacity = 0.56
            orbitBrightness = 0.45
            atmosphereOpacity = 0.5
        }

        guard await pause(for: 0.35) else { return }

        phase = .logoReveal
        withAnimation(.easeInOut(duration: 0.40)) {
            logoOpacity = 1
            logoGlow = 0.32
        }

        guard await pause(for: 0.43) else { return }

        phase = .impact
        withAnimation(.easeOut(duration: 0.18)) {
            pulseOpacity = 0.42
            pulseScale = 1.06
            logoGlow = 0.56
        }

        guard await pause(for: 0.18) else { return }

        phase = .release
        withAnimation(.easeInOut(duration: 0.28)) {
            pulseOpacity = 0
            pulseScale = 1.3
            orbitOpacity = 0
            atmosphereOpacity = 0.16
            logoGlow = 0.2
        }

        guard await pause(for: 0.42) else { return }

        phase = .exit
        withAnimation(.easeInOut(duration: 0.42)) {
            screenOpacity = 0
            logoGlow = 0
        }

        guard await pause(for: 0.42) else { return }
        isPresented = false
    }

    @MainActor
    private func pause(for seconds: Double) async -> Bool {
        do {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return !Task.isCancelled
        } catch {
            return false
        }
    }
}

private struct LumoOrbitView: View {
    let trim: Double
    let outerRotation: Double
    let innerRotation: Double
    let brightness: Double

    var body: some View {
        ZStack {
            outerOrbit
            secondaryOrbit
            precisionRing
        }
        .compositingGroup()
    }

    private var outerOrbit: some View {
        ZStack {
            Circle()
                .trim(from: 0.03, to: 0.03 + (0.68 * trim))
                .stroke(
                    AngularGradient(
                        colors: [
                            .clear,
                            Color.white.opacity(0.18),
                            Color.white.opacity(0.36 + (0.44 * brightness)),
                            Color.white.opacity(0.2),
                            .clear
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 1.35, lineCap: .round)
                )
                .blur(radius: 5)
                .opacity(0.32 + (0.2 * brightness))

            Circle()
                .trim(from: 0.03, to: 0.03 + (0.68 * trim))
                .stroke(
                    AngularGradient(
                        colors: [
                            .clear,
                            Color.white.opacity(0.24),
                            Color.white.opacity(0.72 + (0.28 * brightness)),
                            Color.white.opacity(0.32),
                            .clear
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 1.25, lineCap: .round)
                )

            Circle()
                .trim(from: 0.76, to: 0.76 + (0.15 * trim))
                .stroke(
                    Color.white.opacity(0.48 + (0.38 * brightness)),
                    style: StrokeStyle(lineWidth: 0.7, lineCap: .round)
                )
        }
        .rotationEffect(.degrees(outerRotation - 90))
        .scaleEffect(x: 1, y: 0.82)
        .rotationEffect(.degrees(-9))
    }

    private var secondaryOrbit: some View {
        ZStack {
            Circle()
                .trim(from: 0.18, to: 0.18 + (0.46 * trim))
                .stroke(
                    AngularGradient(
                        colors: [
                            .clear,
                            Color.white.opacity(0.16),
                            Color.white.opacity(0.52 + (0.4 * brightness)),
                            .clear
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 0.9, lineCap: .round)
                )

            Circle()
                .trim(from: 0.7, to: 0.7 + (0.12 * trim))
                .stroke(
                    Color.white.opacity(0.24 + (0.34 * brightness)),
                    style: StrokeStyle(lineWidth: 1.8, lineCap: .round)
                )
                .blur(radius: 1.2)
        }
        .padding(34)
        .rotationEffect(.degrees(innerRotation + 35))
        .scaleEffect(x: 1, y: 0.76)
        .rotationEffect(.degrees(14))
    }

    private var precisionRing: some View {
        Circle()
            .trim(from: 0.08, to: 0.08 + (0.32 * trim))
            .stroke(
                Color.white.opacity(0.12 + (0.12 * brightness)),
                style: StrokeStyle(
                    lineWidth: 0.55,
                    lineCap: .round,
                    dash: [2, 7]
                )
            )
            .padding(63)
            .rotationEffect(.degrees((outerRotation * 0.42) - 20))
            .scaleEffect(x: 1, y: 0.88)
    }
}

#Preview {
    LumoLaunchView(isPresented: .constant(true))
}
