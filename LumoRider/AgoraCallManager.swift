import Foundation
import AVFoundation
import AgoraRtcKit
import Combine

final class AgoraCallManager: NSObject, ObservableObject {

    static let shared = AgoraCallManager()

    @Published private(set) var isInCall = false
    @Published private(set) var isMuted = false
    @Published private(set) var isSpeakerEnabled = true
    @Published private(set) var remoteUserJoined = false
    @Published private(set) var errorMessage: String?

    private var agoraEngine: AgoraRtcEngineKit?

    private override init() {
        super.init()
    }

    // MARK: - Setup

    func configure(appId: String) {
        guard agoraEngine == nil else { return }

        let config = AgoraRtcEngineConfig()
        config.appId = appId
        config.channelProfile = .communication

        agoraEngine = AgoraRtcEngineKit.sharedEngine(
            with: config,
            delegate: self
        )

        agoraEngine?.enableAudio()
        agoraEngine?.setAudioProfile(
            .default,
            scenario: .default
        )
    }

    // MARK: - Microphone Permission

    func requestMicrophonePermission(
        completion: @escaping (Bool) -> Void
    ) {
        AVAudioApplication.requestRecordPermission { granted in
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }

    // MARK: - Join Call

    func joinCall(
        token: String,
        channelName: String,
        uid: UInt = 0
    ) {
        guard let agoraEngine else {
            setError("Agora has not been configured.")
            return
        }

        requestMicrophonePermission { [weak self] granted in
            guard let self else { return }

            guard granted else {
                self.setError("Microphone permission was denied.")
                return
            }

            self.activateAudioSession()

            let options = AgoraRtcChannelMediaOptions()
            options.clientRoleType = .broadcaster
            options.channelProfile = .communication
            options.publishMicrophoneTrack = true
            options.autoSubscribeAudio = true

            let result = agoraEngine.joinChannel(
                byToken: token,
                channelId: channelName,
                uid: uid,
                mediaOptions: options
            )

            if result != 0 {
                self.setError("Could not join the call. Agora error: \(result)")
            }
        }
    }

    // MARK: - Leave Call

    func leaveCall() {
        agoraEngine?.leaveChannel(nil)

        DispatchQueue.main.async {
            RiderCallAudioFeedback.shared.stop(deactivateAudioSession: false)
            self.isInCall = false
            self.isMuted = false
            self.remoteUserJoined = false
        }

        deactivateAudioSession()
    }

    // MARK: - Mute

    func toggleMute() {
        isMuted.toggle()
        agoraEngine?.muteLocalAudioStream(isMuted)
    }

    // MARK: - Speaker

    func toggleSpeaker() {
        isSpeakerEnabled.toggle()
        agoraEngine?.setEnableSpeakerphone(isSpeakerEnabled)
    }

    func setSpeakerEnabled(_ enabled: Bool) {
        isSpeakerEnabled = enabled
        agoraEngine?.setEnableSpeakerphone(enabled)
    }

    // MARK: - Cleanup

    func destroy() {
        leaveCall()
        AgoraRtcEngineKit.destroy()
        agoraEngine = nil
    }

    // MARK: - Audio Session

    private func activateAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()

            try session.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [
                    .allowBluetooth,
                    .allowBluetoothA2DP,
                    .defaultToSpeaker
                ]
            )

            try session.setActive(
                true,
                options: .notifyOthersOnDeactivation
            )

            agoraEngine?.setEnableSpeakerphone(true)

            DispatchQueue.main.async {
                self.isSpeakerEnabled = true
            }
        } catch {
            setError("Could not activate audio: \(error.localizedDescription)")
        }
    }

    private func deactivateAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(
                false,
                options: .notifyOthersOnDeactivation
            )
        } catch {
            print("Audio session cleanup error: \(error.localizedDescription)")
        }
    }

    private func setError(_ message: String) {
        DispatchQueue.main.async {
            RiderCallAudioFeedback.shared.stop(deactivateAudioSession: !self.isInCall)
            self.errorMessage = message
        }
    }
}

// MARK: - Agora Delegate

extension AgoraCallManager: AgoraRtcEngineDelegate {

    func rtcEngine(
        _ engine: AgoraRtcEngineKit,
        didJoinChannel channel: String,
        withUid uid: UInt,
        elapsed: Int
    ) {
        DispatchQueue.main.async {
            self.isInCall = true
            self.errorMessage = nil
        }
    }

    func rtcEngine(
        _ engine: AgoraRtcEngineKit,
        remoteUserDidJoin uid: UInt,
        elapsed: Int
    ) {
        DispatchQueue.main.async {
            RiderCallAudioFeedback.shared.stop(deactivateAudioSession: false)
            self.remoteUserJoined = true
        }
    }

    func rtcEngine(
        _ engine: AgoraRtcEngineKit,
        didOfflineOfUid uid: UInt,
        reason: AgoraUserOfflineReason
    ) {
        DispatchQueue.main.async {
            self.remoteUserJoined = false
        }
    }

    func rtcEngine(
        _ engine: AgoraRtcEngineKit,
        didOccurError errorCode: AgoraErrorCode
    ) {
        setError("Agora error: \(errorCode.rawValue)")
    }
}
