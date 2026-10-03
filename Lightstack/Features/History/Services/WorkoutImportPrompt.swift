import Foundation

enum WorkoutImportPrompt {
    static let text = """
    You are helping me move my past workout history into a fitness app. I will paste my workout records at the end of this message (notes, spreadsheet rows, screenshots transcribed to text, or another app's export). Read them and convert them into the exact JSON format below.

    OUTPUT RULES (strict):
    - Output ONLY the JSON. No explanations, no greetings, no markdown commentary. A single ```json code block is fine.
    - Write one entry in "workouts" per workout day.
    - "date" must be YYYY-MM-DD. If a workout has no date you can determine, use "N/A".
    - "name" is a short name based on the exercises performed, e.g. "Push", "Pull", "Legs", "Upper Body", "Full Body".
    - Every exercise needs a "muscle_group", one of: Chest, Back, Shoulders, Arms, Legs, Core.
    - "weight_lbs" is in pounds. Convert kilograms to pounds (1 kg = 2.2046 lbs) and round to the nearest 0.5. Use 0 for bodyweight exercises.
    - Write one entry in "sets" for every set performed. "reps" is a whole number.
    - "rir" is reps in reserve. Keep ranges exactly as written, e.g. "1-2". If it is not recorded, write "N/A".
    - Put any notes I wrote into "notes", per exercise or per workout. If there are none, write "N/A".
    - Use "N/A" for ANY value that is not recorded in my records.
    - Do NOT invent, guess or fill in data that is not in my records. Do not add workouts, exercises or sets that I did not record.

    FORMAT (follow exactly, with these key names):

    {"workouts": [
      {"date": "2026-09-14", "name": "Pull", "notes": "N/A",
       "exercises": [
         {"name": "Barbell Row", "muscle_group": "Back", "notes": "N/A",
          "sets": [{"weight_lbs": 135, "reps": 8, "rir": "1-2"}]}
       ]}
    ]}

    My workout records:


    """
}
