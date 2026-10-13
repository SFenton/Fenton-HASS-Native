import HassCore
import HassDesign
import SwiftUI

/// The Vacuums page on the app's connection (spec: `.agents/pages/vacuums/spec.md`; web `VacuumPage`).
struct VacuumsScreen: View {
    @Environment(HassConnection.self) private var connection

    var body: some View {
        VacuumsPage(store: connection.store, caller: connection) { vacuum in
            VacuumSheet(vacuum: vacuum, connection: connection)
        }
    }
}

/// Robot Vacuums and Auto-Clean. One column on phones, folded or portrait; where a split is allowed (unfolded
/// Duo and iPad in landscape) Robot Vacuums leads and Auto-Clean sits beside it.
struct VacuumsPage<Sheet: View>: View {
    @State private var autoClean: VacuumAutoCleanController
    @State private var open: VacuumConfig?
    private let store: EntityStore
    private let sheet: (VacuumConfig) -> Sheet
    @Environment(\.horizontalSizeClass) private var sizeClass
    @ScaledMetric(relativeTo: .subheadline) private var minTileWidth: CGFloat = 150

    /// Creates the page.
    /// - Parameters:
    ///   - initialVacuum: A vacuum whose sheet opens at once (gallery).
    ///   - sheet: Builds a vacuum's sheet.
    init(store: EntityStore, caller: any HassServiceCalling, scheduler: any RevertScheduler = TaskRevertScheduler(),
         initialVacuum: VacuumConfig? = nil, @ViewBuilder sheet: @escaping (VacuumConfig) -> Sheet) {
        self.store = store
        self.sheet = sheet
        _autoClean = State(initialValue: VacuumAutoCleanController(store: store, caller: caller, scheduler: scheduler))
        _open = State(initialValue: initialVacuum)
    }

    var body: some View {
        GeometryReader { proxy in
            let split = SplitPolicy.allowsSplit(size: proxy.size, isRegularWidth: sizeClass == .regular)
            Group {
                if split {
                    HStack(alignment: .top, spacing: 0) {
                        ScrollView { vacuumsSection.padding(HassTokens.Spacing.l) }
                            .frame(width: SplitPolicy.dividerX(width: proxy.size.width, hingeMidX: nil))
                        Divider()
                        ScrollView { autoCleanSection.padding(HassTokens.Spacing.l) }
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: HassTokens.Spacing.xl) {
                            vacuumsSection
                            autoCleanSection
                        }
                        .padding(HassTokens.Spacing.l)
                    }
                }
            }
            .accessibilityIdentifier(split ? "vacuums.layout.split" : "vacuums.layout.single")
        }
        .navigationTitle("Vacuums")
        .sheet(item: $open) { vacuum in
            sheet(vacuum).vacuumPresentation()
        }
    }

    private var vacuumsSection: some View {
        VacuumSection("Robot Vacuums") {
            DynamicGridLayout(minCellWidth: minTileWidth, maxColumns: 3) {
                ForEach(Vacuums.all) { vacuum in
                    let state = store.entity(vacuum.entityId).state
                    let visual = VacuumVisual.state(state?.state)
                    GlassTile(
                        title: vacuum.title,
                        subtitle: VacuumFormat.tileSubtitle(state: state?.state, battery: store.entity(vacuum.batteryEntityId).state?.state),
                        symbol: VacuumStyle.symbol(visual.icon),
                        tint: VacuumStyle.color(visual.tone == .neutral ? .active : visual.tone),
                        isActive: visual.tone != .unavailable && visual.tone != .neutral,
                        kind: .navigate
                    ) { open = vacuum }
                    .accessibilityHint("Opens the vacuum controls and map.")
                    .accessibilityIdentifier("vacuums.tile.\(vacuum.vacuumMapId)")
                }
            }
        }
    }

    private var autoCleanSection: some View {
        VacuumSection("Auto-Clean") {
            DynamicGridLayout(minCellWidth: minTileWidth, maxColumns: 3) {
                ForEach(Vacuums.autoCleanControls) { control in
                    let display = autoClean.display(control)
                    GlassTile(
                        title: control.title,
                        subtitle: display.subtitle,
                        symbol: VacuumStyle.symbol(control.icon),
                        tint: VacuumStyle.autoClean,
                        isActive: display.isEnabled,
                        isUnavailable: display.isUnavailable,
                        kind: .toggle
                    ) { autoClean.toggle(control) }
                    .accessibilityIdentifier("vacuums.autoClean.\(control.entityId)")
                }
            }
        }
    }
}

/// The Home entry that opens the Vacuums page (web At a Glance "Vacuums" quick link). Until the navigation
/// flyout lands this is the page's only route.
struct VacuumsHomeLink: View {
    var body: some View {
        NavigationLink {
            VacuumsScreen()
        } label: {
            HStack(spacing: HassTokens.Spacing.m) {
                Image(systemName: VacuumStyle.symbol("mdi:robot-vacuum"))
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text("Vacuums")
                    .font(.headline)
                    .foregroundStyle(HassTokens.Ink.primary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(HassTokens.Ink.secondary)
                    .accessibilityHidden(true)
            }
            .padding(HassTokens.Spacing.m)
            .frame(minHeight: HassTokens.minTarget + 12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: HassTokens.Radius.tile, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: HassTokens.Radius.tile, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.vacuums")
    }
}
