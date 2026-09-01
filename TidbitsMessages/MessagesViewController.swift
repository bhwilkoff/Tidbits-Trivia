import Messages
import SwiftUI
import UIKit

/// Tidbits in a message thread.
///
/// The model is the whole design: there is no server, no room, no backend. A round
/// lives entirely in an `MSMessage.url` (see `RoundState`), and `MSSession` makes each
/// send REPLACE the previous bubble instead of appending — so a thread shows the
/// current state of the game, not a transcript of every tap.
///
/// Two presentations, because Messages gives you two:
///   - `.compact` — the drawer above the keyboard. Small. Start a round here.
///   - `.expanded` — near-full screen. Answer and reveal here.
/// Answering in compact would put four options in a few hundred points of height, so
/// the controller requests expansion when there is a round to play.
final class MessagesViewController: MSMessagesAppViewController {

    private var host: UIHostingController<AnyView>?

    // MARK: - Conversation lifecycle

    override func willBecomeActive(with conversation: MSConversation) {
        super.willBecomeActive(with: conversation)
        present(conversation: conversation)
    }

    override func didTransition(to presentationStyle: MSMessagesAppPresentationStyle) {
        super.didTransition(to: presentationStyle)
        guard let conversation = activeConversation else { return }
        present(conversation: conversation)
    }

    /// A participant identifier is an opaque per-conversation UUID — never a name, a
    /// handle or anything linkable to the account. So scores are thread-local and
    /// players name themselves; there is no path from here to `players/{uid}` without
    /// a full sign-in inside a keyboard drawer, which is out of scope.
    ///
    /// Truncated to 8 characters to stay inside the 5,000-character wire budget: eight
    /// full UUIDs would spend 288 characters on identity alone.
    private func localPlayerID(_ conversation: MSConversation) -> String {
        String(conversation.localParticipantIdentifier.uuidString.prefix(8))
    }

    // MARK: - Routing

    private func present(conversation: MSConversation) {
        let state = conversation.selectedMessage?.url.flatMap(RoundState.init(url:))

        let view: AnyView
        if let state {
            if presentationStyle == .compact {
                // A live round needs room. Ask for it rather than cramming four
                // options into the drawer.
                view = AnyView(CompactPromptView(
                    headline: "Tap to play",
                    subhead: "Question \(min(state.index + 1, state.questionIDs.count)) of \(state.questionIDs.count)",
                    action: { [weak self] in self?.requestPresentationStyle(.expanded) }))
            } else {
                view = AnyView(RoundView(
                    state: state,
                    playerID: localPlayerID(conversation),
                    onSend: { [weak self] updated, caption in
                        self?.send(updated, caption: caption, in: conversation)
                    }))
            }
        } else {
            view = AnyView(StartRoundView(
                compact: presentationStyle == .compact,
                onExpand: { [weak self] in self?.requestPresentationStyle(.expanded) },
                onStart: { [weak self] category, name in
                    guard let self else { return }
                    self.startRound(category: category, name: name, in: conversation)
                }))
        }
        setRoot(view)
    }

    /// `root`, not `view` — naming the parameter `view` shadowed the controller's own
    /// `self.view`, so the constraints were pinned to the SwiftUI value instead of the
    /// container. Swift could not even produce a diagnostic for it.
    private func setRoot(_ root: AnyView) {
        if let host {
            host.rootView = root
            return
        }
        let controller = UIHostingController(rootView: root)
        controller.view.backgroundColor = .clear
        addChild(controller)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        let container: UIView = self.view
        container.addSubview(controller.view)
        NSLayoutConstraint.activate([
            controller.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            controller.view.topAnchor.constraint(equalTo: container.topAnchor),
            controller.view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        controller.didMove(toParent: self)
        host = controller
    }

    // MARK: - Sending

    private func startRound(category: String?, name: String, in conversation: MSConversation) {
        // The seed makes the round reproducible from its id alone: every device draws
        // the same questions, which is the whole reason the wire can carry ids only.
        let seed = UInt64.random(in: 1...UInt64.max)
        let questions = QuestionPack.shared.pick(
            count: RoundState.questionCount, category: category, seed: seed)
        guard !questions.isEmpty else { return }

        var state = RoundState(questionIDs: questions.map(\.i), players: [], index: 0)
        state.upsert(playerID: localPlayerID(conversation), name: name)
        send(state, caption: "Tidbits — tap to play", in: conversation)
    }

    private func send(_ state: RoundState, caption: String, in conversation: MSConversation) {
        // Reuse the session of the message being replied to. That is what makes the
        // bubble UPDATE instead of the thread filling with one bubble per answer —
        // without it a five-question round with six players is thirty bubbles.
        let session = conversation.selectedMessage?.session ?? MSSession()
        let message = MSMessage(session: session)

        let layout = MSMessageTemplateLayout()
        layout.caption = caption
        layout.subcaption = scoreline(state)
        layout.image = BubbleImage.render(state: state)
        message.layout = layout

        let encoded = state.encoded()
        // Belt and braces on the documented 5,000-character cap. Sending anyway would
        // throw MSMessageErrorCode.urlExceedsMaxSize and the player's answer would
        // vanish with no explanation, which is the worst possible failure here.
        guard encoded.count < 5_000, let url = URL(string: encoded) else {
            return
        }
        message.url = url
        message.summaryText = caption

        conversation.insert(message) { [weak self] error in
            if error != nil { return }
            self?.dismiss()
        }
    }

    private func scoreline(_ state: RoundState) -> String {
        guard !state.players.isEmpty else { return "Waiting for players" }
        let key: (String) -> Int? = { QuestionPack.shared.correctIndex(id: $0) }
        return state.players
            .map { "\($0.name) \(state.score($0, correctIndexFor: key))" }
            .joined(separator: " · ")
    }
}
