import Foundation
import Combine
import AVFoundation

@MainActor
final class RiderCallAudioFeedback {
    static let shared = RiderCallAudioFeedback()
    enum Tone { case outgoingRingback, incomingRingtone }

    private var player: AVAudioPlayer?
    private var playingTone: Tone?
    private init() {}

    func play(_ tone: Tone) {
        if playingTone == tone, player?.isPlaying == true { return }
        stop(deactivateAudioSession: false)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetoothHFP, .defaultToSpeaker])
            try session.setActive(true)
            let audio = try AVAudioPlayer(data: Self.wavData(for: tone))
            audio.numberOfLoops = -1
            audio.volume = tone == .incomingRingtone ? 1 : 0.55
            audio.prepareToPlay(); audio.play()
            player = audio; playingTone = tone
        } catch {
            player = nil; playingTone = nil
        }
    }

    func stop(deactivateAudioSession: Bool) {
        player?.stop(); player = nil; playingTone = nil
        if deactivateAudioSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    private static func wavData(for tone: Tone) -> Data {
        let rate = 16_000
        let duration = tone == .incomingRingtone ? 2.8 : 3.0
        let count = Int(Double(rate) * duration)
        var samples = Data(capacity: count * 2)
        for index in 0..<count {
            let time = Double(index) / Double(rate)
            let wave: Double
            switch tone {
            case .outgoingRingback:
                wave = time < 0.8
                    ? (sin(2 * .pi * 440 * time) + sin(2 * .pi * 480 * time)) * 0.18
                    : 0
            case .incomingRingtone:
                // A bright three-note chime, intentionally unlike telephone ringback.
                let notes: [(start: Double, end: Double, frequency: Double)] = [
                    (0.00, 0.24, 880), (0.32, 0.56, 1_046.5), (0.64, 1.04, 1_318.5)
                ]
                if let note = notes.first(where: { time >= $0.start && time < $0.end }) {
                    let position = time - note.start
                    let length = note.end - note.start
                    let envelope = min(1, position / 0.02, (length - position) / 0.04)
                    wave = sin(2 * .pi * note.frequency * position) * 0.32 * max(0, envelope)
                } else {
                    wave = 0
                }
            }
            var sample = Int16(max(-1, min(1, wave)) * Double(Int16.max)).littleEndian
            withUnsafeBytes(of: &sample) { samples.append(contentsOf: $0) }
        }
        var data = Data()
        func append(_ value: UInt32) { var value = value.littleEndian; withUnsafeBytes(of: &value) { data.append(contentsOf: $0) } }
        func append(_ value: UInt16) { var value = value.littleEndian; withUnsafeBytes(of: &value) { data.append(contentsOf: $0) } }
        data.append(Data("RIFF".utf8)); append(UInt32(36 + samples.count)); data.append(Data("WAVEfmt ".utf8))
        append(UInt32(16)); append(UInt16(1)); append(UInt16(1)); append(UInt32(rate)); append(UInt32(rate * 2))
        append(UInt16(2)); append(UInt16(16)); data.append(Data("data".utf8)); append(UInt32(samples.count)); data.append(samples)
        return data
    }
}

@MainActor
final class RiderCallManager: ObservableObject {
    static let shared = RiderCallManager()
    @Published private(set) var currentCall: CallSession?
    @Published private(set) var incomingCall: CallSession?
    @Published private(set) var isStartingCall = false
    @Published private(set) var errorMessage: String?
    private let callSessionService=CallSessionService.shared
    private let tokenService=AgoraTokenService.shared
    private let agoraManager=AgoraCallManager.shared
    private var requestID:UUID?
    private var monitorTask:Task<Void,Never>?
    private var monitoredRideID:UUID?
    private init() {}

