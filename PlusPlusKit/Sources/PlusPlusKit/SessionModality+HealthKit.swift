#if canImport(HealthKit)
import HealthKit

/// How a session's modality files in Apple Health.
///
/// This lives in the Kit — behind the same `canImport` guard the XML and
/// networking shims use, so Linux still builds — because the phone and the
/// watch both need it and they must not disagree. They did before: a bike
/// ride logged from the phone and the same ride logged from the wrist both
/// arrived as `.traditionalStrengthTraining`, because each device had its
/// own two-value ternary that only knew "outdoor run" from "everything
/// else". Two copies of a rule is how they drift; this is one.
public extension SessionModality {
    /// The activity type Health should file this workout under.
    ///
    /// A session that mixes families does not get to claim one of them:
    /// strength alongside cardio is cross-training, and several cardio
    /// families with no lifting is mixed cardio. Both are real Apple
    /// types, and both earn rings correctly.
    var healthActivityType: HKWorkoutActivityType {
        if isMixed {
            return primary.isCardio ? .mixedCardio : .crossTraining
        }
        switch primary {
        case .strength: return .traditionalStrengthTraining
        case .flexibility: return .flexibility
        case .running: return .running
        case .walking: return .walking
        case .hiking: return .hiking
        case .cycling: return .cycling
        case .rowing: return .rowing
        case .swimming: return .swimming
        case .elliptical: return .elliptical
        case .stairClimbing: return .stairClimbing
        case .jumpRope: return .jumpRope
        // Cardio we can measure but cannot name — a ski erg, an unlabelled
        // console. `.mixedCardio` is the honest bucket and still earns
        // rings, where `.other` would not.
        case .cardio: return .mixedCardio
        }
    }

    var healthLocationType: HKWorkoutSessionLocationType {
        isOutdoor ? .outdoor : .indoor
    }

    /// The configuration a live session or a retrospective builder is
    /// started with. One place, so the phone and the wrist cannot file the
    /// same workout two different ways.
    var healthConfiguration: HKWorkoutConfiguration {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = healthActivityType
        configuration.locationType = healthLocationType
        return configuration
    }
}
#endif
