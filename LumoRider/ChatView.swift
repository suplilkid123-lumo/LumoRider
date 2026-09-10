// ChatView.swift
import SwiftUI
import PhotosUI
import UIKit
import Combine

struct ChatView: View {
    let rideId: UUID
    let senderId: String
    let senderRole: String   // "rider" or "driver"

    @StateObject private var chat = ChatService()

    @State private var text: String = ""

    @State private var photoItem: PhotosPickerItem? = nil
    @State private var isUploadingPhoto: Bool = false

    @State private var showPhotoError: Bool = false
    @State private var photoErrorMessage: String = ""

    var body: some View {
        VStack {
            Text(rideId.uuidString)
                .font(.caption)
                .foregroundColor(.gray)
                .padding(.top, 6)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(chat.rows) { msg in
                            chatBubble(msg)
                                .id(msg.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: chat.rows.count) { _ in
                    if let last = chat.rows.last {
                        proxy.scrollTo(last.id, anchor: .bottom)

                        // If a new incoming message arrives while chat is open, mark it read (Uber/Lyft behavior)
                        let isIncoming = (last.sender_role ?? "").lowercased() != senderRole.lowercased()
                        if isIncoming && last.read != true {
                            Task { @MainActor in
                                await chat.markIncomingMessagesRead(rideId: rideId)
                            }
                        }
                    }
                }
            }

            HStack(spacing: 10) {
                PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                    ZStack {
                        Circle()
                            .fill(Color(UIColor.systemGray5))
                            .frame(width: 36, height: 36)

                        if isUploadingPhoto {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Image(systemName: "plus")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.black)
                        }
                    }
                }
                .disabled(isUploadingPhoto)

                TextField("Message...", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isUploadingPhoto)

                Button("Send") {
                    let bodyText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !bodyText.isEmpty else { return }

                    Task { @MainActor in
                        await chat.sendMessage(
                            rideId: rideId,
                            senderId: senderId,
                            senderRole: senderRole,
                            body: bodyText
                        )
                        text = ""
                    }
                }
                .disabled(isUploadingPhoto)
            }
            .padding()
            .alert("Photo", isPresented: $showPhotoError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(photoErrorMessage)
            }
            .onChange(of: photoItem) { newItem in
                guard let newItem else { return }
                isUploadingPhoto = true

                Task {
                    defer {
                        isUploadingPhoto = false
                        photoItem = nil
                    }

                    guard let uiImage = await loadUIImage(from: newItem) else {
                        photoErrorMessage = "Couldn’t read the selected photo."
                        showPhotoError = true
                        return
                    }

                    await chat.sendImageMessage(
                        rideId: rideId,
                        senderId: senderId,
                        senderRole: senderRole,
                        image: uiImage
                    )
                }
            }
        }
        .navigationTitle("Chat")
        .onAppear {
            LumoChatPresence.setOpen(true, rideId: rideId)
            // Ensure unread logic works correctly (ChatService expects the current viewer role)
            chat.viewerRole = senderRole.lowercased()

            chat.start(rideId: rideId, userID: senderId, every: 1.0)
            Task { @MainActor in
                // When the chat is opened, immediately mark incoming messages as read
                await chat.markIncomingMessagesRead(rideId: rideId)
            }
        }
        .onDisappear {
            LumoChatPresence.setOpen(false, rideId: rideId)
            chat.stopPolling()
        }
    }

    // MARK: - UI

    @ViewBuilder
    private func chatBubble(_ msg: ChatRow) -> some View {
        let isMe = (msg.sender_role ?? "").lowercased() == senderRole.lowercased()
        let bodyText = (msg.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let imageURLString: String = {
            let storedPath = (msg.image_url ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !storedPath.isEmpty { return storedPath }
            guard (msg.type ?? "").lowercased() == "image" else { return "" }
            return bodyText
        }()

        HStack {
            if isMe { Spacer(minLength: 40) }

            VStack(alignment: .leading, spacing: 6) {
                if !imageURLString.isEmpty {
                    SignedChatImage(attachment: imageURLString, rideId: rideId, chat: chat)
                }

                if !bodyText.isEmpty && (msg.type ?? "").lowercased() != "image" {
                    Text(bodyText)
                        .foregroundColor(isMe ? .white : .black)
                }
            }
            .padding(.horizontal, imageURLString.isEmpty ? 14 : 10)
            .padding(.vertical, 10)
            .background(isMe ? Color.blue : Color(UIColor.systemGray5))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .frame(maxWidth: 280, alignment: isMe ? .trailing : .leading)

            if !isMe { Spacer(minLength: 40) }
        }
        .padding(.horizontal, 4)
    }

    private func loadUIImage(from item: PhotosPickerItem) async -> UIImage? {
        if let data = try? await item.loadTransferable(type: Data.self),
           let img = UIImage(data: data) {
            return img
        }
        return nil
    }
}

private struct SignedChatImage: View {
    let attachment: String
    let rideId: UUID
    let chat: ChatService

    @State private var signedImage: SignedChatImageURL?
    @State private var refreshID = UUID()
    @State private var refreshedAfterFailure = false

    var body: some View {
        Group {
            if let signedImage {
                AsyncImage(url: signedImage.url) { phase in
                    switch phase {
                    case .empty:
                        placeholder
                    case .success(let image):
                        image.resizable().scaledToFill()
                            .frame(width: 220, height: 220)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    case .failure:
                        placeholder
                            .onAppear { refreshAfterImageFailure() }
                    @unknown default:
                        EmptyView()
                    }
                }
            } else {
                placeholder
            }
        }
        .task(id: refreshID) { await resolveSignedURL() }
        .onChange(of: attachment) { _ in
            signedImage = nil
            refreshedAfterFailure = false
            refreshID = UUID()
        }
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16).fill(Color(UIColor.systemGray5))
            ProgressView()
        }
        .frame(width: 220, height: 220)
    }

    private func resolveSignedURL() async {
        guard let resolved = try? await chat.signedImageURL(for: attachment, rideId: rideId) else { return }
        signedImage = resolved
        let refreshDelay = max(1, resolved.expiresAt.timeIntervalSinceNow - 15)
        try? await Task.sleep(for: .seconds(refreshDelay))
        guard !Task.isCancelled, signedImage == resolved else { return }
        refreshID = UUID()
    }

    private func refreshAfterImageFailure() {
        guard !refreshedAfterFailure else { return }
        refreshedAfterFailure = true
        signedImage = nil
        refreshID = UUID()
    }
}
