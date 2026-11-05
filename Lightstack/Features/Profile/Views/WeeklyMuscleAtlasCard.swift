import SwiftUI

/// Native, offline-capable overlay on the approved detailed armor illustration.
/// The art is a static bundled asset; regions are independent vector paths.
struct WeeklyMuscleAtlasCard: View {
    let activity: WeeklyMuscleActivity

    @State private var inspectedMuscle: InspectedMuscle?

    private static let artSize = CGSize(width: 1122, height: 1402)
    private static let groupNames: [String: String] = [
        "traps": "Trapezius",
        "frontDelts": "Front deltoids",
        "sideDelts": "Side deltoids",
        "rearDelts": "Rear deltoids",
        "upperChest": "Upper chest",
        "chest": "Chest",
        "serratus": "Serratus anterior",
        "obliques": "Obliques",
        "abs": "Abdominals",
        "biceps": "Biceps",
        "brachialis": "Brachialis",
        "triceps": "Triceps",
        "forearms": "Forearms",
        "hipFlexors": "Hip flexors",
        "adductors": "Adductors",
        "quads": "Quadriceps",
        "tibialis": "Tibialis anterior",
        "calves": "Calves",
        "rhomboids": "Rhomboids",
        "lats": "Latissimus dorsi",
        "lowerBack": "Lower back",
        "glutes": "Glutes",
        "hamstrings": "Hamstrings"
    ]

