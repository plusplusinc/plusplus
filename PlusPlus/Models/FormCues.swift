import Foundation

/// Spoken form cues (voice guidance, 2026-07-16): one short line per
/// BUILT-IN exercise, read aloud by `FormGuidanceSpeaker` when the
/// exercise's block starts in a live session. Content law, enforced by
/// `FormCuesTests`:
///
/// - FULL catalog coverage — a voice that speaks for some exercises and
///   goes silent for others reads as broken, so adding a SeedData row
///   means adding its cue here (the test fails until it exists).
/// - Setup + execution reminders only: body position, path, control.
///   Never programming advice (reps/loads live in the plan) and never
///   judgement — cues instruct, anti-shame style.
/// - Short enough to finish inside the default 15 s transition (#369):
///   one to three clauses, ≤ 120 characters, a single sentence. The
///   speaker prepends the exercise name, so lines don't repeat it.
/// - House copy rules apply even though the text is spoken: no em
///   dashes, no obligation words.
///
/// Custom exercises deliberately have no entry — we can't know the
/// movement behind a user's name, and a wrong cue is worse than
/// silence (the isLoadable can't-classify-intent rule).
enum FormCues {

    /// The spoken cue line for a built-in exercise; nil for customs
    /// (and anything else the catalog doesn't know).
    static func line(for exerciseName: String) -> String? {
        linesByName[exerciseName]
    }

    /// All cue keys — the coverage tests' iteration surface.
    static var exerciseNames: [String] { Array(linesByName.keys) }

