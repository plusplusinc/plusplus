import Foundation

extension Store {
    /// Diffs the workout's stored rows against `rows` by id: a row gone is deleted, a new one
    /// inserted, and each written at its place. A stored row whose exercise this build can't
    /// read, never in `rows` since loading leaves it out, is kept rather than taken for one gone,
    /// as logged sets are (`writeSets`), and stays right after the row it followed, or the
    /// nearest earlier one still kept; first, with none.
    func writeRows(_ rows: [WorkoutExercise], of workout: StoredRoutine) throws {
        let old = (workout.exercises ?? []).sorted { $0.position < $1.position }
        let list = try exercises()
        let kept = Set(rows.map(\.id))
        // Each unreadable row under the id of the kept row it follows, nil for none.
        var unreadable: [UUID?: [StoredRoutineExercise]] = [:]
        var lastKept: UUID?
        for row in old {
            if list.exercise(id: row.exerciseID) == nil {
                unreadable[lastKept, default: []].append(row)
            } else if kept.contains(row.id) {
                lastKept = row.id
            } else {
                modelContext.delete(row)
            }
        }
        // Row ids are unique in the app's own writes; keyed leniently against a store that isn't.
        let byID = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var ordered = unreadable[nil] ?? []
        for item in rows {
            let row = byID[item.id] ?? {
                let new = StoredRoutineExercise(
                    id: item.id,
                    exerciseID: item.exercise.id,
                    position: 0,
                )
                modelContext.insert(new)
                new.routine = workout
                return new
            }()
            row.write(item.plan)
            row.write(roundRest: item.roundRest)
            row.update(\.supersetID, to: item.supersetID)
            ordered.append(row)
            ordered += unreadable[item.id] ?? []
        }
        for (position, row) in ordered.enumerated() {
            row.update(\.position, to: position)
        }
    }
}
