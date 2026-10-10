import SwiftUI
import AppKit

struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel
    var later: () -> Void
    var finish: (Bool) -> Void
    private let labels = ["Connect agents", "Choose a project", "Try it", "Ready"]
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                BrandLogo(size: 42).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Welcome to Open One").font(.system(size: 23, weight: .semibold))
                    Text("Your agents. Within reach.").font(.system(size: 13)).foregroundStyle(.secondary)
                }
                Spacer()
                Text("OPEN SOURCE").font(.system(size: 9, weight: .semibold)).tracking(1.4).foregroundStyle(.secondary)
            }.padding(.bottom, 24)
            HStack(spacing: 8) {
                ForEach(0..<3) { index in
                    VStack(alignment: .leading, spacing: 7) {
                        Capsule().fill(index <= model.progress.step ? Color.accentColor : .white.opacity(0.12)).frame(height: 3)
                        Text("\(index + 1)  \(labels[index])").font(.system(size: 11, weight: index == model.progress.step ? .semibold : .regular)).foregroundStyle(index <= model.progress.step ? .primary : .secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }.padding(.bottom, 24)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if model.progress.step == 0 { connections }
                    else if model.progress.step == 1 { project }
                    else if model.progress.step == 2 { verification }
                    else { ready }
                    if let error = model.error {
                        Label(error, systemImage: "exclamationmark.triangle").font(.system(size: 12)).foregroundStyle(.orange).textSelection(.enabled)
                            .padding(12).frame(maxWidth: .infinity, alignment: .leading).background(.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 16)
            }
            Divider().padding(.bottom, 16)
            HStack {
                if model.progress.step < 3 { Button("Set up later", action: later).buttonStyle(.plain).foregroundStyle(.secondary).accessibilityIdentifier("setup.later") }
                Spacer()
                if model.progress.step > 0 && model.progress.step < 3 { Button("Back") { model.back() }.disabled(model.verifying) }
                if model.progress.step < 2 {
                    Button("Continue") { model.advance() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                        .disabled(model.progress.step == 0 ? !model.canContinue : !model.projectValid).accessibilityIdentifier("setup.continue")
                } else if model.progress.step == 2 {
                    if model.verifying { Button("Cancel check") { model.cancelVerification() } }
                    else { Button(model.error == nil ? "Verify connections" : "Retry connection check") { model.verify() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(!model.canContinue || !model.projectValid).accessibilityIdentifier("setup.verify") }
                } else {
                    Button("Connect my phone") { finish(true) }.accessibilityIdentifier("setup.phone")
                    Button("Open my Inbox") { finish(false) }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).accessibilityIdentifier("setup.finish")
                }
            }
        }.padding(30).frame(width: 640, height: 610).background(Color(white: 0.085)).preferredColorScheme(.dark)
            .task { await model.refresh() }
    }
    private var connections: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Bring your coding agents.").font(.system(size: 20, weight: .semibold))
            Text("Choose the agents you use. Open One connects through their official CLIs and your existing accounts.").font(.system(size: 13)).foregroundStyle(.secondary)
            ForEach(OnboardingModel.providers, id: \.self) { provider in
                providerCard(provider)
            }
            HStack {
                Text("These checks don’t send a model request.").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button(model.checking ? "Checking…" : "Check again") { Task { await model.refresh() } }.disabled(model.checking)
            }
        }
    }
    private func providerCard(_ provider: String) -> some View {
        let status = model.statuses[provider]
        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                ProviderLogo(provider: provider, size: 23)
                Toggle(provider == "Claude" ? "Claude Code" : "Codex", isOn: Binding(get: { model.progress.providers.contains(provider) }, set: { model.chooseProvider(provider, selected: $0) }))
                    .toggleStyle(.checkbox).font(.system(size: 14, weight: .semibold)).accessibilityIdentifier("setup.provider.\(provider.lowercased())")
                Spacer()
                if model.checking { ProgressView().controlSize(.small) }
                else if status?.state == .ready { Label("Signed in", systemImage: "checkmark.circle.fill").font(.system(size: 11)).foregroundStyle(.green) }
                else { Text(status?.state == .missing ? "Not installed" : "Needs attention").font(.system(size: 11)).foregroundStyle(.orange) }
            }
            Text(status?.detail ?? "Checking installation and sign-in…").font(.system(size: 12)).foregroundStyle(.secondary)
            if let status, status.state != .ready {
                HStack {
                    if status.state == .missing {
                        Link("Install \(provider == "Claude" ? "Claude Code" : "Codex") ↗", destination: URL(string: provider == "Claude" ? "https://code.claude.com/docs/en/quickstart" : "https://developers.openai.com/codex/cli")!)
                    } else {
                        Button("Sign in with \(provider == "Claude" ? "Claude" : "Codex")…") { model.signIn(provider) }
                        Text("Opens the official CLI in Terminal.").foregroundStyle(.secondary)
                    }
                }.font(.system(size: 11))
            }
        }.padding(14).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(model.progress.providers.contains(provider) ? Color.accentColor.opacity(0.65) : .white.opacity(0.08), lineWidth: 1))
    }
    private var project: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "folder").font(.system(size: 34, weight: .light)).foregroundStyle(.secondary)
            Text("Where are you working?").font(.system(size: 22, weight: .semibold))
            Text("Choose a project folder for your first conversations. You can add more projects and change which conversations you follow later.").font(.system(size: 14)).foregroundStyle(.secondary)
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.progress.project.isEmpty ? "No project selected" : URL(fileURLWithPath: model.progress.project).lastPathComponent).font(.system(size: 15, weight: .medium))
                    if !model.progress.project.isEmpty { Text(model.progress.project).font(.system(size: 11)).foregroundStyle(.secondary).textSelection(.enabled) }
                }
                Spacer()
                Button("Choose folder…") {
                    let picker = NSOpenPanel(); picker.canChooseDirectories = true; picker.canChooseFiles = false; picker.allowsMultipleSelection = false
                    picker.prompt = "Choose project"
                    guard let window = NSApp.keyWindow else { return }
                    picker.beginSheetModal(for: window) { result in
                        if result == .OK, let url = picker.url { model.chooseProject(url) }
                        window.makeKeyAndOrderFront(nil)
                    }
                }.accessibilityIdentifier("setup.project")
            }.padding(16).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            Text("Choose a folder you trust. Your agents’ normal project permissions apply. For Codex, use a Git project.").font(.system(size: 12)).foregroundStyle(.secondary)
            Text("Microphone and screen access are optional. We’ll ask only when you use voice or screenshots.").font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }
    private var verification: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Let’s get your first reply.").font(.system(size: 22, weight: .semibold))
            Text("Send one short hello to each selected agent. A real response confirms that Open One can use your account in this project.").font(.system(size: 14)).foregroundStyle(.secondary)
            Text(OnboardingModel.checkPrompt).font(.system(size: 12)).foregroundStyle(.secondary).padding(14).frame(maxWidth: .infinity, alignment: .leading).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            ForEach(model.progress.providers, id: \.self) { provider in
                HStack(spacing: 10) {
                    ProviderLogo(provider: provider, size: 23)
                    Text(provider == "Claude" ? "Claude Code" : "Codex").font(.system(size: 14, weight: .medium))
                    Spacer()
                    if model.verified(provider) { Label("Response received", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                    else if model.activeProvider == provider { ProgressView().controlSize(.small); Text("Waiting for reply…").foregroundStyle(.secondary) }
                    else { Text("Ready to check").foregroundStyle(.secondary) }
                }.font(.system(size: 11)).padding(12).background(.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
            }
            Text("Uses your existing account and may count toward its usage. The conversations stay in your Inbox. No task is sent until you click Verify connections.").font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
    private var ready: some View {
        VStack(alignment: .leading, spacing: 17) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 35)).foregroundStyle(.green)
            Text("Your agents are within reach.").font(.system(size: 23, weight: .semibold))
            ForEach(model.progress.providers, id: \.self) { provider in
                VStack(alignment: .leading, spacing: 5) {
                    Text(provider == "Claude" ? "Claude Code" : "Codex").font(.system(size: 12, weight: .semibold))
                    Text(model.response(provider) ?? "Connected").font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(3)
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
            }
            Label("Reach for the screen edge to open your agents.", systemImage: "sidebar.right").font(.system(size: 13))
            Label("Double-tap Control to start talking.", systemImage: "keyboard").font(.system(size: 13))
            Text("Want to keep going from your phone? Connect it now, or find Remote access from the toolbar later.").font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }
}

@MainActor final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    let model: OnboardingModel
    init(model: OnboardingModel, finished: @escaping (Bool) -> Void) {
        self.model = model
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 610), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Set up Open One"; window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true; window.backgroundColor = NSColor(white: 0.085, alpha: 1)
        super.init(window: window)
        window.delegate = self
        window.contentView = NSHostingView(rootView: OnboardingView(model: model, later: { [weak self] in
            if model.deferSetup() { self?.window?.orderOut(nil) }
        }, finish: { [weak self] phone in
            if model.complete() { self?.window?.orderOut(nil); finished(phone) }
        }))
        window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func present() { NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil) }
    func windowShouldClose(_ sender: NSWindow) -> Bool { model.deferSetup() }
}
