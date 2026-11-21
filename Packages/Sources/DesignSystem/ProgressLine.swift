import SwiftUI

/// Which set or round the current exercise is on, as its caption line shows it: "Set 2 of 3",
/// and while resting after that set, "Set 2 of 3 done".
public struct SetPlace: Equatable {
    /// The word that names where it is: "Set", or "Round" in a superset.
    public var word: String
    public var number: Int
    public var total: Int
    /// Whether the set is done, resting after it: "done" shows after the line.
    public var isDone: Bool
    public var locale: Locale

    public init(
        word: String,
        number: Int,
        total: Int,
        isDone: Bool = false,
        locale: Locale = .current,
    ) {
        self.word = word
        self.number = number
        self.total = total
        self.isDone = isDone
        self.locale = locale
    }

    var numberText: String {
        number.formatted(.number.locale(locale))
    }

    var totalText: String {
        total.formatted(.number.locale(locale))
    }

    /// "Set 2 of 3", or "Set 2 of 3 done", as VoiceOver reads it.
    public var text: String {
        "\(word) \(numberText) of \(totalText)\(isDone ? " done" : "")"
    }
}

/// What the lead of the current exercise's caption line reads, part by part, as `ProgressLine`
/// draws it: "Set", "2", "of 3", then at its end "done" while resting after the set, else the
/// side, "Left", else nothing.
struct ProgressWords: Equatable {
    enum End: Equatable {
        case done
        case side(String)
    }

    var word: String
    var number: String
    var total: String
    var end: End?

    init(_ focus: RowFocus) {
        word = focus.place.word
        number = focus.place.numberText
        total = focus.place.totalText
        end = focus.place.isDone ? .done : focus.side.map(End.side)
    }
}

/// The lead of the current exercise's caption line: "Set 1 of 3", then, in one place, "done"
/// while resting after the set, or the side, "· Left", set off in the name's color; the two
/// never show together. As the sets go by only the number changes, rolling as a count's digits
/// do (`RestBlock.countdown`, Dave, 2026-11-20): "Set", "of 3" hold still, and "done" keeps its
/// room and fades, so nothing beside it moves. Changed with no animation, as a relaunch or End's
/// set-back does, every part changes at once. With Reduce Motion the number changes in place and
/// "done" shows or goes at once. The words wrap between words, as at the accessibility sizes,
/// "done" with them; a side, or "done" in its place, goes beside the set where it fits, else
/// under it (`FigureLayout`).
struct ProgressLine: View {
    let focus: RowFocus

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let words = ProgressWords(focus)
        let showsDone = words.end == .done
        let done = word("done")
            .fading(showsDone, on: doneFade)
        if let side = focus.side {
            let showsSide = !showsDone
            FigureLayout(spacing: 0) {
                FlowLayout(spacing: 0) {
                    placeWords(words)
                }
                // The side laid out while hidden too, so the line keeps its room through a rest.
                ZStack(alignment: .topLeading) {
                    done
                    SideWord(side: side)
                        // Within a set, Left fades to Right; a side changed as it hides, the
                        // next set's taking the place of the one just done, changes at once.
                        .transaction(value: side) {
                            if !showsSide {
                                $0.animation = nil
                            }
                        }
                        // It goes at once as "done" comes in, and comes back once "done" has gone.
                        .fading(showsSide, on: reduceMotion || !showsSide ? nil : Fade.inAfterOut)
                }
            }
        } else {
            // "done" one more word, kept laid out: at the accessibility sizes it shares the
            // second line with "of 3" where it fits, else has the line under it.
            FlowLayout(spacing: 0) {
                placeWords(words)
                done
            }
        }
    }

    /// "done" in and out; where it shares its place with a side, it goes as quickly as the side
    /// does, and comes in once the side has gone, so the two are never seen over each other.
    private var doneFade: Animation? {
        guard !reduceMotion else { return nil }
        guard focus.side != nil else { return Fade.in }
        return focus.place.isDone ? Fade.inAfterOut : Fade.out
    }

    /// "Set 1 of 3 ", a word to a part, each with the space after it, so each is its own part of
    /// the flow it is put in. The number's digits are of one width, so "of 3" holds still as it
    /// rolls.
    @ViewBuilder
    private func placeWords(_ words: ProgressWords) -> some View {
        word("\(words.word) ")
        word("\(words.number) ")
            .monospacedDigit()
            .contentTransition(
                reduceMotion ? .identity : .numericText(value: Double(focus.place.number)),
            )
            // Its own roll, whatever curve else the update animates on.
            .transaction(value: focus.place.number) {
                if $0.animation != nil {
                    $0.animation = reduceMotion ? nil : SetMotion.restRoll
                }
            }
        word("of ")
        word("\(words.total) ")
    }

    private func word(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.ppCurrentProgress)
            .foregroundStyle(.pp(.textSecondary))
            .fixedSize()
    }
}

/// How the words at the line's end come and go: out quickly, as a leaving part does, and in over
/// the roll, once the word before them has gone.
private enum Fade {
    static let out = Animation.easeOut(duration: SetMotion.leaveFade)
    static let `in` = Animation.easeOut(duration: SetMotion.roll)
    static let inAfterOut = `in`.delay(SetMotion.leaveFade)
}

extension View {
    /// Shown while `isShown`, kept laid out; a change in a motion fades on `animation`, whatever
    /// the motion's curve, and one with no animation, at once.
    fileprivate func fading(_ isShown: Bool, on animation: Animation?) -> some View {
        opacity(isShown ? 1 : 0)
            .transaction(value: isShown) {
                if $0.animation != nil {
                    $0.animation = animation
                }
            }
    }
}

/// "· Left": the dot in the set's gray, the side in the name's color. Left to Right, the old side
/// fades out where it stands and the new one fades in once it has gone, so the two are never seen
/// over each other and no letter is cut, as a push clipped them, "Right" losing its g for six
/// frames. With Reduce Motion the side changes in place.
private struct SideWord: View {
    let side: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(verbatim: "·\(noBreakSpace)")
                .foregroundStyle(.pp(.textSecondary))
            ZStack(alignment: .topLeading) {
                Text(verbatim: side)
                    .foregroundStyle(.pp(.textPrimary))
                    .id(side)
                    .transition(reduceMotion ? .identity : Self.swap)
            }
        }
        .font(.ppCurrentProgress)
        .fixedSize()
    }

    private static let swap = AnyTransition.asymmetric(
        insertion: .opacity.animation(Fade.inAfterOut),
        removal: .opacity.animation(Fade.out),
    )
}

#Preview {
    let line = { (number: Int, isDone: Bool, side: String?) in
        ProgressLine(focus: RowFocus(
            place: SetPlace(word: "Set", number: number, total: 3, isDone: isDone),
            side: side,
            figures: [],
            spokenFigures: "",
        ))
    }
    VStack(alignment: .leading, spacing: Spacing.md) {
        line(1, false, nil)
        line(1, true, nil)
        line(2, false, "Left")
        line(2, true, "Right")
    }
    .padding()
    .background(Color.pp(.background))
}
