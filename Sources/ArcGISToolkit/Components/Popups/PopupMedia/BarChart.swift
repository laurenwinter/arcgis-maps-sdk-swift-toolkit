// Copyright 2022 Esri.

// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
// http://www.apache.org/licenses/LICENSE-2.0

// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import SwiftUI
import Charts

/// A view displaying details for popup media.
@available(iOS 16, *)
struct BarChart: View {
    /// The chart data to display.
    let chartData: [ChartData]
    
    /// A Boolean value specifying whether the chart is a "column" chart, with vertical bars.  If it's
    /// not a "column" chart, then the bars are horizontal.
    let isColumnChart: Bool
    
    var body: some View {
        Group {
            Chart(chartData) {
                if isColumnChart {
                    // Vertical bars.
                    BarMark(
                        x: .value("Field", $0.label),
                        y: .value("Value", $0.value)
                    )
                } else {
                    // Horizontal bars.
                    BarMark(
                        x: .value("Value", $0.value),
                        y: .value("Field", $0.label)
                    )
                }
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel(collisionResolution: .greedy, orientation: .verticalReversed)
                }
            }
        }
    }
}
