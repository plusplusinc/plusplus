import Foundation

// Typing a number into the sheet. The field's raw text is digits, and for a weight one decimal
// separator; it is filtered as it changes, shown as it reads (a time fills from the right, as a
// microwave's does), and committed when typing ends.

extension RoutineExercise {
    /// `raw` with only what `part` accepts: digits up to its limit, and for a weight one
    /// separator ("." or ",") and two decimals.
    public func filtered(_ raw: String, for part: PlanPart) -> String {
        guard part == .weight else {
            return String(raw.filter(\.isASCIIDigit).prefix(digitLimit(part)))
        }
        var whole = ""
        var fraction: String?
        for character in raw {
            if character.isASCIIDigit {
                if fraction != nil {
                    if fraction?.count ?? 0 < 2 {
                        fraction?.append(character)
                    }
                } else if whole.count < digits(PlanLimits.maxWeight) {
                    whole.append(character)
                }
            } else if character == "." || character == ",", fraction == nil {
                whole.append(character)
                fraction = ""
            }
        }
        return whole + (fraction ?? "")
    }

    /// What the field shows for `raw` while typing: a time's digits fill from the right, so 1, 3,
    /// 0 reads "1:30" and 5 reads "0:05"; anything else as typed.
    public func typedText(_ raw: String, for part: PlanPart) -> String {
        guard part == .target, case .time = plan.target, !raw.isEmpty else { return raw }
        let padded = String(repeating: "0", count: max(0, 3 - raw.count)) + raw
        return "\(padded.dropLast(2)):\(padded.suffix(2))"
    }

    /// Sets `part` from typed `raw` text. Sets, reps, and time keep their value when nothing or
    /// zero was typed, and stop at their limits; a weight typed empty or zero is not set, and a
    /// new one takes `newWeightUnit`.
    public mutating func commit(typed raw: String, into part: PlanPart, newWeightUnit: WeightUnit) {
        switch part {
        case .sets:
            if let sets = Int(raw), sets > 0 {
                plan.sets = min(sets, PlanLimits.sets.upperBound)
            }
        case .target:
            switch plan.target {
            case .reps:
                if let reps = Int(raw), reps > 0 {
                    plan.target = .reps(min(reps, PlanLimits.reps.upperBound))
                }
            case .time:
                let digits = Int(raw) ?? 0
                let seconds = digits / 100 * 60 + digits % 100
                if seconds > 0 {
                    plan.target = .time(seconds: min(seconds, PlanLimits.seconds.upperBound))
                }
            }
        case .weight:
            // A lone separator is nothing typed; only an emptied field clears the weight.
            guard exercise.load != nil, raw.isEmpty || raw.contains(where: \.isNumber)
            else { return }
            let amount = Double(raw.replacingOccurrences(of: ",", with: ".")) ?? 0
            guard amount > 0 else {
                plan.weight = nil
                return
            }
            let rounded = (min(amount, PlanLimits.maxWeight) * 100).rounded() / 100
            plan.weight = Weight(rounded, plan.weight?.unit ?? newWeightUnit)
        }
    }

    /// As many digits as the part's largest value has; a weight's whole number is limited in
    /// `filtered`. Time is typed as minutes and seconds, 99:59 as 4 digits.
    private func digitLimit(_ part: PlanPart) -> Int {
        switch (part, plan.target) {
        case (.sets, _): digits(PlanLimits.sets.upperBound)
        case (_, .reps): digits(PlanLimits.reps.upperBound)
        case (_, .time): 4
        }
    }

    private func digits(_ value: some BinaryInteger) -> Int {
        String(value).count
    }

    private func digits(_ value: Double) -> Int {
        digits(Int(value))
    }
}

extension Character {
    fileprivate var isASCIIDigit: Bool {
        isASCII && isNumber
    }
}
