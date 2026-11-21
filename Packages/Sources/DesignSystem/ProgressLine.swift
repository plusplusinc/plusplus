import SwiftUI

/// Which set or round the current exercise is on, as its caption line shows it: "Set 2 of 3",
/// and while resting after that set, "Set 2 of 3 done".
public struct SetPlace: Equatable {
    /// The word that names where it is: "Set", or "Round" in a superset.
    public var word: String
    public var number: Int
    public var total: Int
    /// Whether the set is done, resting after it: "done" shows after the line.
    public var isDone = false
    public var locale: Locale

    public init(word: String, number: Int, total: Int, locale: Locale = .current) {
        self.word = word
        self.number = number
        self.total = total
        self.locale = locale
    }

    var numberText: String {
        number.formatted(.number.locale(locale))
    }

    var totalText: String {
        total.formatted(.number.locale(locale))
    }

    /// "Set 2 of 3", as VoiceOver reads it.
    public var text: String {
        "\(word) \(numberText) of \(totalText)"
    }
}

/// What the lead of the current exercise's caption line reads, part by part, as `ProgressLine`
/// draws it: "Set", "2", "of 3", then at its end "done" while resting after the set, else the
/// side, "Left", while it shows, else nothing.
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
        if focus.place.isDone {
            end = .done
        } else if focus.showsSide, let side = focus.side {
            end = .side(side)
        }
    }
}

/// The lead of the current exercise's caption line: "Set 1 of 3", then, in one place, "done"
/// while resting after the set, or the side, "· Left", set off in the name's color; the two
/// never show together. As the sets go by only the number changes, rolling as a count's digits
/// do (`RestBlock.countdown`, Dave, 2026-11-20): "Set", "of 3" hold still, and "done" keeps its
/// room and fades, so nothing beside it moves. With Reduce Motion the number changes in place and
/// "done" shows or goes at once. The words wrap between words, as at the accessibility sizes,
/// "done" with them; a side, or "done" in its place, goes beside the set where it fits, else
/// under it (`FigureLayout`).
struct ProgressLine: View {
    let focus: RowFocus

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let words = ProgressWords(focus)
        let showsSide = words.end.map { $0 != .done } ?? false
        let done = word("done")
            .opacity(words.end == .done ? 1 : 0)
            .animation(doneFade, value: words.end == .done)
        if let side = focus.side {
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
                        .opacity(showsSide ? 1 : 0)
                        .animation(sideFade(showsSide), value: showsSide)
                }
            }
        } else {
            // "done" one more word, kept laid out: at the accessibility sizes it shares the
            // second line with "of 3", so the line is as tall as it was before it had a "done".
            FlowLayout(spacing: 0) {
                placeWords(words)
                done
            }
        }
    }

    private static let fadeIn = Animation.easeOut(duration: SetMotion.roll)

    /// "done" in and out; where it shares its place with a side, it goes as quickly as the side
    /// does, and comes in once the side has gone, so the two are never seen over each other.
    private var doneFade: Animation? {
        guard !reduceMotion else { return nil }
        guard focus.side != nil else { return Self.fadeIn }
        return focus.place.isDone
            ? Self.fadeIn.delay(SetMotion.leaveFade)
            : .easeOut(duration: SetMotion.leaveFade)
    }

    /// The side goes at once as "done" comes in, since the side just done gives way to the next
    /// set's as it goes, and comes back once "done" has gone from its place.
    private func sideFade(_ showsSide: Bool) -> Animation? {
        guard !reduceMotion, showsSide else { return nil }
        return Self.fadeIn.delay(SetMotion.leaveFade)
    }

    /// "Set 1 of 3 ", a word to a part, each with the space after it. The number's digits are of
    /// one width, so "of 3" holds still as it rolls.
    @ViewBuilder
    private func placeWords(_ words: ProgressWords) -> some View {
        // A group, so each word is its own part of the flow it is put in.
        word("\(words.word) ")
        word("\(words.number) ")
            .monospacedDigit()
            .contentTransition(
                reduceMotion ? .identity : .numericText(value: Double(focus.place.number)),
            )
            // Its own roll, whatever else the update animates.
            .transaction(value: focus.place.number) {
                $0.animation = reduceMotion ? nil : SetMotion.restRoll
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
        insertion: .opacity.animation(
            .easeOut(duration: SetMotion.roll).delay(SetMotion.leaveFade),
        ),
        removal: .opacity.animation(.easeOut(duration: SetMotion.leaveFade)),
    )
}

#Preview {
    let line = { (number: Int, isDone: Bool, side: String?) in
        var place = SetPlace(word: "Set", number: number, total: 3)
        place.isDone = isDone
        var focus = RowFocus(place: place, side: side, figures: [], spokenFigures: "")
        focus.showsSide = !isDone
        return ProgressLine(focus: focus)
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
