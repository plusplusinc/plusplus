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

/// The lead of the current exercise's caption line: "Set 1 of 3", then, in one place, "done"
/// while resting after the set, or the side, "· Left", set off in the name's color; the two
/// never show together. As the sets go by only the number changes, rolling as a count's digits
/// do (`RestBlock.countdown`, Dave, 2026-11-20): "Set", "of 3" hold still, and "done" keeps its
/// room and fades, so nothing beside it moves. With Reduce Motion the number changes in place and
/// "done" shows or goes at once. Side by side where they fit, else the side or "done" under the
/// set (`FigureLayout`); the set's words wrap between words, as at the accessibility sizes.
struct ProgressLine: View {
    let focus: RowFocus

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        FigureLayout(spacing: 0) {
            placeWords(focus.place)
            ZStack(alignment: .topLeading) {
                word("done")
                    .opacity(focus.place.isDone ? 1 : 0)
                    .animation(doneFade, value: focus.place.isDone)
                if let side = focus.side {
                    SideWord(side: side)
                        // Within a set, Left fades to Right; a side changed as it hides, the
                        // next set's taking the place of the one just done, changes at once.
                        .transaction(value: side) {
                            if !focus.showsSide {
                                $0.animation = nil
                            }
                        }
                        .opacity(focus.showsSide ? 1 : 0)
                        .animation(sideFade, value: focus.showsSide)
                }
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
    private var sideFade: Animation? {
        guard !reduceMotion, focus.showsSide else { return nil }
        return Self.fadeIn.delay(SetMotion.leaveFade)
    }

    /// "Set 1 of 3 ", a word to a part, each with the space after it. The number's digits are of
    /// one width, so "of 3" holds still as it rolls.
    private func placeWords(_ place: SetPlace) -> some View {
        FlowLayout(spacing: 0) {
            word("\(place.word) ")
            word("\(place.numberText) ")
                .monospacedDigit()
                .contentTransition(
                    reduceMotion ? .identity : .numericText(value: Double(place.number)),
                )
                // Its own roll, whatever else the update animates.
                .transaction(value: place.number) {
                    $0.animation = reduceMotion ? nil : SetMotion.restRoll
                }
            word("of ")
            word("\(place.totalText) ")
        }
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
