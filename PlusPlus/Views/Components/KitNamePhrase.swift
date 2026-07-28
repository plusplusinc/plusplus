import SwiftUI

/// A kit name set as a NAME (Dave, 2026-07-28).
///
/// The problem it fixes: "Add barbell to main" parses as an adjective waiting
/// for a noun — nothing in the sentence says `main` is the name of a thing.
/// It only bites once a second kit exists, because the naming law
/// (2026-07-20) keeps prose on "your kit" until then and swaps to the raw
/// name after; so the sentence stops parsing exactly when the app gets more
/// complicated, which is the worst moment for it.
///
/// The treatment is the app's data-tag look — soft `surfaceRaised` fill, r6,
/// no stroke — because that is already what "a value, not a control" means
/// everywhere else (`CardTagCapsule`). It is sized from the surrounding text
/// rather than pinned to caption2, so the tag matches the sentence it sits in.
///
/// ⚠️ The name goes LAST. Laying a padded tag inside a wrapping paragraph is
/// not something SwiftUI's `Text` can do (an inline background can't take a
/// corner radius, and a view can't be interpolated into a run), so this is an
/// `HStack` on the first text baseline — which reads correctly only while the
/// name terminates the phrase. Every string that carries one today does. If a
/// future line needs the name mid-sentence, give it its noun in prose ("the
/// main kit") instead of forcing a tag into the middle.
struct KitTag: View {
    let name: String

    var body: some View {
        Text(name)
            .fontWeight(.semibold)
            .padding(.horizontal, 7)
            .padding(.vertical, 1.5)
            .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: CardTagCapsule.cornerRadius))
            // A kit is user-named, so the name can be long. Truncating in the
            // MIDDLE keeps both ends, which is where the distinguishing words
            // of "Home garage" and "Home gym" live.
            .lineLimit(1)
            .truncationMode(.middle)
    }
}

/// `<prose> <kit tag>` on one baseline: the phrase wraps, the tag doesn't.
struct KitNamePhrase: View {
    let prefix: String
    let kit: String
    var font: Font = .system(.subheadline)
    var tint: Color = Theme.textPrimary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(prefix)
                .foregroundStyle(tint)
            KitTag(name: kit)
        }
        .font(font)
        // Two Texts would otherwise be read as two elements with a pause in
        // between; spoken, the sentence is one sentence.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(prefix) \(kit)")
    }
}