    func monitor(rideId:UUID?) {
        guard rideId != monitoredRideID else { return }
        monitorTask?.cancel(); monitoredRideID=rideId; incomingCall=nil
        RiderCallAudioFeedback.shared.stop(deactivateAudioSession: currentCall == nil)
        guard let rideId else { agoraManager.leaveCall(); currentCall=nil; return }
        monitorTask=Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh(rideId:rideId)
                try? await Task.sleep(nanoseconds:3_000_000_000)
            }
        }
    }

    func startCall(rideId:UUID,driverId:String) async {
        guard currentCall==nil,incomingCall==nil,!isStartingCall else { return }
        guard !driverId.isEmpty else { errorMessage="No Driver is assigned to this ride."; return }
        isStartingCall=true; errorMessage=nil
        let stableID=requestID ?? UUID(); requestID=stableID
        var createdSession: CallSession?
        do {
            let session=try await callSessionService.createRiderCall(rideId:rideId,requestId:stableID)
            createdSession=session; currentCall=session
            if session.isCaller, session.status == .ringing {
                RiderCallAudioFeedback.shared.play(.outgoingRingback)
            }
            let token=try await tokenService.fetchToken(callId:session.id)
            AgoraCallManager.shared.configure(appId:token.appId)
            agoraManager.joinCall(token:token.token,channelName:token.channelName,uid:token.uid)
            requestID=nil
        } catch {
            RiderCallAudioFeedback.shared.stop(deactivateAudioSession: true); currentCall=nil
            if let createdSession { try? await callSessionService.endCall(callId:createdSession.id) }
            errorMessage="Call not started. \(error.localizedDescription) You can still message your Driver."
        }
        isStartingCall=false
    }

    func acceptIncoming() async {
        guard let incomingCall,!isStartingCall else { return }
        RiderCallAudioFeedback.shared.stop(deactivateAudioSession: true)
        isStartingCall=true; errorMessage=nil
        do {
            let accepted=try await callSessionService.acceptCall(callId:incomingCall.id)
            let token=try await tokenService.fetchToken(callId:accepted.id)
            AgoraCallManager.shared.configure(appId:token.appId)
            agoraManager.joinCall(token:token.token,channelName:token.channelName,uid:token.uid)
            self.incomingCall=nil; currentCall=accepted
        } catch { errorMessage="Call could not be accepted. \(error.localizedDescription)" }
        isStartingCall=false
    }

    func declineIncoming() async {
        guard let incomingCall else { return }
        RiderCallAudioFeedback.shared.stop(deactivateAudioSession: true)
        do { try await callSessionService.declineCall(callId:incomingCall.id) }
        catch { errorMessage="Jiylo could not confirm the decline. \(error.localizedDescription)" }
        self.incomingCall=nil
    }

    func endCurrentCall() async {
        RiderCallAudioFeedback.shared.stop(deactivateAudioSession: false)
        agoraManager.leaveCall()
        if let currentCall { try? await callSessionService.endCall(callId:currentCall.id) }
        currentCall=nil
    }
    func cancelOutgoingCall() async { await endCurrentCall() }
    func refreshCurrentCall() async { if let rideId=monitoredRideID { await refresh(rideId:rideId) } }
    func toggleMute(){ agoraManager.toggleMute() }
    func toggleSpeaker(){ agoraManager.toggleSpeaker() }
    func clearError(){ errorMessage=nil }

    private func refresh(rideId:UUID) async {
        do {
            if let currentCall {
                let latest=try await callSessionService.fetchCallSession(callId:currentCall.id)
                if [.declined,.ended,.missed,.failed].contains(latest.status) || latest.expiresAt <= Date() {
                    RiderCallAudioFeedback.shared.stop(deactivateAudioSession: false)
                    agoraManager.leaveCall(); self.currentCall=nil
                } else {
                    self.currentCall=latest
                    if latest.isCaller, latest.status == .ringing, !agoraManager.remoteUserJoined {
                        RiderCallAudioFeedback.shared.play(.outgoingRingback)
                    } else {
                        RiderCallAudioFeedback.shared.stop(deactivateAudioSession: false)
                    }
                }
            } else if let incomingCall {
                let latest=try await callSessionService.fetchCallSession(callId:incomingCall.id)
                if !latest.isCaller, latest.status == .ringing, latest.expiresAt > Date() {
                    self.incomingCall=latest
                    RiderCallAudioFeedback.shared.play(.incomingRingtone)
                } else {
                    self.incomingCall=nil
                    RiderCallAudioFeedback.shared.stop(deactivateAudioSession: true)
                }
            } else if let call=try await callSessionService.fetchIncomingCall(rideId:rideId), !call.isCaller {
                incomingCall=call
                RiderCallAudioFeedback.shared.play(.incomingRingtone)
            }
        } catch {
            if let incomingCall, incomingCall.expiresAt <= Date() {
                self.incomingCall=nil
                RiderCallAudioFeedback.shared.stop(deactivateAudioSession: true)
            }
            // Network loss never mutates the ride or fabricates call state.
        }
    }
}
