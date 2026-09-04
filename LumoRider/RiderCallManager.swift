import Foundation
import Combine

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
        do {
            let session=try await callSessionService.createRiderCall(rideId:rideId,requestId:stableID)
            let token=try await tokenService.fetchToken(callId:session.id)
            AgoraCallManager.shared.configure(appId:token.appId)
            agoraManager.joinCall(token:token.token,channelName:token.channelName,uid:token.uid)
            currentCall=session; requestID=nil
        } catch { errorMessage="Call not started. \(error.localizedDescription) You can still message your Driver." }
        isStartingCall=false
    }

    func acceptIncoming() async {
        guard let incomingCall,!isStartingCall else { return }
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
        do { try await callSessionService.declineCall(callId:incomingCall.id) }
        catch { errorMessage="Lumo could not confirm the decline. \(error.localizedDescription)" }
        self.incomingCall=nil
    }

    func endCurrentCall() async {
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
                if [.declined,.ended,.missed].contains(latest.status) { agoraManager.leaveCall(); self.currentCall=nil }
                else { self.currentCall=latest }
            } else if incomingCall==nil {
                incomingCall=try await callSessionService.fetchIncomingCall(rideId:rideId)
            }
        } catch { /* Network loss never mutates the ride or fabricates call state. */ }
    }
}
