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
                    .font(AppTheme.playfair(20, weight: .bold))
                    .foregroundStyle(AppTheme.textPrimary)

                Spacer()

                statusBadge
            }

            if let note = session.focusNote, !note.isEmpty {
                Text(note)
                    .font(AppTheme.caveat(14))
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
                .font(AppTheme.playfairItalic(16, weight: .bold))
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
                        .font(AppTheme.caveat(15))
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
                    .font(AppTheme.playfairItalic(16, weight: .bold))
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
                .font(AppTheme.playfairItalic(16, weight: .bold))
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
                    .font(AppTheme.caveat(11, weight: .bold))
                    .foregroundStyle(AppTheme.success)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppTheme.success.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            } else if isToday {
                Text("Today")
                    .font(AppTheme.caveat(11, weight: .bold))
                    .foregroundStyle(AppTheme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppTheme.accent.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            } else if isPast {
                Text("Missed")
                    .font(AppTheme.caveat(11, weight: .bold))
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
                .font(AppTheme.caveat(11))
                .foregroundStyle(AppTheme.accent)
            Text(label)
                .font(AppTheme.caveat(11))
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(AppTheme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
    }
}
