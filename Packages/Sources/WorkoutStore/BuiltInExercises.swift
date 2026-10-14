extension Exercise {
    /// The exercises that come with the app, A to Z.
    ///
    /// Grouped here by muscle group, for reading only. A name is plain when there is one common
    /// version; a variant carries its implement in the name, as its own exercise.
    public static let builtIn: [Self] = [
        // Chest
        Self(id: "push-up", name: "Push-up", muscleGroup: .chest),
        Self(id: "ring-push-up", name: "Ring push-up", muscleGroup: .chest, equipment: [.rings]),
        Self(
            id: "dumbbell-bench-press",
            name: "Dumbbell bench press",
            muscleGroup: .chest,
            equipment: [.dumbbells, .bench],
        ),
        Self(
            id: "incline-dumbbell-press",
            name: "Incline dumbbell press",
            muscleGroup: .chest,
            equipment: [.dumbbells, .bench],
        ),
        Self(
            id: "barbell-bench-press",
            name: "Barbell bench press",
            muscleGroup: .chest,
            equipment: [.barbell, .bench],
        ),
        Self(id: "ring-dip", name: "Ring dip", muscleGroup: .chest, equipment: [.rings]),
        Self(
            id: "doorway-chest-stretch",
            name: "Doorway chest stretch",
            muscleGroup: .chest,
            isStretch: true,
        ),
        // Back
        Self(id: "pull-up", name: "Pull-up", muscleGroup: .back, equipment: [.pullUpBar]),
        Self(id: "chin-up", name: "Chin-up", muscleGroup: .back, equipment: [.pullUpBar]),
        Self(id: "inverted-row", name: "Inverted row", muscleGroup: .back, equipment: [.rings]),
        Self(
            id: "dumbbell-row",
            name: "Dumbbell row",
            muscleGroup: .back,
            equipment: [.dumbbells, .bench],
        ),
        Self(id: "barbell-row", name: "Barbell row", muscleGroup: .back, equipment: [.barbell]),
        Self(id: "dead-hang", name: "Dead hang", muscleGroup: .back, equipment: [.pullUpBar]),
        Self(id: "childs-pose", name: "Child\u{2019}s pose", muscleGroup: .back, isStretch: true),
        Self(id: "cat-cow", name: "Cat-cow", muscleGroup: .back, isStretch: true),
        Self(
            id: "thoracic-rotation",
            name: "Thoracic rotation",
            muscleGroup: .back,
            isStretch: true,
        ),
        // Shoulders
        Self(
            id: "overhead-press",
            name: "Overhead press",
            muscleGroup: .shoulders,
            equipment: [.dumbbells],
        ),
        Self(
            id: "barbell-overhead-press",
            name: "Barbell overhead press",
            muscleGroup: .shoulders,
            equipment: [.barbell],
        ),
        Self(
            id: "lateral-raise",
            name: "Lateral raise",
            muscleGroup: .shoulders,
            equipment: [.dumbbells],
        ),
        Self(id: "face-pull", name: "Face pull", muscleGroup: .shoulders, equipment: [.band]),
        Self(
            id: "band-pull-apart",
            name: "Band pull-apart",
            muscleGroup: .shoulders,
            equipment: [.band],
        ),
        Self(
            id: "cross-body-shoulder-stretch",
            name: "Cross-body shoulder stretch",
            muscleGroup: .shoulders,
            isStretch: true,
        ),
        Self(
            id: "band-shoulder-dislocate",
            name: "Band shoulder dislocate",
            muscleGroup: .shoulders,
            isStretch: true,
            equipment: [.band],
        ),
        // Arms
        Self(id: "biceps-curl", name: "Biceps curl", muscleGroup: .arms, equipment: [.dumbbells]),
        Self(id: "hammer-curl", name: "Hammer curl", muscleGroup: .arms, equipment: [.dumbbells]),
        Self(
            id: "triceps-extension",
            name: "Triceps extension",
            muscleGroup: .arms,
            equipment: [.dumbbells],
        ),
        // Legs
        Self(
            id: "goblet-squat",
            name: "Goblet squat",
            muscleGroup: .legs,
            equipment: [.kettlebell],
        ),
        Self(
            id: "barbell-back-squat",
            name: "Barbell back squat",
            muscleGroup: .legs,
            equipment: [.barbell],
        ),
        Self(
            id: "bulgarian-split-squat",
            name: "Bulgarian split squat",
            muscleGroup: .legs,
            equipment: [.dumbbells, .bench],
        ),
        Self(
            id: "reverse-lunge",
            name: "Reverse lunge",
            muscleGroup: .legs,
            equipment: [.dumbbells],
        ),
        Self(id: "step-up", name: "Step-up", muscleGroup: .legs, equipment: [.dumbbells, .bench]),
        Self(id: "calf-raise", name: "Calf raise", muscleGroup: .legs, equipment: [.dumbbells]),
        Self(
            id: "romanian-deadlift",
            name: "Romanian deadlift",
            muscleGroup: .legs,
            equipment: [.dumbbells],
        ),
        Self(
            id: "barbell-deadlift",
            name: "Barbell deadlift",
            muscleGroup: .legs,
            equipment: [.barbell],
        ),
        Self(
            id: "kettlebell-swing",
            name: "Kettlebell swing",
            muscleGroup: .legs,
            equipment: [.kettlebell],
        ),
        Self(id: "glute-bridge", name: "Glute bridge", muscleGroup: .legs),
        Self(
            id: "balance-board-hold",
            name: "Balance board hold",
            muscleGroup: .legs,
            equipment: [.balanceBoard],
        ),
        Self(
            id: "kneeling-hip-flexor-stretch",
            name: "Kneeling hip flexor stretch",
            muscleGroup: .legs,
            isStretch: true,
        ),
        Self(
            id: "hamstring-stretch",
            name: "Hamstring stretch",
            muscleGroup: .legs,
            isStretch: true,
        ),
        Self(id: "pigeon-stretch", name: "Pigeon stretch", muscleGroup: .legs, isStretch: true),
        Self(id: "calf-stretch", name: "Calf stretch", muscleGroup: .legs, isStretch: true),
        Self(
            id: "worlds-greatest-stretch",
            name: "World\u{2019}s greatest stretch",
            muscleGroup: .legs,
            isStretch: true,
        ),
        // Core
        Self(id: "plank", name: "Plank", muscleGroup: .core),
        Self(id: "side-plank", name: "Side plank", muscleGroup: .core),
        Self(id: "dead-bug", name: "Dead bug", muscleGroup: .core),
        Self(
            id: "hanging-knee-raise",
            name: "Hanging knee raise",
            muscleGroup: .core,
            equipment: [.pullUpBar],
        ),
        Self(id: "pallof-press", name: "Pallof press", muscleGroup: .core, equipment: [.band]),
        Self(
            id: "turkish-get-up",
            name: "Turkish get-up",
            muscleGroup: .core,
            equipment: [.kettlebell],
        ),
        Self(
            id: "farmers-carry",
            name: "Farmer\u{2019}s carry",
            muscleGroup: .core,
            equipment: [.dumbbells],
        ),
    ].sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
}
