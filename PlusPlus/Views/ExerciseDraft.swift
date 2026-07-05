import Foundation
import Observation
import PlusPlusKit

/// Editable state for creating or editing a custom exercise. Pure logic —
/// validation and normalization live here, SwiftUI-free, so they're unit
/// testable without a ModelContainer (same pattern as ExerciseFilterState).
@Observable
final class ExerciseDraft {
    var name = ""
    var muscleGroup: MuscleGroup = .chest
    var exerciseType: ExerciseType = .weightReps
    var selectedEquipment: Set<Equipment> = []
    var notes = ""
    var videoURL = ""

    init() {}

    init(from exercise: Exercise) {
        name = exercise.name
        muscleGroup = exercise.muscleGroup
        exerciseType = exercise.exerciseType
        selectedEquipment = Set(exercise.equipment)
        notes = exercise.notes ?? ""
        videoURL = exercise.videoURL ?? ""
    }

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    enum VideoURLResult: Equatable {
        case none
        case valid(String)
        case invalid
    }

    /// Empty input is fine (no video). Scheme-less input like "youtu.be/x"
    /// is upgraded to https. Anything that still doesn't parse to an
    /// http(s) URL with a host is invalid.
    var normalizedVideoURL: VideoURLResult {
        let trimmed = videoURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .none }

        let candidate: String
        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            candidate = trimmed
        } else if trimmed.contains("://") {
            return .invalid
        } else {
            candidate = "https://" + trimmed
        }

        guard let url = URL(string: candidate),
              let host = url.host, host.contains(".") else {
            return .invalid
        }
        return .valid(candidate)
    }

    /// Case-insensitive duplicate check. Pass the name being edited (if any)
    /// so an unchanged name doesn't count as its own duplicate.
    func isDuplicate(among existingNames: [String], excluding editedName: String? = nil) -> Bool {
        let target = trimmedName.lowercased()
        return existingNames.contains { candidate in
            let lowered = candidate.lowercased()
            return lowered == target && lowered != editedName?.lowercased()
        }
    }

    func canSave(existingNames: [String], editedName: String? = nil) -> Bool {
        !trimmedName.isEmpty
            && normalizedVideoURL != .invalid
            && !isDuplicate(among: existingNames, excluding: editedName)
    }

    /// Writes the draft onto a model object (new or existing).
    func apply(to exercise: Exercise) {
        exercise.name = trimmedName
        exercise.muscleGroup = muscleGroup
        exercise.exerciseType = exerciseType
        exercise.equipment = selectedEquipment.sorted { $0.name < $1.name }
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        exercise.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
        if case .valid(let url) = normalizedVideoURL {
            exercise.videoURL = url
        } else {
            exercise.videoURL = nil
        }
    }
}
