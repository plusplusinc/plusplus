import Foundation

/// Reassembles repo files back into an `ExportBundle` — the inverse of
/// `FileLayout.templateFiles` + session placement. The app uses this to apply
/// sync PULLS: the engine hands back the remote bytes for paths the local
/// store should adopt, and this turns that per-file map into one bundle to run
/// through the normal import path (upsert exercises, replace-or-create
/// routines, append sessions). Files under unknown paths are ignored — a
/// user's README or skills never round-trip through import.
public enum InterchangeFiles {
    public static func bundle(from files: [FileWrite]) throws -> ExportBundle {
        var exercises: [ExerciseDTO] = []
        var routines: [RoutineDTO] = []
        var equipment: [EquipmentDTO] = []
        var libraries: [EquipmentLibraryDTO] = []
        var sessions: [SessionDTO] = []

        for file in files.sorted(by: { $0.path < $1.path }) {
            // Only .json documents are interchange payloads: history also
            // carries .gpx route sidecars (#378), and force-decoding one as
            // a SessionDocument would fail the whole pull. Sidecars are
            // paired and attached by the app's sync layer, not here.
            guard file.path.hasSuffix(".json") else { continue }
            if file.path.hasPrefix(FileLayout.exercisesDirectory + "/") {
                exercises.append(try InterchangeCodec.decode(ExerciseDocument.self, from: file.data).exercise)
            } else if file.path.hasPrefix(FileLayout.routinesDirectory + "/") {
                routines.append(try InterchangeCodec.decode(RoutineDocument.self, from: file.data).routine)
            } else if file.path.hasPrefix(FileLayout.equipmentLibrariesDirectory + "/") {
                libraries.append(try InterchangeCodec.decode(EquipmentLibraryDocument.self, from: file.data).library)
            } else if file.path.hasPrefix(FileLayout.equipmentDirectory + "/") {
                equipment.append(try InterchangeCodec.decode(EquipmentDocument.self, from: file.data).equipment)
            } else if file.path.hasPrefix(FileLayout.historyDirectory + "/") {
                sessions.append(try InterchangeCodec.decode(SessionDocument.self, from: file.data).session)
            }
            // Anything else (README, CLAUDE.md, skills): not ours, skip.
        }

        return ExportBundle(
            exercises: exercises,
            routines: routines,
            sessions: sessions,
            equipment: equipment.isEmpty ? nil : equipment,
            equipmentLibraries: libraries.isEmpty ? nil : libraries
        )
    }
}
