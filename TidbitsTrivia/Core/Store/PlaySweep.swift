import Foundation

/// Plays whole games — start to results screen — and reports what happened.
///
/// This is deliberately NOT the question-set sweep in `QuestionProvider`. That one
/// assembles a round and inspects the questions; it never submits an answer, so a
/// whole class of defect is invisible to it: an answer the game marks wrong when
/// it is right, a round that never reaches its results screen, a mode whose score
/// disagrees with what the player actually did. Those only exist once the game is
/// PLAYED, so this drives the real `GameEngine` through the real submit / reveal /
/// advance loop — the same calls the views make — and audits the play.
///
/// It runs the engine rather than the SwiftUI views because the view autopilot
/// sleeps 0.9s per step for screenshots; at that rate a sweep of a thousand games
/// takes about six hours. The engine is where the rules live, so this is a real
/// playthrough of the rules. Watching the rendered game is a separate, sampled
/// pass — see tools/play/watch.sh — because that is the only way to catch what a
/// player SEES rather than what the engine computes.
@MainActor
enum PlaySweep {

    /// Play `games` games across the mode x category grid, answering CORRECTLY
    /// every time, and print one line per game plus any anomaly.
    ///
    /// Answering correctly is the high-signal run: if a game marks the right
    /// answer wrong, or scores it zero, or refuses to end, that is a defect the
    /// player meets on their best turn, not their worst.
    static func run(games: Int, modes: [GameMode], categories: [TriviaCategory],
                    style: Style = .correct) async {
        print("PLAYTHROUGH-BEGIN games=\(games) style=\(style.rawValue)")
        for g in 0..<games {
            let mode = modes[g % modes.count]
            let cat = categories[(g / modes.count) % categories.count]
            await playOne(index: g, mode: mode, category: cat, style: style)
        }
        print("PLAYTHROUGH-END")
    }

    /// How the harness plays. A game only audited on its happy path hides a whole
    /// class of defect — the tie, the zero, the round that ends on the first
    /// question. `wrong` answers everything incorrectly; `timeout` answers nothing
    /// at all, which is what a player who puts the phone down produces.
    enum Style: String { case correct, wrong, timeout }

    private static func playOne(index g: Int, mode: GameMode, category: TriviaCategory,
                                style: Style) async {
        let engine = GameEngine()
        await engine.start(mode: mode, category: category)

        guard !engine.questions.isEmpty else {
            print("PLAY-FAIL\t\(g)\t\(mode.rawValue)\t\(category.id)\tno questions — the game cannot start")
            return
        }

        var steps = 0
        // A round is at most one submit + one advance per question. Anything past
        // that means the loop is not converging, which is a hang in front of a
        // real player — report it rather than spin.
        let budget = engine.questions.count * 4 + 40
        var answeredCorrectly = 0
        var expectedCorrect = 0

        while engine.phase != .finished && engine.phase != .idle && steps < budget {
            steps += 1
            switch engine.phase {
            case .playing:
                guard let q = engine.current else { engine.advance(); continue }
                expectedCorrect += 1
                switch style {
                case .correct: answerCorrectly(engine, q)
                case .wrong:   answerWrongly(engine, q)
                case .timeout: timeoutCurrent(engine, q)
                }
                // Every shape resolves to `.reveal`; if it did not, the submit path
                // silently refused the answer and the round would stall here.
                if engine.phase == .playing {
                    print("PLAY-FAIL\t\(g)\t\(mode.rawValue)\t\(category.id)"
                          + "\tsubmit did not resolve q=\(q.id) shape=\(shapeName(q))")
                    return
                }
                if let a = engine.lastAnswer, a.isCorrect { answeredCorrectly += 1 }
                if style == .correct, engine.lastAnswer?.isCorrect == false {
                    // The player gave the documented-correct answer and the game
                    // called it wrong. This is the defect worth finding.
                    print("PLAY-WRONG\t\(g)\t\(mode.rawValue)\t\(category.id)\t\(q.id)"
                          + "\t\(shapeName(q))\t\(q.correctAnswer)\t\(q.prompt.prefix(80))")
                }
                if style == .wrong, engine.lastAnswer?.isCorrect == true {
                    // Every option was avoided and it still scored a hit — the
                    // question has more than one correct answer, or none.
                    print("PLAY-FALSEHIT\t\(g)\t\(mode.rawValue)\t\(category.id)\t\(q.id)"
                          + "\t\(shapeName(q))\t\(q.prompt.prefix(80))")
                }
            case .reveal:
                engine.advance()
            default:
                break
            }
        }

        if engine.phase != .finished {
            print("PLAY-FAIL\t\(g)\t\(mode.rawValue)\t\(category.id)"
                  + "\tnever finished after \(steps) steps (phase=\(engine.phase))")
            return
        }

        let s = engine.summary
        print("PLAY-DONE\t\(g)\t\(mode.rawValue)\t\(category.id)"
              + "\t\(answeredCorrectly)/\(expectedCorrect)\tscore=\(engine.score)"
              + "\tsummaryCorrect=\(s.correct)\tsummaryTotal=\(s.total)\tsteps=\(steps)")
    }

