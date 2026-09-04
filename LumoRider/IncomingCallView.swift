import SwiftUI

struct IncomingCallView:View {
    let call:CallSession
    @ObservedObject private var manager=RiderCallManager.shared
    var body:some View {
        VStack(spacing:24) {
            Spacer(); Image(systemName:"phone.arrow.down.left.fill").font(.system(size:72)).foregroundStyle(.green)
            Text("Driver calling").font(.largeTitle.bold()); Text(call.otherPartyName).font(.title2)
            Text("Private in-app voice call").foregroundStyle(.secondary); Spacer()
            HStack(spacing:40) {
                Button { Task { await manager.declineIncoming() } } label:{ Label("Decline",systemImage:"phone.down.fill") }.buttonStyle(.bordered).tint(.red)
                Button { Task { await manager.acceptIncoming() } } label:{ Label("Accept",systemImage:"phone.fill") }.buttonStyle(.borderedProminent).tint(.green)
            }.disabled(manager.isStartingCall)
            Spacer()
        }.padding().interactiveDismissDisabled()
    }
}
