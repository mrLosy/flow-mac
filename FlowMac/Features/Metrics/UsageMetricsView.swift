import SwiftUI

struct UsageMetricsView: View {
    @ObservedObject var metricsService = UsageMetricsService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Top stats grid
            HStack(spacing: 20) {
                statCard(title: "Sessions", value: "\(metricsService.metrics.totalSessions)", icon: "mic.fill")
                statCard(title: "Words", value: formatNumber(metricsService.metrics.totalWords), icon: "text.word.spacing")
                statCard(title: "Streak", value: "\(metricsService.currentStreak) days", icon: "flame.fill")
            }

            HStack(spacing: 20) {
                statCard(title: "Time Saved", value: formatDuration(metricsService.estimatedTimeSaved), icon: "clock.arrow.circlepath")
                statCard(title: "Keystrokes Saved", value: formatNumber(metricsService.keystrokesSaved), icon: "keyboard")
                statCard(title: "WPM", value: String(format: "%.0f", metricsService.wordsPerMinute), icon: "speedometer")
            }

            // Activity chart
            VStack(alignment: .leading, spacing: 8) {
                Text("DAILY ACTIVITY")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                    .tracking(0.5)

                let activity = metricsService.dailyActivity(days: 30)
                let maxCount = max(activity.map(\.count).max() ?? 1, 1)

                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(Array(activity.enumerated()), id: \.offset) { _, day in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(day.count > 0 ? Color.accentColor : Color.primary.opacity(0.08))
                            .frame(height: max(4, CGFloat(day.count) / CGFloat(maxCount) * 40))
                    }
                }
                .frame(height: 44)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                )
            }

            // Total recording time
            HStack {
                Text("Total recording time:")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                Spacer()
                Text(formatDuration(metricsService.metrics.totalDuration))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
            }
        }
    }

    private func statCard(title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(.accentColor)
                Text(title)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return "\(Int(seconds))s" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        let hours = Int(seconds / 3600)
        let mins = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
        return "\(hours)h \(mins)m"
    }

    private func formatNumber(_ n: Int) -> String {
        if n < 1000 { return "\(n)" }
        if n < 1_000_000 { return String(format: "%.1fK", Double(n) / 1000) }
        return String(format: "%.1fM", Double(n) / 1_000_000)
    }
}