    /// Answer the current question the way a player who knows the answer would —
    /// by SHAPE, mirroring `GamePlayView`'s autopilot and the engine's own
    /// `forceTimeoutSubmit`, so every mode is exercised through its real path.
    private static func answerCorrectly(_ engine: GameEngine, _ q: Question) {
        if let spec = q.closest {
            engine.setGuess(spec.answer)
            engine.submitGuess()
        } else if let order = q.ordering {
            // Only `moveOrderItem` exists, because that is all a player has — the
            // board is reordered one swap at a time. Selection-sorting through it
            // exercises the same code path their taps do.
            for target in order.indices {
                guard let at = engine.currentOrder.firstIndex(of: order[target]) else { continue }
                var pos = at
                while pos > target { engine.moveOrderItem(pos, up: true); pos -= 1 }
            }
            engine.submitOrder()
        } else if let m = q.matching {
            // Same reason: link each key to its value by the two taps the UI takes.
            for (i, want) in m.values.enumerated() {
                guard let vIndex = engine.matchValues.firstIndex(of: want) else { continue }
                engine.selectMatchKey(i)
                engine.assignMatchValue(vIndex)
            }
            engine.submitMatch()
        } else if q.accepted != nil {
            engine.typedText = q.correctAnswer
            engine.submitText()
        } else if let spec = q.enumerate {
            for name in spec.displayNames { engine.submitEnumGuess(name) }
            if engine.phase == .playing { engine.finishEnum() }
        } else {
            if engine.mode == .stake, engine.currentStake == 0,
               let tier = engine.stakeTiers.first(where: { $0.remaining > 0 }) {
                engine.setStake(tier.value)
            }
            engine.submit(q.correctIndex)
        }
    }

    /// Answer everything wrong, on purpose. Drives the losing outcome of every
    /// mode — Survival ending on question one, a results screen with nothing
    /// right, Stake spending chips on misses.
    private static func answerWrongly(_ engine: GameEngine, _ q: Question) {
        if let spec = q.closest {
            // Far outside tolerance, and clamped into the slider's own domain so
            // this stays a guess a player could actually make.
            let far = spec.answer + spec.tolerance * 4
            engine.setGuess(far > spec.max ? spec.min : far)
            engine.submitGuess()
        } else if q.ordering != nil {
            engine.submitOrder()      // the board starts deliberately shuffled
        } else if q.matching != nil {
            engine.submitMatch()      // nothing linked
        } else if q.accepted != nil {
            engine.typedText = "zzz not the answer"
            engine.submitText()
        } else if q.enumerate != nil {
            engine.finishEnum()       // named nothing
        } else {
            if engine.mode == .stake, engine.currentStake == 0,
               let tier = engine.stakeTiers.first(where: { $0.remaining > 0 }) {
                engine.setStake(tier.value)
            }
            let wrong = q.options.indices.first { $0 != q.correctIndex } ?? 0
            engine.submit(wrong)
        }
    }

    /// Answer nothing — what a player who puts the phone down produces. Mirrors
    /// the engine's own `forceTimeoutSubmit`, which is private to it.
    private static func timeoutCurrent(_ engine: GameEngine, _ q: Question) {
        if q.closest != nil { engine.submitGuess() }
        else if q.ordering != nil { engine.submitOrder() }
        else if q.matching != nil { engine.submitMatch() }
        else if q.accepted != nil { engine.typedText = ""; engine.submitText() }
        else if q.enumerate != nil { engine.finishEnum() }
        else { engine.submit(nil) }
    }

    private static func shapeName(_ q: Question) -> String {
        if q.closest != nil { return "closest" }
        if q.ordering != nil { return "ordering" }
        if q.matching != nil { return "matching" }
        if q.accepted != nil { return "typed" }
        if q.enumerate != nil { return "enumerate" }
        return "mcq"
    }
}
