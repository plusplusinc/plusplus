import DesignSystem
import WorkoutStore

extension WorkoutSlot {
    /// The routine's slot for one dropped on the rail, joining what the rail's joins.
    init(_ slot: RailSlot<WorkoutExercise.ID>) {
        let place: Place = switch slot.place {
        case let .before(id): .before(id)
        case .end: .end
        }
        let joining: WorkoutNeighbor? = switch slot.joining {
        case .above: .above
        case .below: .below
        case nil: nil
        }
        self.init(place, joining: joining)
    }
}
