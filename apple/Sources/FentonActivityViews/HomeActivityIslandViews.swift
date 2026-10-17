import FentonActivityModel
import SwiftUI

/// The Dynamic Island's regions for the Home activity (`live-activities.md` §4). The widget extension places each in
/// `DynamicIsland { ... }`; the gallery and the tests draw them in a black capsule.
///
/// The island always shows the focused job (``HomeActivityState/focusedJob``); the ‹ › pager changes which.
public enum HomeActivityIsland {
    /// Compact, leading: the focused job's glyph, with a count when other jobs run too.
    public struct CompactLeading: View {
        let state: HomeActivityState

        public init(state: HomeActivityState) { self.state = state }

        public var body: some View {
            if let job = state.focusedJob {
                HStack(spacing: 2) {
                    ActivityGlyph(job: job, size: 22)
                    if state.jobs.count > 1 {
                        Text("\(state.jobs.count)")
                            .font(.caption2.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(ActivityStyle.primaryText)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(state.jobs.count > 1 ? "\(job.title), \(state.jobs.count) jobs running" : job.title)
            }
        }
    }

    /// Compact, trailing: the focused job's countdown, or its percentage. It has a fixed width so the island does not
    /// resize each second; "Done" with a checkmark during the linger.
    public struct CompactTrailing: View {
        let state: HomeActivityState

        public init(state: HomeActivityState) { self.state = state }

        public var body: some View {
            if let job = state.focusedJob {
                ActivityTrailing(job: job, width: 48)
                    .frame(maxWidth: 56, alignment: .trailing)
            }
        }
    }

    /// Minimal: the focused glyph inside a ring that fills itself as the job runs. It must fit a 28 pt circle.
    public struct Minimal: View {
        let state: HomeActivityState

        public init(state: HomeActivityState) { self.state = state }

        public var body: some View {
            if let job = state.focusedJob {
                let style = ActivityStyle(tint: job.tint)
                ZStack {
                    ring(job: job).tint(style.accent)
                    Image(systemName: job.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(style.accent)
                }
                .frame(width: 24, height: 24)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(job.title)
            }
        }

        @ViewBuilder
        private func ring(job: ActivityJob) -> some View {
            switch job.bar {
            case let .timer(range):
                ProgressView(timerInterval: range, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                    .progressViewStyle(.circular)
            case let .fraction(value):
                ProgressView(value: value).progressViewStyle(.circular)
            case .full:
                ProgressView(value: 1).progressViewStyle(.circular)
            case .hidden:
                Circle().stroke(ActivityStyle(tint: job.tint).accent.opacity(0.35), lineWidth: 2)
            }
        }
    }

    /// Expanded, leading: glyph and title.
    public struct ExpandedLeading: View {
        let state: HomeActivityState

        public init(state: HomeActivityState) { self.state = state }

        public var body: some View {
            if let job = state.focusedJob {
                HStack(spacing: 6) {
                    ActivityGlyph(job: job, size: 30)
                    Text(job.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ActivityStyle.primaryText)
                        .lineLimit(2)
                }
            }
        }
    }

    /// Expanded, trailing: the large countdown.
    public struct ExpandedTrailing: View {
        let state: HomeActivityState

        public init(state: HomeActivityState) { self.state = state }

        public var body: some View {
            if let job = state.focusedJob {
                ActivityTrailing(job: job, emphasized: true, width: 96)
            }
        }
    }

    /// Expanded, center: the status line.
    public struct ExpandedCenter: View {
        let state: HomeActivityState

        public init(state: HomeActivityState) { self.state = state }

        public var body: some View {
            if let job = state.focusedJob, !job.status.isEmpty {
                Text(job.status)
                    .font(.caption)
                    .foregroundStyle(ActivityStyle.secondaryText)
                    .lineLimit(1)
            }
        }
    }

    /// Expanded, bottom: the bar, then the controls and the pager.
    public struct ExpandedBottom: View {
        let state: HomeActivityState
        let tag: String

        public init(state: HomeActivityState, tag: String = HomeActivityAttributes.homeTag) {
            self.state = state
            self.tag = tag
        }

        public var body: some View {
            if let job = state.focusedJob {
                VStack(spacing: 4) {
                    ActivityBar(job: job)
                    ActivityFocusLine(state: state, tag: tag)
                }
            }
        }
    }
}

/// The apple-watch Smart Stack and CarPlay presentation (`.small` supplemental family, iOS 18): the focused job's
/// glyph, its countdown and "+N". No controls: buttons do nothing there until a device check says otherwise.
public struct HomeActivitySmallView: View {
    private let state: HomeActivityState

    /// Creates the view.
    public init(state: HomeActivityState) { self.state = state }

    public var body: some View {
        if let job = state.focusedJob {
            HStack(spacing: 6) {
                ActivityGlyph(job: job, size: 26)
                VStack(alignment: .leading, spacing: 0) {
                    Text(job.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ActivityStyle.primaryText)
                        .lineLimit(1)
                    ActivityTrailing(job: job, width: 56)
                }
                if state.jobs.count > 1 {
                    Text("+\(state.jobs.count - 1)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(ActivityStyle.secondaryText)
                        .accessibilityLabel("\(state.jobs.count - 1) more")
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// The three island presentations in a black capsule, for the gallery, the hosted tests and screenshots: the system
/// draws the real island, so this is a stand-in with the real regions inside it.
public struct HomeActivityIslandPreview: View {
    /// Which presentation.
    public enum Kind: String, CaseIterable, Sendable {
        case compact, minimal, expanded
    }

    private let state: HomeActivityState
    private let kind: Kind

    /// Creates the preview.
    public init(state: HomeActivityState, kind: Kind) {
        self.state = state
        self.kind = kind
    }

    public var body: some View {
        Group {
            switch kind {
            case .compact:
                HStack {
                    HomeActivityIsland.CompactLeading(state: state)
                    Spacer(minLength: 90)
                    HomeActivityIsland.CompactTrailing(state: state)
                }
                .padding(.horizontal, 12)
                .frame(width: 250, height: 36)
                .background(Capsule().fill(Color.black))
            case .minimal:
                HomeActivityIsland.Minimal(state: state)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.black))
            case .expanded:
                VStack(spacing: 6) {
                    HStack(alignment: .top) {
                        HomeActivityIsland.ExpandedLeading(state: state)
                        Spacer()
                        HomeActivityIsland.ExpandedTrailing(state: state)
                    }
                    HomeActivityIsland.ExpandedCenter(state: state)
                    HomeActivityIsland.ExpandedBottom(state: state)
                }
                .padding(16)
                .frame(width: 370)
                .background(RoundedRectangle(cornerRadius: 44, style: .continuous).fill(Color.black))
            }
        }
        .accessibilityIdentifier("liveactivity.island.\(kind.rawValue)")
    }
}
