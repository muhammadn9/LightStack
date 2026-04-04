import SwiftUI

/// Detail view for a single planned session day.
/// Shows workout type, focus note, and progressive overload target.
struct PlannedSessionView: View {
    let session: PlannedSession
    let onStartWorkout: (() -> Void)?
    let onConfigureWithAI: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerCard
                detailsCard
                if !session.isRestDay {
                    actionButtons
                }
            }
            .padding(16)
        }
        .themedBackground()
        .navigationTitle(DateFormatter.shortDate.string(from: session.plannedDate))
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    private var headerCard: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: session.isRestDay ? "moon.zzz.fill" : "figure.strengthtraining.traditional")
                    .font(.title2)
                    .foregroundStyle(session.isRestDay ? AppTheme.textSecondary : AppTheme.accent)

                Text(session.workoutType)
                    .font(.title2.bold())
                    .foregroundStyle(AppTheme.textPrimary)

                Spacer()

                statusBadge
            }

            if let note = session.focusNote, !note.isEmpty {
                Text(note)
                    .font(.body)
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .cardStyle()
    }

    // MARK: - Details

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Session Details")
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)

            HStack {
                DetailPill(icon: "calendar", label: formattedDate)
                DetailPill(icon: session.isRestDay ? "bed.double.fill" : "dumbbell.fill",
                          label: session.isRestDay ? "Rest Day" : "Training Day")
            }

            if session.completed {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppTheme.success)
                    Text("Completed")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.success)
                }
                .padding(.top, 4)
            }
        }
        .cardStyle()
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 12) {
            if isToday && !session.completed {
                Button(action: { onStartWorkout?() }) {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Start This Workout")
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppTheme.accentGradient)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                }
            }

            Button(action: { onConfigureWithAI?() }) {
                HStack {
                    Image(systemName: "sparkles")
                    Text("Configure with AI")
                }
                .font(.headline)
                .foregroundStyle(AppTheme.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(AppTheme.accent.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            }
        }
    }

    // MARK: - Helpers

    private var statusBadge: some View {
        Group {
            if session.completed {
                Text("Done")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.success)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppTheme.success.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            } else if isToday {
                Text("Today")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppTheme.accent.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            } else if isPast {
                Text("Missed")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.warning)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppTheme.warning.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            }
        }
    }

    private var isToday: Bool {
        Calendar.current.isDateInToday(session.plannedDate)
    }

    private var isPast: Bool {
        session.plannedDate < Calendar.current.startOfDay(for: Date()) && !session.completed
    }

    private var formattedDate: String {
        DateFormatter.shortDate.string(from: session.plannedDate)
    }
}

// MARK: - Detail Pill

private struct DetailPill: View {
    let icon: String
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(AppTheme.accent)
            Text(label)
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(AppTheme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
    }
}
