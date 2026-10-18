@testable import HassDesign
import SwiftUI
import Testing

/// Each shared component in `.agents/design/motion-components.md` that colours from state registers a state colour animation
/// with ``MotionAudit`` when it renders, so dropping the helper fails here. The colour key of each is checked to change with the
/// input that changes the colour.
@MainActor
struct ComponentMotionTests {
    private func audit<V: View>(_ view: @autoclosure () -> V, width: CGFloat = 402) -> Set<String> {
        StateColorTransitionTests.audit(view(), width: width)
    }

    // MARK: GlassTile

    private func face(isActive: Bool = false, isError: Bool = false, isUnavailable: Bool = false, family: ColorFamily? = .climate,
                      fillRGB: UInt32? = nil, wash: Color? = nil, level: Double? = nil, tint: Color = .blue,
                      levelTint: Color? = nil) -> GlassTileFace {
        GlassTileFace(title: "Tile", subtitle: "State", symbol: "thermometer", tint: tint, family: family, fillRGB: fillRGB,
                      isActive: isActive, isUnavailable: isUnavailable, isError: isError, level: level, levelTint: levelTint, wash: wash)
    }

    @Test func glassTileAnimatesGroundInkGlyphAndRim() {
        #expect(audit(face()).contains("GlassTile"))
        #expect(audit(face(isActive: true)).contains("GlassTile"))
        #expect(audit(face(isActive: true, family: .lights)).contains("GlassTile"))
        #expect(audit(GlassTile(title: "T", symbol: "lock", family: .contact, isActive: true, kind: .command) {}).contains("GlassTile"))
        #expect(audit(face().environment(\.tileFinish, .frostedModule)).contains("GlassTile"))
        #expect(audit(face().environment(\.tileFinish, .tintedGlass)).contains("GlassTile"))
        #expect(audit(face(family: nil)).contains("GlassTile"))
    }

    @Test func glassTileColourKeyChangesWithEveryInput() {
        let base = face().colorKey
        #expect(face(isActive: true).colorKey != base)
        #expect(face(isError: true).colorKey != base)
        #expect(face(isUnavailable: true).colorKey != base)
        #expect(face(family: .heating).colorKey != base)
        #expect(face(fillRGB: 0xFF0000).colorKey != base)
        #expect(face(wash: .red).colorKey != base)
        #expect(face(tint: .red).colorKey != base)
        #expect(face(levelTint: .red).colorKey != base)
        #expect(face(level: 0.5).colorKey != base)
        #expect(face().colorKey == base)
    }

    @Test func glassTileLevelWidthIsProgressNotColour() {
        // A band appearing is a colour change; its width moving is not (BrightnessTile animates that on `quick`).
        #expect(face(level: 0.3).colorKey == face(level: 0.8).colorKey)
        #expect(face(level: 0).colorKey == face(level: nil).colorKey)
    }

    // MARK: Tiles and pills

    @Test func brightnessTileColoursThroughTheFace() {
        let tile = BrightnessTile(title: "Hall", tint: .yellow, percent: 40, onPower: { _ in }, onBrightness: { _ in })
        #expect(audit(tile).contains("GlassTile"))
        #expect(audit(BrightnessTile(title: "Hall", tint: .yellow, percent: 0, onPower: { _ in }, onBrightness: { _ in })).contains("GlassTile"))
    }

    @Test func statusPillAnimatesIconAndFill() {
        for tone in [StatusPill.Tone.neutral, .ok, .active, .warning, .danger, .unavailable] {
            #expect(audit(StatusPill(label: "L", value: "V", symbol: "wind", tone: tone)).contains("StatusPill"))
        }
        #expect(audit(StatusPill(label: "L", value: "V", detail: "d", symbol: "wind", surface: .groupedList)).contains("StatusPill"))
        #expect(audit(StatusPill(label: "L", value: "V", symbol: "wind", surface: .module)).contains("StatusPill"))
    }

    @Test func primaryButtonFadesEnabledAndDisabled() {
        #expect(audit(PrimaryButton("Save") {}).contains("PrimaryButton"))
        #expect(audit(PrimaryButton("Save") {}.disabled(true)).contains("PrimaryButton"))
        #expect(audit(PrimaryButton("Water", family: .water) {}).contains("PrimaryButton"))
    }

    @Test func moduleRowButtonStyleReleasesOnQuick() {
        let row = Button("Row") {}.buttonStyle(ModuleRowButtonStyle())
        #expect(audit(row).contains("ModuleRowButtonStyle"))
        #expect(audit(ModuleList { ModuleRow("A", subtitle: "b", symbol: "lock", glyph: .red, subtitleInk: .orange) }).contains("ModuleRow"))
    }

    @Test func optionRowsAnimateTheirSelection() {
        for selected in [false, true] {
            #expect(audit(SelectableOptionRow(title: "Heat", detail: "d", symbol: "flame", tint: .orange, isSelected: selected) {})
                .contains("SelectableOptionRow"))
            #expect(audit(SelectableOptionRow(title: "Heat", detail: "d", symbol: "flame", tint: .orange, isSelected: selected, isDisabled: true) {})
                .contains("SelectableOptionRow"))
            #expect(audit(FilterOptionRow(title: "A", subtitle: "s", isSelected: selected) {}).contains("FilterOptionRow"))
        }
    }

    @Test func floatingActionBarAnimatesActiveTintAndGlyph() {
        let actions = [
            FloatingAction(id: "filter", title: "Filter", symbol: "slider.horizontal.3", showsTitle: false, isActive: true) {},
            FloatingAction(id: "add", title: "Add", symbol: "plus") {},
        ]
        #expect(audit(FloatingActionBar(actions: actions)).contains("FloatingActionBar"))
        let search = FloatingSearch(text: .constant("milk"), isExpanded: .constant(false), prompt: "Search")
        #expect(audit(FloatingActionBar(actions: actions, search: search)).contains("FloatingActionBar"))
    }

    @Test func thermostatDialAnimatesMarkerAndHandleColours() {
        let configuration = ThermostatDialConfiguration(title: "Office", current: 70, targets: .range(low: 68, high: 74), action: "heating")
        #expect(audit(ThermostatDial(configuration) { _ in }, width: 320).contains("ThermostatDial"))
        let cooling = ThermostatDialConfiguration(title: "Office", current: 76, targets: .single(72), action: "cooling")
        #expect(audit(ThermostatDial(cooling) { _ in }, width: 320).contains("ThermostatDial"))
    }
}
