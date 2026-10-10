extension Exercise {
    /// The exercises that come with the app, A to Z.
    ///
    /// Grouped here for reading only. A name is plain when there is one common version; a
    /// variant carries its implement in the name, as its own exercise.
    public static let builtIn: [Self] = [
        // Push
        Self(id: "push-up", name: "Push-up"),
        Self(
            id: "dumbbell-bench-press",
            name: "Dumbbell bench press",
            equipment: [.dumbbells, .bench],
        ),
        Self(
            id: "incline-dumbbell-press",
            name: "Incline dumbbell press",
            equipment: [.dumbbells, .bench],
        ),
        Self(id: "barbell-bench-press", name: "Barbell bench press", equipment: [.barbell, .bench]),
        Self(id: "overhead-press", name: "Overhead press", equipment: [.dumbbells]),
        Self(id: "barbell-overhead-press", name: "Barbell overhead press", equipment: [.barbell]),
        Self(id: "ring-dip", name: "Ring dip", equipment: [.rings]),
        Self(id: "ring-push-up", name: "Ring push-up", equipment: [.rings]),
        Self(id: "lateral-raise", name: "Lateral raise", equipment: [.dumbbells]),
        Self(id: "triceps-extension", name: "Triceps extension", equipment: [.dumbbells]),
        // Pull
        Self(id: "pull-up", name: "Pull-up", equipment: [.pullUpBar]),
        Self(id: "chin-up", name: "Chin-up", equipment: [.pullUpBar]),
        Self(id: "inverted-row", name: "Inverted row", equipment: [.rings]),
        Self(id: "dumbbell-row", name: "Dumbbell row", equipment: [.dumbbells, .bench]),
        Self(id: "barbell-row", name: "Barbell row", equipment: [.barbell]),
        Self(id: "face-pull", name: "Face pull", equipment: [.band]),
        Self(id: "band-pull-apart", name: "Band pull-apart", equipment: [.band]),
        Self(id: "biceps-curl", name: "Biceps curl", equipment: [.dumbbells]),
        Self(id: "hammer-curl", name: "Hammer curl", equipment: [.dumbbells]),
        // Legs
        Self(id: "goblet-squat", name: "Goblet squat", equipment: [.kettlebell]),
        Self(id: "barbell-back-squat", name: "Barbell back squat", equipment: [.barbell]),
        Self(
            id: "bulgarian-split-squat",
            name: "Bulgarian split squat",
            equipment: [.dumbbells, .bench],
        ),
        Self(id: "reverse-lunge", name: "Reverse lunge", equipment: [.dumbbells]),
        Self(id: "romanian-deadlift", name: "Romanian deadlift", equipment: [.dumbbells]),
        Self(id: "barbell-deadlift", name: "Barbell deadlift", equipment: [.barbell]),
        Self(id: "kettlebell-swing", name: "Kettlebell swing", equipment: [.kettlebell]),
        Self(id: "glute-bridge", name: "Glute bridge"),
        Self(id: "step-up", name: "Step-up", equipment: [.dumbbells, .bench]),
        Self(id: "calf-raise", name: "Calf raise", equipment: [.dumbbells]),
        Self(id: "balance-board-hold", name: "Balance board hold", equipment: [.balanceBoard]),
        // Core and carries
        Self(id: "plank", name: "Plank"),
        Self(id: "side-plank", name: "Side plank"),
        Self(id: "dead-bug", name: "Dead bug"),
        Self(id: "hanging-knee-raise", name: "Hanging knee raise", equipment: [.pullUpBar]),
        Self(id: "pallof-press", name: "Pallof press", equipment: [.band]),
        Self(id: "turkish-get-up", name: "Turkish get-up", equipment: [.kettlebell]),
        Self(id: "farmers-carry", name: "Farmer\u{2019}s carry", equipment: [.dumbbells]),
        // Stretches
        Self(id: "kneeling-hip-flexor-stretch", name: "Kneeling hip flexor stretch"),
        Self(id: "hamstring-stretch", name: "Hamstring stretch"),
        Self(id: "pigeon-stretch", name: "Pigeon stretch"),
        Self(id: "calf-stretch", name: "Calf stretch"),
        Self(id: "childs-pose", name: "Child\u{2019}s pose"),
        Self(id: "cat-cow", name: "Cat-cow"),
        Self(id: "worlds-greatest-stretch", name: "World\u{2019}s greatest stretch"),
        Self(id: "thoracic-rotation", name: "Thoracic rotation"),
        Self(id: "doorway-chest-stretch", name: "Doorway chest stretch"),
        Self(id: "cross-body-shoulder-stretch", name: "Cross-body shoulder stretch"),
        Self(id: "dead-hang", name: "Dead hang", equipment: [.pullUpBar]),
        Self(id: "band-shoulder-dislocate", name: "Band shoulder dislocate", equipment: [.band]),
    ].sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
}