    private static let regions: [AtlasRegion] = {
        guard let url = Bundle.main.url(forResource: "MuscleAtlasRegions", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let atlas = try? JSONDecoder().decode(AtlasRegionFile.self, from: data) else {
            assertionFailure("Bundled MuscleAtlasRegions.json is missing or invalid")
            return []
        }
        return atlas.regions.enumerated().flatMap { index, definition -> [AtlasRegion] in
            let axis = definition.view == "front" ? atlas.frontAxis : atlas.backAxis
            let original = AtlasRegion(
                id: "\(definition.view)-left-\(index)", muscle: definition.muscle,
                name: definition.name, points: definition.points.map { CGPoint(x: $0[0], y: $0[1]) }
            )
            let mirrored = AtlasRegion(
                id: "\(definition.view)-right-\(index)", muscle: definition.muscle,
                name: definition.name,
                points: definition.points.map { CGPoint(x: 2 * axis - $0[0], y: $0[1]) }
            )
            return [original, mirrored]
        }
    }()

    private var weekLabel: String {
        let end = Calendar.current.date(byAdding: .day, value: 6, to: activity.weekStart) ?? activity.weekStart
        return "\(activity.weekStart.formatted(.dateTime.month(.abbreviated).day()))–\(end.formatted(.dateTime.day()))"
    }

    private var activeMuscles: [(name: String, sets: Double)] {
        activity.setsByMuscle.compactMap { key, sets in
            guard sets > 0 else { return nil }
            return (name: Self.groupNames[key] ?? key, sets: sets)
        }
        .sorted { $0.sets == $1.sets ? $0.name < $1.name : $0.sets > $1.sets }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Muscles this week")
                        .font(.headline)
                        .foregroundStyle(AppTheme.textPrimary)
                    Text("Based on logged sets • \(weekLabel)")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(activeMuscles.count)")
                        .font(.title2.bold())
                        .foregroundStyle(Color(red: 0.28, green: 0.79, blue: 1))
                    Text("targeted")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }

            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    Image("MjolnirAnatomy")
                        .resizable()
                        .interpolation(.high)
                        .frame(width: geometry.size.width, height: geometry.size.height)

                    Canvas(opaque: false, rendersAsynchronously: true) { context, size in
                        for region in Self.regions {
                            let intensity = activity.intensity(for: region.muscle)
                            guard intensity > 0 else { continue }
                            let path = region.path(in: size, originalSize: Self.artSize)
                            let cyan = Color(red: 0.25, green: 0.77, blue: 1)
                            context.fill(path, with: .color(cyan.opacity(0.15 + intensity * 0.43)))
                            context.stroke(
                                path, with: .color(cyan.opacity(0.35 + intensity * 0.55)),
                                lineWidth: max(0.7, size.width / Self.artSize.width * 2)
                            )
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        SpatialTapGesture().onEnded { value in
                            guard geometry.size.width > 0, geometry.size.height > 0 else { return }
                            let location = CGPoint(
                                x: value.location.x * Self.artSize.width / geometry.size.width,
                                y: value.location.y * Self.artSize.height / geometry.size.height
                            )
                            if let hit = Self.regions.reversed().first(where: { $0.contains(location) }) {
                                inspectedMuscle = InspectedMuscle(id: hit.muscle)
                            }
                        }
                    )
                    .accessibilityLabel("Master Chief muscle diagram: front left, back right. Tap a region for details.")
                    .accessibilityIdentifier("profile.weeklyMuscleAtlas")
                }
                .clipped()
            }
            .aspectRatio(Self.artSize.width / Self.artSize.height, contentMode: .fit)
            .background(Color(red: 0.02, green: 0.05, blue: 0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            if activeMuscles.isEmpty {
                Text("Complete a strength workout to illuminate the muscles you trained.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            } else {
                FlowGroupSummary(groups: Array(activeMuscles.prefix(5)))
            }

            Text("Blue intensity reflects effective sets this week. Tap a muscle to inspect it.")
                .font(.caption2)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .sheet(item: $inspectedMuscle) { selected in
            NavigationStack {
                VStack(spacing: 16) {
                    Text(Self.groupNames[selected.id] ?? selected.id)
                        .font(.title2.bold())
                    Text(String(format: "%.1f effective sets this week", activity.setsByMuscle[selected.id] ?? 0))
                        .foregroundStyle(AppTheme.textSecondary)
                    Text("Primary sets count fully; secondary muscle involvement is estimated. This is a training visualization, not a medical recovery measurement.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(AppTheme.textSecondary)
                    Spacer()
                }
                .padding(24)
                .navigationTitle("Muscle activity")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { inspectedMuscle = nil }
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }
}

private struct FlowGroupSummary: View {
    let groups: [(name: String, sets: Double)]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(groups.indices, id: \.self) { index in
                let group = groups[index]
                HStack {
                    Text(group.name)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                    Spacer()
                    Text(String(format: "%.1f sets", group.sets))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Color(red: 0.34, green: 0.83, blue: 1))
                }
            }
        }
    }
}

private struct InspectedMuscle: Identifiable {
    let id: String
}

private struct AtlasRegionFile: Decodable {
    let width: CGFloat
    let height: CGFloat
    let frontAxis: CGFloat
    let backAxis: CGFloat
    let regions: [AtlasRegionDefinition]
}

private struct AtlasRegionDefinition: Decodable {
    let view: String
    let muscle: String
    let name: String
    let points: [[CGFloat]]
}

private struct AtlasRegion: Identifiable {
    let id: String
    let muscle: String
    let name: String
    let points: [CGPoint]

    func path(in size: CGSize, originalSize: CGSize) -> Path {
        var result = Path()
        guard let first = points.first else { return result }
        let xScale = size.width / originalSize.width
        let yScale = size.height / originalSize.height
        result.move(to: CGPoint(x: first.x * xScale, y: first.y * yScale))
        for point in points.dropFirst() {
            result.addLine(to: CGPoint(x: point.x * xScale, y: point.y * yScale))
        }
        result.closeSubpath()
        return result
    }

    /// Ray casting permits hit-testing without an HTML/SVG web view.
    func contains(_ location: CGPoint) -> Bool {
        guard points.count >= 3 else { return false }
        var inside = false
        var j = points.count - 1
        for i in points.indices {
            let a = points[i]
            let b = points[j]
            if (a.y > location.y) != (b.y > location.y) {
                let x = (b.x - a.x) * (location.y - a.y) / (b.y - a.y) + a.x
                if location.x < x { inside.toggle() }
            }
            j = i
        }
        return inside
    }
}

#Preview {
    ScrollView {
        WeeklyMuscleAtlasCard(
            activity: WeeklyMuscleActivity(
                weekStart: Date(),
                setsByMuscle: ["upperChest": 6, "triceps": 4, "frontDelts": 3, "lats": 7, "biceps": 4],
                completedSets: 12
            )
        )
        .padding()
    }
}
