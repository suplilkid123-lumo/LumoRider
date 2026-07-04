// ChatView.swift
import SwiftUI
import PhotosUI
import UIKit
import Combine

// MARK: - Case A: Track whether ChatView is currently visible
enum ChatPresence {
    static var isChatOpen: Bool = false
}

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
            ChatPresence.isChatOpen = true
            // Ensure unread logic works correctly (ChatService expects the current viewer role)
            chat.viewerRole = senderRole.lowercased()

            Task { @MainActor in
                await chat.loadMessages(rideId: rideId)
                // When the chat is opened, immediately mark incoming messages as read
                await chat.markIncomingMessagesRead(rideId: rideId)
                chat.startPolling(rideId: rideId, every: 1.0)
            }
        }
        .onDisappear {
            ChatPresence.isChatOpen = false
            chat.stopPolling()
        }
    }

    // MARK: - UI

    @ViewBuilder
    private func chatBubble(_ msg: ChatRow) -> some View {
        let isMe = (msg.sender_role ?? "").lowercased() == senderRole.lowercased()
        let bodyText = (msg.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let imageURLString = (msg.image_url ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        HStack {
            if isMe { Spacer(minLength: 40) }

            VStack(alignment: .leading, spacing: 6) {
                if !imageURLString.isEmpty, let url = URL(string: imageURLString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            ZStack {
                                RoundedRectangle(cornerRadius: 16).fill(Color(UIColor.systemGray5))
                                ProgressView()
                            }
                            .frame(width: 220, height: 220)
                        case .success(let image):
                            image.resizable().scaledToFill()
                                .frame(width: 220, height: 220)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                        case .failure:
                            ZStack {
                                RoundedRectangle(cornerRadius: 16).fill(Color(UIColor.systemGray5))
                                Image(systemName: "photo")
                                    .font(.system(size: 28, weight: .semibold))
                                    .foregroundColor(.black.opacity(0.6))
                            }
                            .frame(width: 220, height: 220)
                        @unknown default:
                            EmptyView()
                        }
                    }
                }

                if !bodyText.isEmpty {
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
