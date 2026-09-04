import SwiftUI

struct OutgoingCallView: View {

    @ObservedObject private var riderCallManager = RiderCallManager.shared
    @ObservedObject private var agoraManager = AgoraCallManager.shared

    let driverName: String

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 110))
                    .foregroundStyle(.white.opacity(0.9))

                Text(driverName.isEmpty ? "Driver" : driverName)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.top, 24)

                Text(callStatusText)
                    .font(.system(size: 17))
                    .foregroundStyle(.white.opacity(0.65))
                    .padding(.top, 8)

                Spacer()

                HStack(spacing: 45) {
                    callControlButton(
                        icon: agoraManager.isMuted
                            ? "mic.slash.fill"
                            : "mic.fill",
                        title: agoraManager.isMuted
                            ? "Unmute"
                            : "Mute",
                        isActive: agoraManager.isMuted
                    ) {
                        riderCallManager.toggleMute()
                    }

                    callControlButton(
                        icon: agoraManager.isSpeakerEnabled
                            ? "speaker.wave.3.fill"
                            : "speaker.fill",
                        title: "Speaker",
                        isActive: agoraManager.isSpeakerEnabled
                    ) {
                        riderCallManager.toggleSpeaker()
                    }
                }

                Button {
                    Task {
                        await riderCallManager.endCurrentCall()
                    }
                } label: {
                    Image(systemName: "phone.down.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 72, height: 72)
                        .background(Color.red)
                        .clipShape(Circle())
                }
                .padding(.top, 42)

                Text("End")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.top, 10)
                    .padding(.bottom, 45)
            }
            .padding(.horizontal, 30)
        }
        .alert(
            "Call Error",
            isPresented: Binding(
                get: {
                    riderCallManager.errorMessage != nil ||
                    agoraManager.errorMessage != nil
                },
                set: { isPresented in
                    if !isPresented {
                        riderCallManager.clearError()
                    }
                }
            )
        ) {
            Button("OK") {
                riderCallManager.clearError()
            }
        } message: {
            Text(
                riderCallManager.errorMessage ??
                agoraManager.errorMessage ??
                "Something went wrong."
            )
        }
    }

    private var callStatusText: String {
        if agoraManager.remoteUserJoined {
            return "Connected"
        }

        if agoraManager.isInCall {
            return "Calling..."
        }

        if riderCallManager.isStartingCall {
            return "Starting call..."
        }

        return "Calling..."
    }

    private func callControlButton(
        icon: String,
        title: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 10) {
            Button(action: action) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(
                        isActive ? Color.black : Color.white
                    )
                    .frame(width: 64, height: 64)
                    .background(
                        isActive
                            ? Color.white
                            : Color.white.opacity(0.18)
                    )
                    .clipShape(Circle())
            }

            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
        }
    }
}

#Preview {
    OutgoingCallView(driverName: "Driver")
}
