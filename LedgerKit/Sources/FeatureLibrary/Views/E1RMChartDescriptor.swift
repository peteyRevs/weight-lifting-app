import Accessibility
import SwiftUI

/// What VoiceOver's audio graph and chart rotor read of `E1RMChart` (criterion 12): one series of the weeks
/// that have a value, in order, on a categorical axis of all eight weeks; a week with no session has no point.
/// The one file of the module that imports Accessibility (ruling R2).
struct E1RMChartDescriptor: AXChartDescriptorRepresentable {
    let chart: ExerciseHistoryModel.Chart

    func makeChartDescriptor() -> AXChartDescriptor {
        let values = chart.bars.compactMap(\.number).map(Double.init)
        let points = chart.bars.compactMap { bar in
            bar.number.map { AXDataPoint(x: bar.week, y: Double($0), label: bar.value) }
        }
        let weeks = AXCategoricalDataAxisDescriptor(title: chart.weekAxis, categoryOrder: chart.bars.map(\.week))
        let estimates = AXNumericDataAxisDescriptor(
            title: chart.valueAxis,
            range: (values.min() ?? 0) ... (values.max() ?? 0),
            gridlinePositions: []
        ) { String(Int($0)) }
        return AXChartDescriptor(
            title: chart.spokenTitle,
            summary: nil,
            xAxis: weeks,
            yAxis: estimates,
            additionalAxes: [],
            series: [AXDataSeriesDescriptor(name: chart.spokenTitle, isContinuous: false, dataPoints: points)]
        )
    }
}
