import SwiftUI
import AppKit
import OneCore

struct TrackingView: View {
    @ObservedObject var store: Store
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Tracked worktrees").font(.system(size: 21, weight: .semibold))
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text("Choose what appears in your Inbox and agent panel. New activity stays within your selection.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            Toggle("Automatically track all worktrees", isOn: Binding(get: { store.trackedWorktreePaths == nil }, set: store.setTrackAllWorktrees))
                .font(.system(size: 12))
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if store.knownWorktreePaths.isEmpty { Text("Add a project or worktree folder to get started.").foregroundStyle(.secondary) }
                    ForEach(store.knownWorktreePaths, id: \.self) { path in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(ProjectLocation(directory: path).displayName).fontWeight(.medium)
                                Text(path).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled)
                            }
                            Spacer()
                            let tracked = store.trackedWorktreePaths?.contains(path) ?? true
                            Button("Only this") { store.trackOnlyWorktree(path) }.help("Track only this worktree")
                            Button(tracked ? "Remove" : "Add") { store.trackWorktree(path, enabled: !tracked) }
                                .accessibilityLabel("\(tracked ? "Remove" : "Add") worktree \(path)")
                        }.font(.system(size: 12)).padding(10).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                    }
                    if !store.removedConversations.isEmpty {
                        Divider()
                        Text("Removed conversations").font(.system(size: 13, weight: .semibold))
                        ForEach(store.removedConversations) { agent in
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(agent.displayTitle).lineLimit(1)
                                    Text(ProjectLocation(directory: agent.directory).displayName).font(.system(size: 10)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Add back") { store.trackConversation(agent.id, enabled: true) }
                            }.font(.system(size: 12))
                        }
                    }
                }
            }
            HStack {
                Button("Add folder…") {
                    let picker = NSOpenPanel()
                    picker.canChooseDirectories = true; picker.canChooseFiles = false
                    picker.allowsMultipleSelection = true; picker.prompt = "Track"
                    if picker.runModal() == .OK {
                        for url in picker.urls { store.trackWorktree(url.path, enabled: true) }
                    }
                }
                Button("Remove all") { store.removeAllTrackedWorktrees() }
                Spacer()
                Text("\(store.activeAgents.count) tracked conversations").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }.padding(22).frame(width: 480, height: 470).preferredColorScheme(.dark)
    }
}
