import Foundation

struct CatalogExercise: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let muscleGroup: String
    let primaryMuscle: String
    let classification: String

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }

    static func == (lhs: CatalogExercise, rhs: CatalogExercise) -> Bool {
        lhs.name == rhs.name
    }
}

enum ExerciseCatalog {

    static let exercises: [CatalogExercise] = [
        // MARK: - Chest
        CatalogExercise(name: "Barbell Bench Press", muscleGroup: "Chest", primaryMuscle: "Pectoralis Major", classification: "Barbell"),
        CatalogExercise(name: "Incline Barbell Press", muscleGroup: "Chest", primaryMuscle: "Upper Pectoralis", classification: "Barbell"),
        CatalogExercise(name: "Decline Bench Press", muscleGroup: "Chest", primaryMuscle: "Lower Pectoralis", classification: "Barbell"),
        CatalogExercise(name: "Dumbbell Bench Press", muscleGroup: "Chest", primaryMuscle: "Pectoralis Major", classification: "Dumbbell"),
        CatalogExercise(name: "Incline Dumbbell Press", muscleGroup: "Chest", primaryMuscle: "Upper Pectoralis", classification: "Dumbbell"),
        CatalogExercise(name: "Dumbbell Flye", muscleGroup: "Chest", primaryMuscle: "Pectoralis Major", classification: "Dumbbell"),
        CatalogExercise(name: "Cable Flye", muscleGroup: "Chest", primaryMuscle: "Pectoralis Major", classification: "Cable"),
        CatalogExercise(name: "Machine Chest Press", muscleGroup: "Chest", primaryMuscle: "Pectoralis Major", classification: "Machine"),
        CatalogExercise(name: "Push-Up", muscleGroup: "Chest", primaryMuscle: "Pectoralis Major", classification: "Bodyweight"),
        CatalogExercise(name: "Dips (Chest)", muscleGroup: "Chest", primaryMuscle: "Lower Pectoralis", classification: "Bodyweight"),

        // MARK: - Back
        CatalogExercise(name: "Deadlift", muscleGroup: "Back", primaryMuscle: "Erector Spinae", classification: "Barbell"),
        CatalogExercise(name: "Barbell Row", muscleGroup: "Back", primaryMuscle: "Latissimus Dorsi", classification: "Barbell"),
        CatalogExercise(name: "T-Bar Row", muscleGroup: "Back", primaryMuscle: "Mid Back", classification: "Barbell"),
        CatalogExercise(name: "Dumbbell Row", muscleGroup: "Back", primaryMuscle: "Latissimus Dorsi", classification: "Dumbbell"),
        CatalogExercise(name: "Pull-Up", muscleGroup: "Back", primaryMuscle: "Latissimus Dorsi", classification: "Bodyweight"),
        CatalogExercise(name: "Chin-Up", muscleGroup: "Back", primaryMuscle: "Latissimus Dorsi", classification: "Bodyweight"),
        CatalogExercise(name: "Lat Pulldown", muscleGroup: "Back", primaryMuscle: "Latissimus Dorsi", classification: "Cable"),
        CatalogExercise(name: "Seated Cable Row", muscleGroup: "Back", primaryMuscle: "Rhomboids", classification: "Cable"),
        CatalogExercise(name: "Face Pull", muscleGroup: "Back", primaryMuscle: "Rear Deltoid", classification: "Cable"),
        CatalogExercise(name: "Hyperextension", muscleGroup: "Back", primaryMuscle: "Erector Spinae", classification: "Bodyweight"),

        // MARK: - Shoulders
        CatalogExercise(name: "Overhead Press", muscleGroup: "Shoulders", primaryMuscle: "Anterior Deltoid", classification: "Barbell"),
        CatalogExercise(name: "Dumbbell Shoulder Press", muscleGroup: "Shoulders", primaryMuscle: "Anterior Deltoid", classification: "Dumbbell"),
        CatalogExercise(name: "Arnold Press", muscleGroup: "Shoulders", primaryMuscle: "Deltoids", classification: "Dumbbell"),
        CatalogExercise(name: "Lateral Raise", muscleGroup: "Shoulders", primaryMuscle: "Lateral Deltoid", classification: "Dumbbell"),
        CatalogExercise(name: "Cable Lateral Raise", muscleGroup: "Shoulders", primaryMuscle: "Lateral Deltoid", classification: "Cable"),
        CatalogExercise(name: "Front Raise", muscleGroup: "Shoulders", primaryMuscle: "Anterior Deltoid", classification: "Dumbbell"),
        CatalogExercise(name: "Reverse Flye", muscleGroup: "Shoulders", primaryMuscle: "Rear Deltoid", classification: "Dumbbell"),
        CatalogExercise(name: "Machine Shoulder Press", muscleGroup: "Shoulders", primaryMuscle: "Anterior Deltoid", classification: "Machine"),
        CatalogExercise(name: "Upright Row", muscleGroup: "Shoulders", primaryMuscle: "Lateral Deltoid", classification: "Barbell"),
        CatalogExercise(name: "Shrugs", muscleGroup: "Shoulders", primaryMuscle: "Trapezius", classification: "Dumbbell"),

        // MARK: - Biceps
        CatalogExercise(name: "Barbell Curl", muscleGroup: "Arms", primaryMuscle: "Biceps Brachii", classification: "Barbell"),
        CatalogExercise(name: "Dumbbell Curl", muscleGroup: "Arms", primaryMuscle: "Biceps Brachii", classification: "Dumbbell"),
        CatalogExercise(name: "Hammer Curl", muscleGroup: "Arms", primaryMuscle: "Brachioradialis", classification: "Dumbbell"),
        CatalogExercise(name: "Preacher Curl", muscleGroup: "Arms", primaryMuscle: "Biceps Brachii", classification: "Barbell"),
        CatalogExercise(name: "Cable Curl", muscleGroup: "Arms", primaryMuscle: "Biceps Brachii", classification: "Cable"),
        CatalogExercise(name: "Concentration Curl", muscleGroup: "Arms", primaryMuscle: "Biceps Brachii", classification: "Dumbbell"),
        CatalogExercise(name: "Incline Dumbbell Curl", muscleGroup: "Arms", primaryMuscle: "Biceps Long Head", classification: "Dumbbell"),

        // MARK: - Triceps
        CatalogExercise(name: "Tricep Pushdown", muscleGroup: "Arms", primaryMuscle: "Triceps Brachii", classification: "Cable"),
        CatalogExercise(name: "Skull Crusher", muscleGroup: "Arms", primaryMuscle: "Triceps Brachii", classification: "Barbell"),
        CatalogExercise(name: "Overhead Tricep Extension", muscleGroup: "Arms", primaryMuscle: "Triceps Long Head", classification: "Dumbbell"),
        CatalogExercise(name: "Close-Grip Bench Press", muscleGroup: "Arms", primaryMuscle: "Triceps Brachii", classification: "Barbell"),
        CatalogExercise(name: "Tricep Dips", muscleGroup: "Arms", primaryMuscle: "Triceps Brachii", classification: "Bodyweight"),
        CatalogExercise(name: "Cable Overhead Extension", muscleGroup: "Arms", primaryMuscle: "Triceps Long Head", classification: "Cable"),
        CatalogExercise(name: "Kickback", muscleGroup: "Arms", primaryMuscle: "Triceps Lateral Head", classification: "Dumbbell"),

        // MARK: - Legs (Quads)
        CatalogExercise(name: "Barbell Squat", muscleGroup: "Legs", primaryMuscle: "Quadriceps", classification: "Barbell"),
        CatalogExercise(name: "Front Squat", muscleGroup: "Legs", primaryMuscle: "Quadriceps", classification: "Barbell"),
        CatalogExercise(name: "Leg Press", muscleGroup: "Legs", primaryMuscle: "Quadriceps", classification: "Machine"),
        CatalogExercise(name: "Hack Squat", muscleGroup: "Legs", primaryMuscle: "Quadriceps", classification: "Machine"),
        CatalogExercise(name: "Leg Extension", muscleGroup: "Legs", primaryMuscle: "Quadriceps", classification: "Machine"),
        CatalogExercise(name: "Bulgarian Split Squat", muscleGroup: "Legs", primaryMuscle: "Quadriceps", classification: "Dumbbell"),
        CatalogExercise(name: "Goblet Squat", muscleGroup: "Legs", primaryMuscle: "Quadriceps", classification: "Dumbbell"),
        CatalogExercise(name: "Walking Lunge", muscleGroup: "Legs", primaryMuscle: "Quadriceps", classification: "Dumbbell"),

        // MARK: - Legs (Hamstrings & Glutes)
        CatalogExercise(name: "Romanian Deadlift", muscleGroup: "Legs", primaryMuscle: "Hamstrings", classification: "Barbell"),
        CatalogExercise(name: "Leg Curl", muscleGroup: "Legs", primaryMuscle: "Hamstrings", classification: "Machine"),
        CatalogExercise(name: "Hip Thrust", muscleGroup: "Legs", primaryMuscle: "Gluteus Maximus", classification: "Barbell"),
        CatalogExercise(name: "Glute Bridge", muscleGroup: "Legs", primaryMuscle: "Gluteus Maximus", classification: "Bodyweight"),
        CatalogExercise(name: "Good Morning", muscleGroup: "Legs", primaryMuscle: "Hamstrings", classification: "Barbell"),
        CatalogExercise(name: "Nordic Hamstring Curl", muscleGroup: "Legs", primaryMuscle: "Hamstrings", classification: "Bodyweight"),

        // MARK: - Legs (Calves)
        CatalogExercise(name: "Standing Calf Raise", muscleGroup: "Legs", primaryMuscle: "Gastrocnemius", classification: "Machine"),
        CatalogExercise(name: "Seated Calf Raise", muscleGroup: "Legs", primaryMuscle: "Soleus", classification: "Machine"),

        // MARK: - Core
        CatalogExercise(name: "Plank", muscleGroup: "Core", primaryMuscle: "Rectus Abdominis", classification: "Bodyweight"),
        CatalogExercise(name: "Hanging Leg Raise", muscleGroup: "Core", primaryMuscle: "Lower Abs", classification: "Bodyweight"),
        CatalogExercise(name: "Cable Crunch", muscleGroup: "Core", primaryMuscle: "Rectus Abdominis", classification: "Cable"),
        CatalogExercise(name: "Ab Wheel Rollout", muscleGroup: "Core", primaryMuscle: "Rectus Abdominis", classification: "Bodyweight"),
        CatalogExercise(name: "Russian Twist", muscleGroup: "Core", primaryMuscle: "Obliques", classification: "Bodyweight"),
        CatalogExercise(name: "Woodchopper", muscleGroup: "Core", primaryMuscle: "Obliques", classification: "Cable"),

        // MARK: - Cardio
        CatalogExercise(name: "Treadmill Run", muscleGroup: "Cardio", primaryMuscle: "Full Body", classification: "Cardio"),
        CatalogExercise(name: "Rowing Machine", muscleGroup: "Cardio", primaryMuscle: "Full Body", classification: "Cardio"),
        CatalogExercise(name: "Stairmaster", muscleGroup: "Cardio", primaryMuscle: "Quadriceps", classification: "Cardio"),
        CatalogExercise(name: "Cycling", muscleGroup: "Cardio", primaryMuscle: "Quadriceps", classification: "Cardio"),
        CatalogExercise(name: "Jump Rope", muscleGroup: "Cardio", primaryMuscle: "Full Body", classification: "Cardio"),
        CatalogExercise(name: "Battle Ropes", muscleGroup: "Cardio", primaryMuscle: "Full Body", classification: "Cardio"),
        CatalogExercise(name: "Elliptical", muscleGroup: "Cardio", primaryMuscle: "Full Body", classification: "Cardio"),
    ]

    static var muscleGroups: [String] {
        Array(Set(exercises.map(\.muscleGroup))).sorted()
    }

    static var primaryMuscles: [String] {
        Array(Set(exercises.map(\.primaryMuscle))).sorted()
    }

    static var classifications: [String] {
        Array(Set(exercises.map(\.classification))).sorted()
    }

    static func filtered(
        muscleGroup: String? = nil,
        primaryMuscle: String? = nil,
        classification: String? = nil,
        search: String = ""
    ) -> [CatalogExercise] {
        exercises.filter { ex in
            if let mg = muscleGroup, mg != "All", ex.muscleGroup != mg { return false }
            if let pm = primaryMuscle, pm != "All", ex.primaryMuscle != pm { return false }
            if let cl = classification, cl != "All", ex.classification != cl { return false }
            if !search.isEmpty {
                let q = search.lowercased()
                return ex.name.lowercased().contains(q)
                    || ex.muscleGroup.lowercased().contains(q)
                    || ex.primaryMuscle.lowercased().contains(q)
            }
            return true
        }
        .sorted { $0.name < $1.name }
    }
}
