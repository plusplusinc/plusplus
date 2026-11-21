import SwiftUI

/// A +15 s turning a count's figure up to its new time a digit at a time: each place, the
/// seconds' ones (0 to 9), their tens (0 to 5), and each of the minutes' digits, steps up one
/// digit a step through its own digits, all places together, each step rolled. 0:11 to 0:26
/// reads 0:22, 0:23, 0:24, 0:25, 0:26. Only the figure lags: the rest's end, the key's fill, and
/// VoiceOver's value change at once.
struct CountSteps: Equatable {
    /// When the first step shows.
    let start: Date
    /// The seconds shown as the end moved.
    let from: Int
    /// The steps from `from` to the time left as the end moved.
    let count: Int

    init(start: Date, from: Int, to target: Int) {
        self.start = start
        self.from = from
        count = Self.distances(from: from, to: target).max() ?? 0
    }

    #if DEBUG
    /// The time between steps, and each step's roll; launch arguments `-stepPace` and `-stepRoll`
    /// try others.
    static let pace = UserDefaults.standard.object(forKey: "stepPace") == nil
        ? 0.1 : UserDefaults.standard.double(forKey: "stepPace")
    static let roll = UserDefaults.standard.object(forKey: "stepRoll") == nil
        ? 0.09 : UserDefaults.standard.double(forKey: "stepRoll")
    #else
    static let pace = 0.1
    static let roll = 0.09
    #endif

    /// Steps past the last that a second going by can still need: across a tens, a tick can
    /// lengthen the ones' way (0:20 to 0:19).
    private static let spare = 3

    /// When each step shows, the first at `start`.
    var dates: [Date] {
        (0 ..< count + Self.spare).map { start.addingTimeInterval(Double($0) * Self.pace) }
    }

    /// The step showing at `date`: 0 before the first, nil once the last is done.
    func step(at date: Date) -> Int? {
        let elapsed = date.timeIntervalSince(start)
        guard elapsed >= 0 else { return 0 }
        let step = Int(elapsed / Self.pace) + 1
        return step <= count + Self.spare ? step : nil
    }

    /// The seconds shown `step` steps from `from` toward `target`, each place `step` digits up
    /// its own wheel, or at its target if that is nearer.
    static func seconds(from: Int, to target: Int, step: Int) -> Int {
        let start = places(from)
        let end = places(target)
        return bases.indices.reduce(0) { seconds, index in
            let way = (end[index] - start[index] + bases[index]) % bases[index]
            return seconds + (start[index] + min(step, way)) % bases[index] * units[index]
        }
    }

    /// Each place's digits, and what one of it is in seconds: the seconds' ones and tens, then
    /// the minutes' ones, tens, and hundreds.
    private static let bases = [10, 6, 10, 10, 10]
    private static let units = [1, 10, 60, 600, 6000]

    private static func places(_ seconds: Int) -> [Int] {
        let minutes = max(0, seconds) / 60
        return [
            max(0, seconds) % 10,
            max(0, seconds) % 60 / 10,
            minutes % 10,
            minutes / 10 % 10,
            minutes / 100 % 10,
        ]
    }

    private static func distances(from: Int, to target: Int) -> [Int] {
        let start = places(from)
        let end = places(target)
        return bases.indices.map { (end[$0] - start[$0] + bases[$0]) % bases[$0] }
    }
}

/// A count's whole seconds (`RestSchedule`) and, after a +15 s, each of its steps.
struct SteppedSchedule: TimelineSchedule {
    let rest: RestSchedule
    let steps: [Date]

    func entries(from startDate: Date, mode: Mode) -> AnyIterator<Date> {
        let seconds = rest.entries(from: startDate, mode: mode)
        var nextSecond = seconds.next()
        var steps = steps.filter { $0 > startDate }[...]
        return AnyIterator {
            if let step = steps.first, nextSecond.map({ step < $0 }) ?? true {
                steps.removeFirst()
                return step
            }
            defer { nextSecond = seconds.next() }
            return nextSecond
        }
    }
}

/// `RestBlock.countdown`: the count, stepping up after a +15 s while it runs and turns.
struct SteppedCountdown: View {
    let block: RestBlock
    let size: CGFloat
    let locale: Locale
    let turns: Bool
    let color: ColorToken
    let shown: ClosedRange<Double>

    @State private var steps: CountSteps?
    /// The end and whether the count ran, as last drawn.
    @State private var seen: Seen?

    struct Seen: Equatable {
        var ends: Date
        var ticks: Bool
    }

    private var now: Seen {
        Seen(ends: block.ends, ticks: block.stage == .open && block.pausedLeft == nil)
    }

    /// A +15 s: a running count's end moved later, not a resume's.
    private func isStepUp(from old: Seen, to new: Seen) -> Bool {
        turns && old.ticks && new.ticks && new.ends > old.ends.addingTimeInterval(0.5)
    }

    var body: some View {
        // In the update that moves the end, before the change below has started the steps, the
        // count as it was: drawn from the new end, the new time showed a frame ahead of them.
        let pending = seen.map { isStepUp(from: $0, to: now) } ?? false
        (pending ? block.ending(at: seen?.ends ?? block.ends) : block)
            .drawn(for: self, steps: steps)
            .onChange(of: now) { old, new in
                if isStepUp(from: old, to: new) {
                    let date = Date.now
                    let from = block.ending(at: old.ends)
                        .figure(at: date, within: shown, steps: steps).seconds
                    steps = CountSteps(
                        start: date,
                        from: Int(from.rounded(.up)),
                        to: Int(block.left(at: date, within: shown).rounded(.up)),
                    )
                }
                seen = new
            }
            .onAppear { seen = now }
    }
}