    private static let linesByName: [String: String] = [
        // Chest
        "Bench Press": "Plant your feet, pin your shoulder blades, lower to mid chest, and press.",
        "Incline Bench Press": "Keep your ribs down and touch just below the collarbone.",
        "Dumbbell Bench Press": "Pin your shoulder blades and press both bells up evenly.",
        "Incline Dumbbell Press": "Lower to the upper chest with control and press without arching.",
        "Machine Chest Press": "Set the handles at mid chest and keep your shoulders down as you press.",
        "Smith Machine Bench Press": "Line the bar over mid chest, shoulder blades pinned, press without shrugging.",
        "Dumbbell Fly": "Keep a slight elbow bend, open wide to a chest stretch, squeeze back up.",
        "Cable Fly": "Soft elbows, chest tall, sweep the handles together without shrugging.",
        "Low-to-High Cable Fly": "Start low with soft elbows and sweep up to eye level.",
        "Pec Deck": "Back against the pad, soft elbows, squeeze together and open with control.",
        "Chest Dip": "Lean slightly forward, shoulders down, and lower with control.",
        "Push-Up": "One straight line from head to heels, core braced, chest to the floor.",
        "Deficit Push-Up": "Keep the plank rigid and go only as deep as your shoulders allow.",
        "Ring Push-Up": "Steady the rings, keep the body rigid, turn the rings out slightly at the top.",
        "Band Chest Press": "Stand braced, wrists straight, press to full lockout with control.",
        "Svend Press": "Squeeze the plates together hard the whole time you press.",

        // Back
        "Deadlift": "Bar over mid foot, flat back, brace hard, and push the floor away.",
        "Trap Bar Deadlift": "Sit your hips back, chest up, and stand up straight through the handles.",
        "Barbell Row": "Hinge at the hips, keep the back flat, pull to your lower ribs without jerking.",
        "Pendlay Row": "Reset each rep on the floor, back flat and parallel, pull fast to the chest.",
        "Dumbbell Row": "Flat back, pull the elbow to your hip, no torso twist.",
        "Chest-Supported Row": "Keep your chest glued to the pad, pull the elbows back, squeeze the blades.",
        "Seated Cable Row": "Sit tall, pull to your belly, and keep the shoulders down.",
        "Cable Row": "Chest tall, drive the elbows back, resist the return.",
        "Machine Row": "Chest on the pad, pull the elbows back, pause, return with control.",
        "Landmine Row": "Straddle the bar, hinge with a flat back, pull to your chest.",
        "Pull-Up": "Start from a full hang, pull your chest toward the bar, lower all the way.",
        "Chin-Up": "Start from a dead hang and pull your chin over the bar without swinging.",
        "Neutral-Grip Pull-Up": "Dead hang, drive the elbows down, chest toward the handles.",
        "Lat Pulldown": "Chest up, pull the bar to your collarbone, control it back up.",
        "Straight-Arm Pulldown": "Arms long with soft elbows, sweep the bar to your thighs.",
        "Ring Row": "Keep the body rigid like a plank and pull your chest to the rings.",
        "Suspension Row": "Straight line from head to heels, pull the handles to your ribs.",
        "Band Pull-Apart": "Arms at shoulder height, pull wide, squeeze the blades together.",
        "Back Extension": "Hinge at the hips and rise to a straight line, not beyond.",
        "Good Morning": "Soft knees, push your hips back until the hamstrings load, stand tall.",

        // Shoulders
        "Overhead Press": "Squeeze your glutes, keep ribs down, press until the bar is over your ears.",
        "Seated Dumbbell Press": "Back against the pad, forearms vertical, press without flaring the ribs.",
        "Dumbbell Shoulder Press": "Brace your core and press both bells overhead without leaning back.",
        "Machine Shoulder Press": "Set the handles at shoulder height and press without shrugging.",
        "Arnold Press": "Start palms in, rotate as you press, finish palms forward overhead.",
        "Push Press": "Shallow knee dip, drive up fast, lock the bar out overhead.",
        "Landmine Press": "Stagger your stance, brace, and press the bar up and away.",
        "Lateral Raise": "Soft elbows, lift to shoulder height, lower slowly.",
        "Cable Lateral Raise": "Stand tall and sweep the handle out to shoulder height with control.",
        "Front Raise": "Brace so you don't rock, raise to eye level, lower slowly.",
        "Plate Front Raise": "Arms long, raise the plate to eye level, no swing.",
        "Rear Delt Fly": "Hinge forward, soft elbows, sweep wide, no bounce.",
        "Reverse Pec Deck": "Chest on the pad, arms level, open wide and pause.",
        "Face Pull": "Pull to your face with the elbows high, then pull the rope apart.",
        "Upright Row": "Lead with the elbows and stop at chest height.",
        "Barbell Shrug": "Arms relaxed, lift straight up toward your ears, pause, lower slowly.",
        "Dumbbell Shrug": "Stand tall, shrug straight up, no rolling.",
        "Pike Push-Up": "Hips high, lower the crown of your head to the floor, press back up.",

        // Biceps
        "Barbell Curl": "Elbows pinned to your sides, curl without swinging, lower slowly.",
        "EZ Bar Curl": "Keep the elbows still and control the way down.",
        "Dumbbell Curl": "Elbows at your sides, curl up, lower on a slow count.",
        "Hammer Curl": "Palms facing in, curl without swinging, squeeze at the top.",
        "Incline Dumbbell Curl": "Lie back, let the arms hang long, curl without swinging.",
        "Preacher Curl": "Armpits snug on the pad, lower all the way, curl smoothly.",
        "Concentration Curl": "Brace the elbow on your thigh, curl slowly, squeeze.",
        "Cable Curl": "Elbows at your sides, curl to a full squeeze, resist the return.",
        "Band Curl": "Anchor the band well, keep the elbows still, stay smooth both directions.",
        "Zottman Curl": "Curl palms up, rotate at the top, lower palms down slowly.",
        "Spider Curl": "Chest on the pad, arms hanging straight down, curl with no swing.",

        // Triceps
        "Close-Grip Bench Press": "Hands shoulder width, elbows tucked, bar to the lower chest.",
        "Tricep Pushdown": "Elbows pinned to your sides, press to lockout, control the return.",
        "Rope Pushdown": "Split the rope apart at the bottom, elbows glued to your sides.",
        "Overhead Tricep Extension": "Elbows in and pointed up, lower behind your head, extend fully.",
        "Cable Overhead Extension": "Elbows by your ears, extend fully without flaring.",
        "Skull Crusher": "Elbows fixed and pointed up, lower to your forehead, extend smoothly.",
        "Tricep Dip": "Stay upright, elbows tracking back, press to lockout.",
        "Bench Dip": "Shoulders down away from your ears, elbows straight back.",
        "Diamond Push-Up": "Hands together under your chest, body rigid, elbows tracking back.",
        "Band Pushdown": "Elbows pinned, press to full lockout, resist the band back up.",
        "Tricep Kickback": "Hinge flat, keep the upper arm parallel to the floor, extend and pause.",

        // Quads
        "Squat": "Brace hard, knees out over the toes, hit depth, drive up through mid foot.",
        "Front Squat": "Elbows high, chest tall, sit straight down.",
        "Smith Machine Squat": "Set your feet slightly forward of the bar, brace, control the descent.",
        "Goblet Squat": "Hold the bell tight to your chest, sit deep, keep the chest tall.",
        "Kettlebell Goblet Squat": "Bell tight to your chest, elbows inside the knees at the bottom.",
        "Hack Squat": "Back flat on the pad, lower under control, drive through the whole foot.",
        "Leg Press": "Feet mid platform, stop before your hips curl up, press smoothly.",
        "Leg Extension": "Sit back in the seat, extend fully, pause, lower slowly.",
        "Bulgarian Split Squat": "Torso tall, drop the back knee straight down, drive through the front heel.",
        "Walking Lunge": "Long steps, torso tall, back knee toward the floor.",
        "Reverse Lunge": "Step back, drop the back knee, drive up through the front heel.",
        "Step-Up": "Whole foot on the box, drive through that heel, no push from the back leg.",
        "Box Squat": "Sit back to the box, pause without relaxing, drive straight up.",
        "Bodyweight Squat": "Feet shoulder width, chest tall, sit to depth, stand tall.",
        "Jump Squat": "Land soft and quiet, knees over toes, reset before each jump.",
        "Wall Sit": "Back flat on the wall, thighs parallel, breathe steadily.",
        "Sissy Squat": "Rise onto your toes, lean back in one line, bend at the knees only.",

        // Hamstrings
        "Romanian Deadlift": "Soft knees, push the hips back, bar close, stop at the hamstring stretch.",
        "Dumbbell Romanian Deadlift": "Hips back, flat back, bells sliding down your thighs.",
        "Stiff-Leg Deadlift": "Legs nearly straight, hinge from the hips, keep the back flat.",
        "Single-Leg Romanian Deadlift": "Hinge on one leg, keep the hips square, reach long, stand tall.",
        "Leg Curl": "Hips pinned to the pad, curl fully, return slowly.",
        "Nordic Curl": "Lower as slowly as you can, hips open, hands ready to catch.",
        "Glute-Ham Raise": "Stay straight from knees to shoulders, lower slowly, pull back up.",
        "Cable Pull-Through": "Hinge back into the hips and squeeze the glutes to stand.",
        "Slider Leg Curl": "Bridge the hips up and keep them up while the heels slide.",

        // Glutes
        "Hip Thrust": "Chin tucked, drive through your heels, squeeze hard at the top.",
        "Machine Hip Thrust": "Set the pad on your hips, reach full lockout, lower with control.",
        "Glute Bridge": "Heels close, push through them, squeeze the glutes at the top.",
        "Single-Leg Glute Bridge": "Keep the hips level, drive through one heel, pause at the top.",
        "Kettlebell Swing": "It's a hip hinge, not a squat: snap the hips and let the bell float.",
        "Sumo Deadlift": "Wide stance, knees out, chest up, push the floor apart.",
        "Cable Kickback": "Hips square, sweep the leg back with a squeeze, no arching.",
        "Curtsy Lunge": "Step back and across, torso tall, drive up through the front heel.",
        "Frog Pump": "Soles together, knees wide, pump the hips up and squeeze.",
        "Banded Lateral Walk": "Quarter squat, wide controlled steps, keep tension in the band.",
        "Fire Hydrant": "On all fours, core braced, lift the knee out without tilting.",

        // Calves
        "Standing Calf Raise": "Full stretch at the bottom, pause high on your toes at the top.",
        "Seated Calf Raise": "Slow reps, full stretch, full squeeze.",
        "Smith Machine Calf Raise": "Balls of your feet on the edge, stretch deep, rise high.",
        "Single-Leg Calf Raise": "Steady yourself, take one foot through its full range, no bouncing.",
        "Donkey Calf Raise": "Hinge over with hips back, stretch deep, finish tall.",
        "Calf Raise": "Rise high onto your toes, pause, lower into a full stretch.",

        // Core
        "Plank": "Straight line, glutes tight, ribs pulled in, breathe.",
        "Side Plank": "Stack your shoulders and feet, lift the hips into one straight line.",
        "Dead Bug": "Press the low back flat, reach opposite arm and leg, breathe slowly.",
        "Bird Dog": "Reach opposite arm and leg long, keep the hips level, no arching.",
        "Hollow Hold": "Low back on the floor, arms and legs long, ribs down.",
        "Crunch": "Curl ribs toward hips, chin off your chest, no neck pulling.",
        "Cable Crunch": "Hips still, crunch the ribs toward the hips, resist the way up.",
        "Sit-Up": "Roll up one vertebra at a time, no yanking on the neck.",
        "Russian Twist": "Sit tall, lean back slightly, rotate from the ribs not the arms.",
        "Hanging Knee Raise": "No swing, knees to your chest, lower with control.",
        "Hanging Leg Raise": "Legs straight, curl the hips up, no swinging between reps.",
        "Toes to Bar": "Tight hang, lats on, sweep the toes up to the bar.",
        "Ab Wheel Rollout": "Hips tucked, roll out only as far as your core holds.",
        "Mountain Climber": "Hips low and level, hands under shoulders, drive the knees fast.",
        "Bicycle Crunch": "Slow and controlled, opposite elbow to knee, shoulders off the floor.",
        "V-Up": "Reach hands and toes to meet over your hips, lower with control.",
        "Leg Raise": "Press the low back down, keep the legs long, lower slowly.",
        "Pallof Press": "Press the handle straight out and refuse the twist.",
        "Suitcase Carry": "One heavy side, shoulders level, walk tall without leaning.",
        "Farmer's Carry": "Grip tight, shoulders back, walk tall with quick steady steps.",
        "Woodchopper": "Arms long, rotate from the hips and ribs, pivot the back foot.",
        "Medicine Ball Slam": "Reach tall, slam with the whole body, pick it up with a flat back.",

        // Full body
        "Burpee": "Chest to the floor, snap the hips up, jump, and breathe.",
        "Clean and Press": "Keep the bar close on the pull, catch on the shoulders, brace, press.",
        "Power Clean": "Push the floor away, bar close, fast elbows into the catch.",
        "Kettlebell Clean and Press": "Keep the bell close so it rolls to your shoulder, then brace and press.",
        "Kettlebell Snatch": "Hike it back, snap the hips, punch through at the top.",
        "Thruster": "Front squat to depth, then drive the bar overhead in one motion.",
        "Dumbbell Thruster": "Bells at the shoulders, squat deep, drive up into the press.",
        "Turkish Get-Up": "Eyes on the bell, move slowly, own every position.",
        "Sled Push": "Lean into it, arms firm, drive with low powerful steps.",
        "Battle Rope Waves": "Slight squat, make the waves from your shoulders, keep breathing.",
        "Box Jump": "Land soft with your whole foot, stand tall, step down.",
        "Jump Rope": "Bounce on the balls of your feet, spin from the wrists, stay relaxed.",
        "Rowing": "Legs, then body, then arms, and reverse it on the way back.",
        "Assault Bike": "Push and pull with arms and legs together, settle into a rhythm.",
        "Stationary Bike": "Set the saddle so the knee stays soft at the bottom, spin smoothly.",
        "Treadmill Run": "Run tall with quick light steps, landing under your hips.",
        "Sandbag Carry": "Hug it high on your chest, brace, walk tall.",
        "Running": "Run tall, relaxed shoulders, quick light steps.",
        "Walking": "Walk tall, relaxed arms, steady rhythm.",
        "Cycling": "Light grip, steady cadence, knees tracking straight.",

        // Specialty bars
        "Safety Bar Squat": "The bar tips you forward, so stay tall, brace, and drive up.",
        "Safety Bar Good Morning": "Soft knees, hips back, flat back, stand tall.",
        "Swiss Bar Bench Press": "Neutral grip, elbows tucked, press smoothly to lockout.",
        "Swiss Bar Overhead Press": "Neutral grip, ribs down, press to full lockout.",
        "Cambered Bar Squat": "The bar wants to swing, so descend slowly and brace hard.",
        "Axle Deadlift": "Crush the thick bar, flat back, push the floor away.",
        "Axle Clean and Press": "Keep the thick bar close, catch it clean, brace, press.",

        // Benches + stations
        "Decline Bench Press": "Shoulder blades set, bar to the lower chest, controlled path.",
        "Decline Sit-Up": "Hook your feet, roll up with control, no neck pulling.",
        "GHD Raise": "Stay straight from knees to head and pull up with the hamstrings.",
        "GHD Sit-Up": "Move smoothly and reach back only as far as you can control.",
        "Reverse Hyperextension": "Hips on the pad, sweep the legs up with the glutes, no jerking.",
        "Nordic Bench Curl": "Lower as slowly as possible, hips open, catch and press back.",
        "Weighted Sissy Squat": "Lock your feet, lean back in one line, bend only at the knees.",
        "Captain's Chair Leg Raise": "Back on the pad, no swing, lift with the abs.",

        // Plate-loaded machines
        "T-Bar Row": "Chest up, flat back, pull to your chest and squeeze.",
        "Belt Squat": "The load hangs from your hips, so sit deep, stay tall, drive.",
        "Pendulum Squat": "Back flat on the pad, sink deep with control, press through the whole foot.",
        "Machine Pullover": "Arms long, sweep down with the lats, resist the return.",

        // Selectorized machines
        "Hip Abduction": "Sit tall, press the knees apart with control, pause wide.",
        "Hip Adduction": "Ease into the starting width, squeeze together smoothly.",
        "Assisted Pull-Up": "Treat it like the real thing: dead hang to chin over.",
        "Assisted Dip": "Stay upright, lower to a controlled depth, press to lockout.",
        "Machine Crunch": "Crunch the ribs toward the hips, exhale hard, return slowly.",
        "Torso Rotation": "Rotate from the trunk with the hips still, smooth both directions.",
        "Machine Lateral Raise": "Let the elbows lead, lift to shoulder height, lower slowly.",
        "Machine Bicep Curl": "Elbows on the pad, full stretch to full squeeze.",
        "Machine Tricep Extension": "Elbows pinned, extend fully, control the way back.",
        "Machine Back Extension": "Move from the hips and low back together, smooth and controlled.",
        "Multi-Hip Kickback": "Stand tall, sweep the leg back, squeeze the glute.",
        "Machine Glute Kickback": "Hips square, press the pad back, squeeze at the top.",

        // Cardio machines
        "Ski Erg": "Reach tall, pull down with lats and core, hinge as you finish.",
        "Elliptical": "Stand tall, push and pull evenly, light grip.",
        "Stair Climber": "Stand tall, whole foot on the step, hands light on the rails.",
        "Vertical Climber": "Long reaches, drive with the legs, keep breathing.",
        "Upper Body Ergometer": "Sit tall, smooth circles, drive and pull evenly.",

        // Strongman
        "Yoke Carry": "Wedge under it, brace hard, take short fast steps, eyes forward.",
        "Farmers Handle Carry": "Deadlift them up with a flat back, then walk tall and quick.",
        "Log Clean and Press": "Roll the log in close, lap it, take a big brace, press.",
        "Atlas Stone Load": "Hug the stone deep, lap it first, drive the hips through.",
        "Circus Dumbbell Press": "Brace, use your legs to help, lock it out overhead.",
        "Husafell Carry": "Hug it high on your chest, stay as tall as you can, steady steps.",
        "Tire Flip": "Chest against the tire, drive with the legs, flip your grip fast.",
        "Sledgehammer Slam": "Slide your hand as you swing, hit with the whole body, stay loose.",

        // Gymnastics + calisthenics
        "Parallette L-Sit": "Press the shoulders down, keep the legs long, breathe through the shake.",
        "Parallette Push-Up": "Body rigid, lower deep between the bars with control.",
        "Rope Climb": "Let your legs do the work: lock your feet, reach, and stand.",
        "Peg Board Ascent": "Move one peg at a time, core tight, control the descent.",
        "Stall Bar Leg Raise": "Back flat on the bars, no swing, lift with the abs.",

        // Small equipment
        "Slam Ball Slam": "Reach tall, slam with the whole body, pick it up with a flat back.",
        "Stability Ball Leg Curl": "Bridge the hips high and keep them high while you curl.",
        "Stability Ball Rollout": "Hips tucked, roll out only as far as your core stays tight.",
        "Balance Trainer Squat": "Find your balance first, then squat slowly and controlled.",
        "Slider Lunge": "Slide back under control, keep the front heel heavy, stand up strong.",
        "Body Saw": "It's a moving plank: rock small, and never let the hips sag.",
        "Chain Bench Press": "Same groove as a bench press, accelerating as the chains load.",
        "Weighted Dip": "Let the belt settle first, then dip with the same control as bodyweight.",
        "Weighted Pull-Up": "Start from a dead hang, no swing, full chin over.",
        "Weighted Push-Up": "The vest changes nothing: same rigid plank, full range.",
        "Ruck": "Straps snug, stand tall under the load, brisk even pace.",
        "Mace 360": "Swing the mace close around your head and brace as it circles.",
        "Steel Club Mill": "Let the club swing on a smooth circle, brace, and stay tall.",
        "Bulgarian Bag Spin": "Sit into the swing, whip the bag around, brace against the pull.",
        "Wrist Roller Roll-Up": "Arms steady, roll from the wrists, control both directions.",
        "Neck Harness Extension": "Small slow nods, full control, no jerking.",
        "Gripper Close": "Set it deep in your palm, crush to a full close, ease it open.",
        "Heavy Bag Rounds": "Stay on the balls of your feet, exhale on every punch, hands back up.",
        "Agility Ladder Drills": "Light quick feet, eyes up, arms driving.",
        "Tibialis Raise": "Heels planted, lift the toes as high as they go, lower slowly.",
        "Slant Board Squat": "Heels elevated, torso tall, let the knees travel forward.",

        // Stretches — ease in, breathe, never bounce.
        "Standing Hamstring Stretch": "Soft knee, hinge until you feel a gentle pull, breathe into it.",
        "Standing Quad Stretch": "Pull the heel to your seat, knees together, tuck the hips.",
        "Kneeling Hip Flexor Stretch": "Tuck your hips under, shift forward gently, stay tall.",
        "Figure-Four Stretch": "Ankle over knee, sit back gently, keep the foot flexed.",
        "Pigeon Pose": "Square the hips, settle in slowly, breathe long.",
        "Butterfly Stretch": "Soles together, sit tall, let the knees fall with gravity.",
        "Standing Calf Stretch": "Back leg straight, heel pressed down, lean in gently.",
        "Downward Dog": "Press the floor away, long spine first, heels reaching second.",
        "Doorway Chest Stretch": "Forearm on the frame, step through gently, no forcing.",
        "Cross-Body Shoulder Stretch": "Pull the arm across gently, shoulders down, breathe.",
        "Neck Stretch": "Ear toward shoulder, gentle hand assist, never force it.",
        "Overhead Triceps Stretch": "Elbow high, hand down the spine, gentle assist.",
        "Standing Biceps Stretch": "Arm long behind you, palm forward, turn away gently.",
        "Child's Pose": "Hips to heels, arms long, let the back settle.",
        "Seated Spinal Twist": "Sit tall first, rotate from the ribs, breathe into it.",
        "Lat Stretch": "Hold on, sit your hips back, breathe into the side of your back.",
        "Cobra Stretch": "Hips stay down, chest lifts, elbows soft.",
        "Standing Side Bend Stretch": "Reach up and over, hips still, long exhale.",

        // Dynamic warmup drills
        "Arm Circles": "Start small, grow the circles, go both directions.",
        "Leg Swings": "Hold something steady, swing loose and controlled, build the range.",
        "Hip Circles": "Hands on hips, big smooth circles, both directions.",
        "Walking Knee Hug": "Pull each knee to your chest and stand tall on the other leg.",
        "Standing Torso Twist": "Relaxed arms, rotate easily from the trunk, feet planted.",
        "Cat-Cow": "Move with your breath: round up, then arch slowly.",
        "World's Greatest Stretch": "Long lunge, elbow toward the floor, then rotate open to the sky.",
        "Inchworm": "Walk the hands out to a plank, then the feet chase them back up.",
    ]
}
