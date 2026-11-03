import SwiftUI

/// Full-screen "set up my macro targets" wizard. Pure UI over `NutritionViewModel`; nothing is saved until the
/// last step (`completeSetup`).
struct NutritionSetupWizardView: View {
    @ObservedObject var viewModel: NutritionViewModel
    /// Called when the wizard goes away. `finished` is false when the user skipped.
    let onClose: (_ finished: Bool) -> Void

    private enum Step: Int {
        case goal, about, current, target, rate, activity, lifting, loading, result
    }

    @State private var settings: NutritionGoalSettings?
    @State private var step: Step = .goal
    @State private var goalChosen = false
    @State private var editing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            if let binding = Binding($settings) {
                content(binding)
            } else {
                ProgressView()
            }
        }
        .onAppear(perform: load)
        .sheet(isPresented: $editing) {
            if let settings {
                PlanEditorView(viewModel: viewModel, plan: nil, wizardCalculation: viewModel.calculate(settings)) { p, c, f, override in
                    finish(settings, edited: (p, c, f, override))
                }
            }
        }
    }

    private func load() {
        guard settings == nil else { return }
        let draft = viewModel.goalSettingsOrDraft()
        if draft?.isComplete == true { goalChosen = true }
        settings = draft
    }

    // MARK: - Flow

    /// Steps the user actually sees (maintain skips target weight and rate).
    private func visibleSteps(_ s: NutritionGoalSettings) -> [Step] {
        s.goal == .maintain ? [.goal, .about, .current, .activity, .lifting]
                            : [.goal, .about, .current, .target, .rate, .activity, .lifting]
    }

    private func next(_ s: NutritionGoalSettings) -> Step {
        let steps = visibleSteps(s)
        guard let i = steps.firstIndex(of: step), i + 1 < steps.count else { return .loading }
        return steps[i + 1]
    }

    private func previous(_ s: NutritionGoalSettings) -> Step? {
        let steps = visibleSteps(s)
        guard let i = steps.firstIndex(of: step), i > 0 else { return nil }
        return steps[i - 1]
    }

    private func go(_ target: Step, forward: Bool = true) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { step = target }
    }

    private func advance(_ binding: Binding<NutritionGoalSettings>) {
        let s = binding.wrappedValue
        let target = next(s)
        prepare(target, binding)
        go(target)
    }

    /// Sensible defaults when a step is entered.
    private func prepare(_ target: Step, _ binding: Binding<NutritionGoalSettings>) {
        var s = binding.wrappedValue
        switch target {
        case .target:
            let valid = s.goal == .lose ? s.targetWeightLbs < s.currentWeightLbs : s.targetWeightLbs > s.currentWeightLbs
            if !valid { s.targetWeightLbs = s.goal == .lose ? max(s.currentWeightLbs - 10, 50) : s.currentWeightLbs + 10 }
        case .rate:
            let range = NutritionCalculator.rateRange(goal: s.goal, weightLbs: s.currentWeightLbs)
            if s.weeklyRateLbs < range.min || s.weeklyRateLbs > range.max {
                s.weeklyRateLbs = NutritionCalculator.recommendedRate(goal: s.goal, weightLbs: s.currentWeightLbs)
            }
        case .loading, .result:
            if s.goal == .maintain { s.weeklyRateLbs = 0; s.targetWeightLbs = s.currentWeightLbs }
        default: break
        }
        binding.wrappedValue = s
    }

    private func canContinue(_ s: NutritionGoalSettings) -> Bool {
        switch step {
        case .goal: return goalChosen
        case .target:
            return s.goal == .lose ? s.targetWeightLbs < s.currentWeightLbs : s.targetWeightLbs > s.currentWeightLbs
        default: return true
        }
    }

    private func finish(_ s: NutritionGoalSettings, edited: (Double, Double, Double, Double?)?) {
        let plan = viewModel.completeSetup(s)
        if let edited, let plan {
            viewModel.savePlan(id: plan.id, name: plan.name, weekdayMask: plan.weekdayMask,
                               protein: edited.0, carbs: edited.1, fat: edited.2, kcalOverride: edited.3)
        }
        editing = false
        onClose(true)
    }

    // MARK: - Layout

    @ViewBuilder
    private func content(_ s: Binding<NutritionGoalSettings>) -> some View {
        VStack(spacing: 0) {
            if step != .loading { topBar(s.wrappedValue) }
            Group {
                switch step {
                case .goal: goalStep(s)
                case .about: aboutStep(s)
                case .current: weightStep(s, title: "What's your current weight?", subtitle: "We use this to work out how much you burn each day.",
                                          keyPath: \.currentWeightLbs, idPrefix: "setup.weight")
                case .target: weightStep(s, title: "What's your target weight?",
                                         subtitle: s.wrappedValue.goal == .lose ? "Pick a weight below where you are now." : "Pick a weight above where you are now.",
                                         keyPath: \.targetWeightLbs, idPrefix: "setup.target")
                case .rate: rateStep(s)
                case .activity: activityStep(s)
                case .lifting: liftingStep(s)
                case .loading: loadingStep(s)
                case .result: resultStep(s)
                }
            }
            .transition(.opacity)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if step != .loading && step != .result { continueBar(s) }
        }
    }

    private func topBar(_ s: NutritionGoalSettings) -> some View {
        let steps = visibleSteps(s)
        let index = steps.firstIndex(of: step) ?? steps.count
        let progress = step == .result ? 1.0 : Double(index + 1) / Double(steps.count + 1)
        return HStack(spacing: 8) {
            Button {
                if step == .result { go(visibleSteps(s).last ?? .lifting) }
                else if let p = previous(s) { go(p, forward: false) }
            } label: {
                Image(systemName: "chevron.left").font(.headline).frame(width: 44, height: 44)
            }
            .opacity(step == .goal ? 0 : 1)
            .disabled(step == .goal)
            .accessibilityLabel("Back")
            .accessibilityIdentifier("setup.back")
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(AppTheme.surfaceElevated)
                    Capsule().fill(AppTheme.accent).frame(width: proxy.size.width * progress)
                }
            }
            .frame(height: 8)
            .accessibilityElement()
            .accessibilityLabel("Progress")
            .accessibilityValue("\(Int(progress * 100)) percent")
            .accessibilityIdentifier("setup.progress")
            Button("Skip for now") { onClose(false) }
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
                .frame(minHeight: 44)
                .accessibilityIdentifier("setup.skip")
        }
        .foregroundStyle(AppTheme.textPrimary)
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }

    private func continueBar(_ s: Binding<NutritionGoalSettings>) -> some View {
        Button { advance(s) } label: { primaryLabel("Continue") }
            .buttonStyle(.plain)
            .disabled(!canContinue(s.wrappedValue))
            .opacity(canContinue(s.wrappedValue) ? 1 : 0.4)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(AppTheme.background)
            .accessibilityIdentifier("setup.continue")
    }

    private func primaryLabel(_ text: String) -> some View {
        Text(text).font(.headline).foregroundStyle(AppTheme.onAccent)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(AppTheme.accent, in: Capsule())
    }

    private func stepHeader(_ title: String, _ subtitle: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.title.weight(.bold)).foregroundStyle(AppTheme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle).font(.subheadline).foregroundStyle(AppTheme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func optionCard(title: String, detail: String?, icon: String, selected: Bool, id: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.title2).frame(width: 36)
                    .foregroundStyle(selected ? AppTheme.accent : AppTheme.textSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline).foregroundStyle(AppTheme.textPrimary)
                    if let detail {
                        Text(detail).font(.subheadline).foregroundStyle(AppTheme.textSecondary)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? AppTheme.accent : AppTheme.textSecondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                    .strokeBorder(selected ? AppTheme.accent : Color.clear, lineWidth: 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityIdentifier(id)
    }

    // MARK: - Steps

    private func goalStep(_ s: Binding<NutritionGoalSettings>) -> some View {
        ScrollView {
            VStack(spacing: 14) {
                stepHeader("What's your goal?", "We'll shape your calories and macros around it.")
                ForEach([(NutritionGoal.lose, "Lose weight", "Eat a bit less than you burn.", "arrow.down.right.circle"),
                         (.maintain, "Maintain weight", "Eat about what you burn.", "equal.circle"),
                         (.gain, "Gain weight", "Eat a bit more than you burn.", "arrow.up.right.circle")], id: \.0) { goal, title, detail, icon in
                    optionCard(title: title, detail: detail, icon: icon,
                               selected: goalChosen && s.wrappedValue.goal == goal, id: "setup.goal.\(goal.rawValue)") {
                        s.wrappedValue.goal = goal
                        goalChosen = true
                    }
                }
            }
            .padding(16)
        }
    }

    private func aboutStep(_ s: Binding<NutritionGoalSettings>) -> some View {
        let metric = s.wrappedValue.unit == .kg
        return ScrollView {
            VStack(spacing: 16) {
                stepHeader("About you", "Your sex, age and height set your base calorie burn.")
                Picker("Sex", selection: s.sex) {
                    Text("Male").tag(NutritionSex.male)
                    Text("Female").tag(NutritionSex.female)
                }
                .pickerStyle(.segmented)
                .frame(minHeight: 44)
                .accessibilityIdentifier("setup.sex")
                stepperRow("Age", "\(s.wrappedValue.age)", id: "setup.age",
                           minus: { s.wrappedValue.age = max(13, s.wrappedValue.age - 1) },
                           plus: { s.wrappedValue.age = min(100, s.wrappedValue.age + 1) })
                stepperRow("Height", heightText(s.wrappedValue), id: "setup.height",
                           minus: { s.wrappedValue.heightInches = max(48, adjustedHeight(s.wrappedValue, -1)) },
                           plus: { s.wrappedValue.heightInches = min(96, adjustedHeight(s.wrappedValue, 1)) })
                Text(metric ? "Showing centimetres." : "Showing feet and inches.")
                    .font(.footnote).foregroundStyle(AppTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
        }
    }

    private func heightText(_ s: NutritionGoalSettings) -> String {
        if s.unit == .kg { return "\(Int((s.heightInches * 2.54).rounded())) cm" }
        let total = Int(s.heightInches.rounded())
        return "\(total / 12)' \(total % 12)\""
    }

    private func adjustedHeight(_ s: NutritionGoalSettings, _ delta: Int) -> Double {
        if s.unit == .kg { return (((s.heightInches * 2.54).rounded() + Double(delta)) / 2.54) }
        return s.heightInches.rounded() + Double(delta)
    }

    private func stepperRow(_ title: String, _ value: String, id: String,
                            minus: @escaping () -> Void, plus: @escaping () -> Void) -> some View {
        HStack {
            Text(title).font(.headline).foregroundStyle(AppTheme.textPrimary)
            Spacer()
            roundButton("minus", label: "Decrease \(title)", id: "\(id).minus", action: minus)
            Text(value).font(.title3.weight(.semibold)).foregroundStyle(AppTheme.textPrimary)
                .frame(minWidth: 72)
                .accessibilityIdentifier("\(id).value")
            roundButton("plus", label: "Increase \(title)", id: "\(id).plus", action: plus)
        }
        .padding(16)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
    }

    private func roundButton(_ icon: String, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.headline).foregroundStyle(AppTheme.textPrimary)
                .frame(width: 44, height: 44)
                .background(AppTheme.surfaceElevated, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    private func weightStep(_ s: Binding<NutritionGoalSettings>, title: String, subtitle: String,
                            keyPath: WritableKeyPath<NutritionGoalSettings, Double>, idPrefix: String) -> some View {
        let unit = s.wrappedValue.unit
        let step = unit == .kg ? 0.5 : 1.0
        let range: ClosedRange<Double> = unit == .kg ? 30...250 : 70...550
        let display = Binding<Double>(
            get: { unit.fromLbs(s.wrappedValue[keyPath: keyPath]) },
            set: { s.wrappedValue[keyPath: keyPath] = unit.toLbs($0) }
        )
        let invalid = idPrefix == "setup.target" && !canContinue(s.wrappedValue)
        return VStack(spacing: 18) {
            stepHeader(title, subtitle).padding(.horizontal, 16).padding(.top, 8)
            Picker("Unit", selection: s.unit) {
                Text("lb").tag(BodyWeightUnit.lb)
                Text("kg").tag(BodyWeightUnit.kg)
            }
            .pickerStyle(.segmented)
            .frame(width: 160, height: 44)
            .accessibilityIdentifier("setup.unit")
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(NutritionFormat.amount(display.wrappedValue))
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(AppTheme.textPrimary)
                    .accessibilityIdentifier("\(idPrefix).value")
                Text(unit.rawValue).font(.title2.weight(.semibold)).foregroundStyle(AppTheme.textSecondary)
            }
            .accessibilityElement(children: .combine)
            HStack(spacing: 20) {
                roundButton("minus", label: "Decrease weight", id: "\(idPrefix).minus") {
                    display.wrappedValue = max(range.lowerBound, display.wrappedValue - step)
                }
                RulerPicker(value: display, range: range, step: step)
                    .id(unit)
                    .accessibilityIdentifier("\(idPrefix).ruler")
                roundButton("plus", label: "Increase weight", id: "\(idPrefix).plus") {
                    display.wrappedValue = min(range.upperBound, display.wrappedValue + step)
                }
            }
            .padding(.horizontal, 8)
            if invalid {
                Text(s.wrappedValue.goal == .lose ? "Your target must be below your current weight."
                                                  : "Your target must be above your current weight.")
                    .font(.footnote).foregroundStyle(AppTheme.warning)
                    .accessibilityIdentifier("setup.target.invalid")
            }
            Spacer(minLength: 0)
        }
    }

    private func rateStep(_ s: Binding<NutritionGoalSettings>) -> some View {
        let calc = viewModel.calculate(s.wrappedValue)
        let unit = s.wrappedValue.unit
        let verb = s.wrappedValue.goal == .lose ? "lose" : "gain"
        let rate = calc.weeklyRateLbs
        return ScrollView {
            VStack(spacing: 18) {
                stepHeader("How fast?", "Slower is easier to stick to. Faster needs more discipline.")
                VStack(spacing: 6) {
                    Text("\(NutritionFormat.amount(unit.fromLbs(rate).rounded(toPlaces: 2))) \(unit.rawValue) / week")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.textPrimary)
                        .accessibilityIdentifier("setup.rate.value")
                    Text("to \(verb) \(NutritionFormat.amount(abs(unit.fromLbs(s.wrappedValue.targetWeightLbs - s.wrappedValue.currentWeightLbs)))) \(unit.rawValue)")
                        .font(.subheadline).foregroundStyle(AppTheme.textSecondary)
                }
                .padding(.top, 8)
                if calc.maxRateLbs > calc.minRateLbs {
                    Slider(value: s.weeklyRateLbs, in: calc.minRateLbs...calc.maxRateLbs, step: 0.05)
                        .tint(AppTheme.accent)
                        .frame(minHeight: 44)
                        .accessibilityLabel("Weekly rate")
                        .accessibilityValue("\(NutritionFormat.amount(unit.fromLbs(rate).rounded(toPlaces: 2))) \(unit.rawValue) per week")
                        .accessibilityIdentifier("setup.rate.slider")
                    HStack {
                        Text("Slower").font(.caption).foregroundStyle(AppTheme.textSecondary)
                        Spacer()
                        Button {
                            s.wrappedValue.weeklyRateLbs = calc.recommendedRateLbs
                        } label: {
                            Label("Recommended: \(NutritionFormat.amount(unit.fromLbs(calc.recommendedRateLbs).rounded(toPlaces: 2)))",
                                  systemImage: "star.fill")
                                .font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.accent)
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("setup.rate.recommended")
                        Spacer()
                        Text("Faster").font(.caption).foregroundStyle(AppTheme.textSecondary)
                    }
                }
                VStack(spacing: 4) {
                    Text("Projected goal date").font(.footnote).foregroundStyle(AppTheme.textSecondary)
                    Text(calc.projectedGoalDate.map { $0.formatted(.dateTime.month(.wide).day().year()) } ?? "–")
                        .font(.title3.weight(.semibold)).foregroundStyle(AppTheme.textPrimary)
                        .accessibilityIdentifier("setup.rate.date")
                }
                .frame(maxWidth: .infinity)
                .padding(16)
                .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
                if calc.flooredByMinimum {
                    Label("This is faster than your calorie minimum allows, so we'll slow it down.", systemImage: "info.circle")
                        .font(.footnote).foregroundStyle(AppTheme.textSecondary)
                }
            }
            .padding(16)
        }
    }

    private func activityStep(_ s: Binding<NutritionGoalSettings>) -> some View {
        let options: [(NutritionActivityLevel, String, String, String)] = [
            (.sedentary, "Sedentary", "Desk job, little exercise.", "figure.seated.side"),
            (.lightlyActive, "Lightly active", "Light exercise 1 to 3 days a week.", "figure.walk"),
            (.active, "Active", "Moderate exercise 3 to 5 days a week.", "figure.run"),
            (.veryActive, "Very active", "Hard exercise most days, or a physical job.", "figure.strengthtraining.traditional")
        ]
        return ScrollView {
            VStack(spacing: 14) {
                stepHeader("How active are you?", "Outside of planned workouts, think about a typical week.")
                ForEach(options, id: \.0) { level, title, detail, icon in
                    optionCard(title: title, detail: detail, icon: icon, selected: s.wrappedValue.activityLevel == level,
                               id: "setup.activity.\(level.rawValue)") { s.wrappedValue.activityLevel = level }
                }
            }
            .padding(16)
        }
    }

    private func liftingStep(_ s: Binding<NutritionGoalSettings>) -> some View {
        ScrollView {
            VStack(spacing: 14) {
                stepHeader("Do you lift weights?", "Lifters need more protein to build and keep muscle, so we raise your protein target.")
                optionCard(title: "Yes", detail: "About 1 g of protein per lb.", icon: "dumbbell.fill",
                           selected: s.wrappedValue.liftsWeights, id: "setup.lift.yes") { s.wrappedValue.liftsWeights = true }
                optionCard(title: "No", detail: "About 0.8 g of protein per lb.", icon: "figure.walk",
                           selected: !s.wrappedValue.liftsWeights, id: "setup.lift.no") { s.wrappedValue.liftsWeights = false }
            }
            .padding(16)
        }
    }

    private func loadingStep(_ s: Binding<NutritionGoalSettings>) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "flame.fill").font(.system(size: 56)).foregroundStyle(AppTheme.accent)
                .symbolEffect(.pulse, isActive: !reduceMotion)
                .accessibilityHidden(true)
            Text("Cooking up your plan…").font(.title2.weight(.semibold)).foregroundStyle(AppTheme.textPrimary)
            if !reduceMotion { ProgressView().tint(AppTheme.accent) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("setup.loading")
        .task {
            try? await Task.sleep(nanoseconds: reduceMotion ? 400_000_000 : 1_600_000_000)
            guard !Task.isCancelled else { return }
            go(.result)
        }
    }

    private func resultStep(_ s: Binding<NutritionGoalSettings>) -> some View {
        let calc = viewModel.calculate(s.wrappedValue)
        return VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 18) {
                    stepHeader("Your macro targets are ready")
                    VStack(spacing: 4) {
                        Text(NutritionFormat.whole(calc.kcal))
                            .font(.system(size: 56, weight: .bold, design: .rounded)).foregroundStyle(AppTheme.textPrimary)
                        Text("calories per day").font(.subheadline).foregroundStyle(AppTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(NutritionFormat.whole(calc.kcal)) calories")
                    .accessibilityIdentifier("setup.result.kcal")
                    HStack(spacing: 10) {
                        resultTile("Protein", calc.proteinGrams, calc.proteinPercent, AppTheme.macroProtein, "setup.result.protein")
                        resultTile("Carbs", calc.carbsGrams, calc.carbsPercent, AppTheme.macroCarbs, "setup.result.carbs")
                        resultTile("Fat", calc.fatGrams, calc.fatPercent, AppTheme.macroFat, "setup.result.fat")
                    }
                    if calc.flooredByMinimum {
                        Label("We raised your calories to the safe minimum of \(NutritionFormat.whole(NutritionCalculator.calorieFloor(for: s.wrappedValue.sex))), so your weekly rate is gentler than you picked.",
                              systemImage: "info.circle")
                            .font(.footnote).foregroundStyle(AppTheme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("setup.result.floor")
                    }
                    if !viewModel.plans.isEmpty {
                        Label("This replaces your current plans with one plan for every day.", systemImage: "exclamationmark.triangle")
                            .font(.footnote).foregroundStyle(AppTheme.warning)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("setup.result.replaces")
                    }
                }
                .padding(16)
            }
            VStack(spacing: 8) {
                Button { finish(s.wrappedValue, edited: nil) } label: { primaryLabel("Looks good!") }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("setup.finish")
                Button { editing = true } label: {
                    Text("Edit Target").font(.headline).foregroundStyle(AppTheme.accent)
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("setup.editTarget")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private func resultTile(_ title: String, _ grams: Double, _ percent: Int, _ color: Color, _ id: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(title).font(.caption).foregroundStyle(AppTheme.textSecondary)
            }
            Text("\(NutritionFormat.whole(grams)) g").font(.title3.weight(.semibold)).foregroundStyle(AppTheme.textPrimary)
            Text("\(percent)%").font(.caption).foregroundStyle(AppTheme.textSecondary)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(NutritionFormat.whole(grams)) grams, \(percent) percent")
        .accessibilityIdentifier(id)
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let m = pow(10, Double(places))
        return (self * m).rounded() / m
    }
}

// MARK: - Ruler

/// A horizontal scrolling ruler. Scroll to pick; the centre line is the value. Also adjustable by VoiceOver.
struct RulerPicker: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    @State private var position: Int?
    private let tickWidth: CGFloat = 12

    private var count: Int { Int(((range.upperBound - range.lowerBound) / step).rounded()) + 1 }
    private func index(_ v: Double) -> Int { min(max(Int(((v - range.lowerBound) / step).rounded()), 0), count - 1) }

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(0..<count, id: \.self) { i in tick(i) }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, max(0, proxy.size.width / 2 - tickWidth / 2), for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $position, anchor: .center)
            .overlay {
                Rectangle().fill(AppTheme.accent).frame(width: 3, height: 56).allowsHitTesting(false)
            }
        }
        .frame(height: 84)
        .onAppear { position = index(value) }
        .onChange(of: position) { _, new in
            guard let new else { return }
            let v = range.lowerBound + Double(new) * step
            if abs(v - value) > step / 2 { value = v }
        }
        .onChange(of: value) { _, new in
            let i = index(new)
            if position != i { position = i }
        }
        .accessibilityElement()
        .accessibilityLabel("Weight ruler")
        .accessibilityValue(NutritionFormat.amount(value))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(range.upperBound, value + step)
            case .decrement: value = max(range.lowerBound, value - step)
            @unknown default: break
            }
        }
    }

    private func tick(_ i: Int) -> some View {
        let v = range.lowerBound + Double(i) * step
        let major = i % 10 == 0
        let mid = i % 5 == 0
        return VStack(spacing: 4) {
            Rectangle().fill(major ? AppTheme.textPrimary : AppTheme.textSecondary.opacity(0.6))
                .frame(width: 1.5, height: major ? 34 : (mid ? 24 : 14))
            Text(major ? NutritionFormat.amount(v) : " ")
                .font(.caption2).foregroundStyle(AppTheme.textSecondary)
                .fixedSize()
        }
        .frame(width: tickWidth, height: 70, alignment: .top)
        .id(i)
    }
}
