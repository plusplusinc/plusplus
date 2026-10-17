import DesignSystem
import WorkoutStore

extension RoutineSlot {
    /// The routine's slot for one dropped on the rail, joining what the rail's joins.
    init(_ slot: RailSlot<RoutineExercise.ID>) {
        let place: Place = switch slot.place {
        case let .before(id): .before(id)
        case .end: .end
        }
        let joining: RoutineNeighbor? = switch slot.joining {
        case .above: .above
        case .below: .below
        case nil: nil
        }
        self.init(place, joining: joining)
    }
}
