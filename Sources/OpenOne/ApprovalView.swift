import SwiftUI
import OneCore

/// Approval content is literal text, never Markdown or an editable chat reply.
struct ApprovalView: View {
    @ObservedObject var store: Store
    let agent: Agent

    var body: some View {
        if let request = store.approvals[agent.id]?.first {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "hand.raised.fill").foregroundStyle(.orange)
                    Text(request.title).fontWeight(.semibold)
                    Spacer()
                    if let count = store.approvals[agent.id]?.count, count > 1 { Text("1 of \(count)").foregroundStyle(.secondary) }
                }
                Text("\(agent.provider) · \(agent.displayTitle)").font(.system(size: 12)).lineLimit(2)
                Text(agent.directory).font(.system(size: 11)).foregroundStyle(.secondary).textSelection(.enabled)
                ScrollView {
                    Text(verbatim: request.details).font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                }.frame(height: 130).background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
                if !request.allowEnabled {
                    Text("This request cannot be approved here. Deny it to let the agent choose another approach.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    Button("Deny") { store.stageApproval(request.id, agentID: agent.id, allow: false) }
                        .accessibilityLabel("Deny command")
                    Spacer()
                    Button { store.stageApproval(request.id, agentID: agent.id, allow: true) } label: {
                        Text("Approve once").fontWeight(.semibold).padding(.horizontal, 14).padding(.vertical, 8)
                            .foregroundStyle(request.allowEnabled ? .black : .gray)
                            .background(request.allowEnabled ? .white : .white.opacity(0.08), in: Capsule())
                    }.buttonStyle(.plain)
                        .disabled(!request.allowEnabled).accessibilityLabel("Approve command once")
                }.disabled(store.pending != nil)
                if store.pending?.approvalID == request.id {
                    HStack { Text("Sending decision…"); Spacer(); Button("Undo") { store.undo() } }.font(.system(size: 11))
                }
            }.font(.system(size: 13)).padding(14)
                .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.orange.opacity(0.4)))
                .padding(10).accessibilityElement(children: .contain)
        } else if agent.isObserved && agent.state == .waiting {
            Label("This conversation is waiting in its original terminal. Confirm or deny the command there. Open One can show approvals for sessions it runs or terminals connected through Herdr.", systemImage: "terminal")
                .font(.system(size: 12)).foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true).padding(12)
        }
    }
}
