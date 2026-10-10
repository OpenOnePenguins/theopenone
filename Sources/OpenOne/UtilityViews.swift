import SwiftUI
import AppKit
import CoreImage

struct UtilityHeader: View {
    let title: String
    var close: () -> Void
    var body: some View {
        HStack {
            Text(title).font(.system(size: 17, weight: .semibold))
            Spacer()
            Button(action: close) { Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)).frame(width: 26, height: 26) }
                .buttonStyle(.plain).accessibilityLabel("Close \(title.lowercased())")
        }
    }
}
struct NotesView: View {
    @ObservedObject var utilities: Utilities
    var close: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            UtilityHeader(title: "Notes", close: close)
            Text(utilities.error ?? (utilities.notesSaved ? "Changes saved automatically" : "Saving…"))
                .font(.system(size: 11)).foregroundStyle(utilities.error == nil ? .secondary : Color.orange)
            TextEditor(text: Binding(get: { utilities.notes }, set: { utilities.updateNotes($0) }))
                .font(.system(size: 14)).scrollContentBackground(.hidden)
                .padding(8).background(.black.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityLabel("Working memory notes")
            Toggle("Include these notes in managed agent requests", isOn: $utilities.includeNotes)
                .font(.system(size: 11)).onChange(of: utilities.includeNotes) { _ in utilities.saveSettings() }
            Text("The first 16,000 characters accompany requests you send from Open One. Existing external sessions are unchanged.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }.padding(20).onDisappear { utilities.saveNotes() }
    }
}
struct FeedbackView: View {
    @ObservedObject var utilities: Utilities
    var close: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            UtilityHeader(title: "Send feedback", close: close)
            Text("What happened? What did you expect?").font(.system(size: 12)).foregroundStyle(.secondary)
            TextEditor(text: $utilities.feedback).font(.system(size: 14)).scrollContentBackground(.hidden)
                .padding(8).background(.black.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityLabel("Feedback message")
                .onChange(of: utilities.feedback) { _ in utilities.saveFeedback() }
            TextField("Email address or GitHub issues URL", text: $utilities.feedbackDestination).textFieldStyle(.roundedBorder)
                .accessibilityLabel("Feedback destination").onChange(of: utilities.feedbackDestination) { _ in utilities.saveSettings() }
            Text("Your message, app version and macOS version are included. Conversations and credentials are excluded. Review the draft before sending.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            if let error = utilities.error { Text(error).font(.system(size: 11)).foregroundStyle(.orange) }
            HStack {
                Button("Export report…") { utilities.exportFeedback() }
                Button("Copy report") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(utilities.feedbackReport(), forType: .string) }
                Spacer()
                Button("Open draft") { utilities.openFeedbackDraft() }.buttonStyle(.borderedProminent)
                    .disabled(utilities.feedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || utilities.feedbackDestination.isEmpty)
            }.font(.system(size: 12))
        }.padding(20)
    }
}
struct UsageView: View {
    @ObservedObject var utilities: Utilities
    var close: () -> Void
    @State private var showClaudeSetup = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            UtilityHeader(title: "Usage", close: close)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(["Claude", "Codex"], id: \.self) { provider in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                ProviderLogo(provider: provider, size: 18)
                                Text(provider).font(.system(size: 14, weight: .semibold)); Spacer()
                                if let plan = utilities.quotas.first(where: { $0.provider == provider })?.windows.first?.plan { Text(plan.capitalized).font(.system(size: 11)).foregroundStyle(.secondary) }
                            }
                            if let quota = utilities.quotas.first(where: { $0.provider == provider }), !quota.windows.isEmpty {
                                ForEach(quota.windows) { window in
                                    VStack(spacing: 5) {
                                        HStack {
                                            Text(window.bucket == "codex" || window.bucket == "Claude" ? window.label : "\(window.bucket) · \(window.label)")
                                            Spacer()
                                            Text("\(Int(window.remaining))% left\(resetText(window.resetsAt))").foregroundStyle(.secondary)
                                        }.font(.system(size: 11))
                                        ProgressView(value: window.remaining, total: 100).tint(window.remaining < 15 ? .orange : .white)
                                    }
                                }
                                Text("Updated \(Date(timeIntervalSince1970: quota.capturedAt), style: .relative) ago")
                                    .font(.system(size: 10)).foregroundStyle(Date().timeIntervalSince1970 - quota.capturedAt > 300 ? Color.orange : Color.gray)
                            } else {
                                Text(provider == "Claude" ? "Connect Claude Code’s quota feed to see your limits here." : "No quota data yet.")
                                    .font(.system(size: 12)).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if let issue = utilities.usageError { Text(issue).font(.system(size: 11)).foregroundStyle(.orange) }
                    DisclosureGroup("Connect Claude usage", isExpanded: $showClaudeSetup) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Claude exposes plan limits through its status line. Use this command as a status-line command, or pipe the same JSON to it from your existing status-line script. Your current configuration is left intact.")
                            HStack {
                                Button("Connect Claude usage") { utilities.configureClaudeUsage() }.disabled(utilities.configuringClaude)
                                Button("Restore previous setup") { utilities.configureClaudeUsage(restore: true) }.disabled(utilities.configuringClaude)
                            }
                            Text("Connect adds a local quota reader to Claude’s user settings and preserves your existing status-line command. Restore puts the previous setting back.")
                            if let message = utilities.claudeSetupMessage { Text(message).foregroundStyle(.secondary) }
                            Text(utilities.claudeCaptureCommand).font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                            Button("Copy integration command") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(utilities.claudeCaptureCommand, forType: .string) }
                            Link("Claude status-line setup", destination: URL(string: "https://code.claude.com/docs/en/statusline")!)
                        }.font(.system(size: 11)).padding(.top, 8)
                    }.font(.system(size: 12))
                }
            }
            HStack {
                Text("Provider-reported limits; missing data is never shown as 0% used.").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Button(utilities.refreshingUsage ? "Refreshing…" : "Refresh") { utilities.refreshUsage() }.disabled(utilities.refreshingUsage)
            }
        }.padding(20).onAppear { utilities.refreshUsage() }
    }
    private func resetText(_ epoch: Double?) -> String {
        guard let epoch else { return "" }
        let seconds = max(0, epoch - Date().timeIntervalSince1970)
        if seconds < 60 { return " · resets now" }
        if seconds >= 86400 { return " · \(Int(seconds / 86400))d \(Int(seconds.truncatingRemainder(dividingBy: 86400) / 3600))h" }
        if seconds >= 3600 { return " · \(Int(seconds / 3600))h \(Int(seconds.truncatingRemainder(dividingBy: 3600) / 60))m" }
        return " · \(Int(seconds / 60))m"
    }
}
struct RemoteAccessView: View {
    @ObservedObject var utilities: Utilities
    var close: () -> Void
    @State private var lanAddress = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            UtilityHeader(title: "Connect your phone", close: close)
            VStack {
                Label("Local Wi-Fi only", systemImage: "wifi").font(.system(size: 12)).foregroundStyle(.secondary)
                phoneConnection
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Label("Your Mac conversations, on your phone", systemImage: "iphone").font(.system(size: 14, weight: .semibold))
                    Text("1. Put your iPhone and this Mac on the same Wi-Fi.\n2. Click Connect phone, then scan the QR with Camera → Safari.\n3. Pick the same conversation you see on this Mac.")
                        .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Connects directly over your local network. Keep the full link private: it allows reading tracked conversations and sending replies. Keep this Mac awake. Stop & revoke links ends access.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        if utilities.lanAddresses.count > 1 {
                            Picker("Mac LAN address", selection: $lanAddress) { ForEach(utilities.lanAddresses, id: \.self) { Text($0).tag($0) } }
                                .disabled(utilities.remoteRunning).onAppear { if lanAddress.isEmpty { lanAddress = utilities.lanAddresses.first ?? "" } }
                        }
                    }
                    if utilities.remoteRunning {
                        Text("Listening on \(utilities.remoteListenHost):\(utilities.remotePort)").font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                        HStack {
                            Button("Preview on this Mac") { if let url = utilities.localRemoteURL { NSWorkspace.shared.open(url) } }
                        }
                    }
                    if let issue = utilities.remoteError { Text(issue).font(.system(size: 12)).foregroundStyle(.orange) }
                }
            }
            HStack {
                Circle().fill(utilities.remoteRunning ? .green : .gray).frame(width: 7, height: 7)
                Text(utilities.remoteStarting ? "Connecting your phone…" : utilities.remoteRunning ? "LAN phone access enabled" : "Phone access off").font(.system(size: 12))
                Spacer()
                Button(utilities.remoteRunning || utilities.remoteStarting ? "Stop & revoke links" : "Connect phone") {
                    if utilities.remoteRunning || utilities.remoteStarting { utilities.stopRemote() }
                    else { utilities.startRemote(lanAddress: lanAddress.isEmpty ? nil : lanAddress) }
                }
            }
        }.padding(20)
    }
    @ViewBuilder private var phoneConnection: some View {
        if let url = phoneConnectionURL, let qr = qrImage(url) {
            VStack(spacing: 10) {
                Text("Scan with your iPhone Camera").font(.system(size: 13, weight: .semibold))
                Image(nsImage: qr).interpolation(.none).resizable().frame(width: 176, height: 176)
                    .padding(12).background(.white, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel("QR code to connect your phone to Open One")
                Text("Tap the Camera link to open Open One in Safari.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Text("\(utilities.remoteConversationCount) tracked conversations from this Mac\nSame sessions and worktrees")
                    .font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Copy phone connection link") { copyConnectionLink(url) }
            }.frame(maxWidth: .infinity)
        } else {
            HStack(spacing: 12) {
                Image(systemName: "qrcode").font(.system(size: 30)).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 5) {
                    Text(utilities.remoteStarting ? "Creating your phone link…" : "Connect your phone").font(.system(size: 13, weight: .semibold))
                    Text(utilities.remoteStarting ? "Starting the connection. Your QR code will appear here when it is ready." : "Click Connect phone below. Your QR code will appear here. No app installation needed.")
                        .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
        }
    }
    private var phoneConnectionURL: URL? {
        guard utilities.remoteRunning, let url = utilities.remoteURL else { return nil }
        return url
    }
    private func copyConnectionLink(_ connection: URL? = nil) {
        guard let url = connection ?? utilities.remoteURL else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }
    private func qrImage(_ url: URL) -> NSImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(url.absoluteString.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let image = NSImage(size: output.extent.size)
        image.addRepresentation(NSCIImageRep(ciImage: output))
        return image
    }
}
