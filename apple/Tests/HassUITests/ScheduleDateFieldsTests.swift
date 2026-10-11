import AppKit
import Foundation
@testable import HassDesign
import SwiftUI
import Testing

/// `ScheduleDatePicker`: immediate and debounced reporting, and the layout at accessibility text sizes.
@MainActor
@Suite(.serialized)
struct ScheduleDateFieldsTests {
    private final class Reports: @unchecked Sendable {
        var dates: [Date] = []
    }

    private func picker(delay: Duration?, reports: Reports, part: ScheduleDateField.Part = .date) -> ScheduleDatePicker {
        let field = ScheduleDateField(label: "Return", part: part, value: Date(timeIntervalSince1970: 1_800_000_000), identifier: "f") { reports.dates.append($0) }
        return ScheduleDatePicker(field: field, commitDelay: delay)
    }

    private func binding(_ picker: ScheduleDatePicker) throws -> Binding<Date> {
        try #require(ViewProbe.first(Binding<Date>.self, in: picker.body))
    }

    @Test func withoutADelayEveryChangeIsReportedAtOnce() throws {
        let reports = Reports()
        let selection = try binding(picker(delay: nil, reports: reports))
        selection.wrappedValue = Date(timeIntervalSince1970: 1_800_003_600)
        selection.wrappedValue = Date(timeIntervalSince1970: 1_800_007_200)
        #expect(reports.dates == [Date(timeIntervalSince1970: 1_800_003_600), Date(timeIntervalSince1970: 1_800_007_200)])
    }

    /// Turns the real date wheel of a hosted picker to `date`, as the person does.
    private func turn(_ hosted: HostedWindow, to date: Date) throws {
        let picker = try #require(hosted.views(ofType: NSDatePicker.self).first)
        picker.dateValue = date
        picker.sendAction(picker.action, to: picker.target)
    }

    @Test func withADelayOneAdjustmentIsOneReport() async throws {
        let reports = Reports()
        let hosted = HostedWindow(picker(delay: .milliseconds(40), reports: reports).frame(width: 400, height: 80))
        // Scrolling a wheel changes the value many times; only where it stops is sent.
        for step in 1...5 { try turn(hosted, to: Date(timeIntervalSince1970: 1_800_000_000 + Double(step) * 86400)) }
        #expect(reports.dates.isEmpty)
        for _ in 0..<500 where reports.dates.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        try await Task.sleep(for: .milliseconds(150))
        #expect(reports.dates.count == 1)
        #expect(reports.dates.last.map { Calendar.current.isDate($0, inSameDayAs: Date(timeIntervalSince1970: 1_800_000_000 + 5 * 86400)) } == true)
    }

    @Test func aHostedPickerWithoutADelayReportsEachChange() throws {
        let reports = Reports()
        let hosted = HostedWindow(picker(delay: nil, reports: reports).frame(width: 400, height: 80))
        try turn(hosted, to: Date(timeIntervalSince1970: 1_800_086_400))
        #expect(reports.dates.count == 1)
    }

    @Test func rendersInBothLayoutsAndForBothParts() {
        let reports = Reports()
        for size in [DynamicTypeSize.large, .accessibility5] {
            for part in [ScheduleDateField.Part.date, .time] {
                let view = picker(delay: nil, reports: reports, part: part).environment(\.dynamicTypeSize, size).frame(width: 360, height: 300)
                #expect(ImageRenderer(content: view).cgImage != nil)
            }
        }
    }
}
