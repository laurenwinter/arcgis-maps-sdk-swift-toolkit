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
import ArcGIS

/// The `FloorFilter` component simplifies visualization of GIS data for a specific floor of a
/// building in your application. It allows you to filter the floor plan data displayed in your map
/// or scene view to a site, a facility (building) in the site, or a floor in the facility.
public struct FloorFilter: View {
    @Environment(\.horizontalSizeClass)
    private var horizontalSizeClass: UserInterfaceSizeClass?
    
    /// Creates a `FloorFilter`.
    /// - Parameters:
    ///   - floorManager: The floor manager used by the `FloorFilter`.
    ///   - alignment: Determines the display configuration of Floor Filter elements.
    ///   - automaticSelectionMode: The selection behavior of the floor filter.
    ///   - viewpoint: Viewpoint updated when the selected site or facility changes.
    ///   - isNavigating: A Boolean value indicating whether the map is currently being navigated.
    ///   - selection: The selected site, facility, or level.
    public init(
        floorManager: FloorManager,
        alignment: Alignment,
        automaticSelectionMode: FloorFilterAutomaticSelectionMode = .always,
        viewpoint: Binding<Viewpoint?> = .constant(nil),
        isNavigating: Binding<Bool>,
        selection: Binding<FloorFilterSelection?>? = nil
    ) {
        _viewModel = StateObject(
            wrappedValue: FloorFilterViewModel(
                automaticSelectionMode: automaticSelectionMode,
                floorManager: floorManager,
                viewpoint: viewpoint
            )
        )
        self.alignment = alignment
        self.isNavigating = isNavigating
        self.viewpoint = viewpoint
        self.selection = selection
    }
    
    /// The view model used by the `FloorFilter`.
    @StateObject private var viewModel: FloorFilterViewModel
    
    /// A Boolean value that indicates whether the site and facility selector is presented.
    @State private var isSitesAndFacilitiesHidden = true
    
    /// The selected site, floor, or level.
    private var selection: Binding<FloorFilterSelection?>?
    
    /// The alignment configuration.
    private let alignment: Alignment
    
    /// The width of the level selector.
    private var levelSelectorWidth: CGFloat = 60
    
    /// The `Viewpoint` used to pan/zoom to the selected site/facility.
    /// If `nil`, there will be no automatic pan/zoom operations or automatic selection support.
    private var viewpoint: Binding<Viewpoint?>
    
    /// Button to open and close the site and facility selector.
    private var sitesAndFacilitiesButton: some View {
        Button {
            isSitesAndFacilitiesHidden.toggle()
        } label: {
            Image(systemName: "building.2")
                .padding(.toolkitDefault)
                .opacity(viewModel.isLoading ? .zero : 1)
                .overlay {
                    if viewModel.isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                    }
                }
        }
    }
    
    /// A view that displays the level selector and the sites and facilites button.
    private var levelSelectorContainer: some View {
        VStack {
            if isTopAligned {
                sitesAndFacilitiesButton
                if viewModel.hasLevelsToDisplay {
                    Divider()
                    levelSelector
                }
            } else {
                if viewModel.hasLevelsToDisplay {
                    levelSelector
                    Divider()
                }
                sitesAndFacilitiesButton
            }
        }
        .frame(width: levelSelectorWidth)
        .esriBorder()
        .frame(
            maxWidth: horizontalSizeClass == .compact ? .infinity : nil,
            maxHeight: .infinity,
            alignment: alignment
        )
    }
    
    /// A Boolean value indicating whether the map is currently being navigated.
    private var isNavigating: Binding<Bool>
    
    /// Indicates that the selector should be presented with a top oriented alignment configuration.
    private var isTopAligned: Bool {
        alignment.vertical == .top
    }
    
    /// A view that allows selecting between levels.
    @ViewBuilder private var levelSelector: some View {
        LevelSelector(
            isTopAligned: isTopAligned,
            levels: viewModel.sortedLevels
        )
    }
    
    /// A configured `SiteAndFacilitySelector` view.
    ///
    /// The layering of the `SiteAndFacilitySelector` over a `RoundedRectangle` is needed to
    /// produce a rounded corners effect. We can not simply use `.esriBorder()` here because
    /// applying the `cornerRadius()` modifier on `SiteAndFacilitySelector`'s underlying
    /// `NavigationView` causes a rendering bug. This bug remains in iOS 16 with
    /// `NavigationStack` and has been reported to Apple as FB10034457.
    @ViewBuilder private var siteAndFacilitySelector: some View {
        if horizontalSizeClass == .compact {
            Color.clear
                .sheet(isPresented: .constant(!$isSitesAndFacilitiesHidden.wrappedValue)) {
                    SiteAndFacilitySelector(isHidden: $isSitesAndFacilitiesHidden)
                }
        } else {
            ZStack {
                Color.clear
                    .esriBorder()
                SiteAndFacilitySelector(isHidden: $isSitesAndFacilitiesHidden)
                    .padding([.top, .leading, .trailing], 2.5)
                    .padding(.bottom)
            }
            .opacity(isSitesAndFacilitiesHidden ? .zero : 1)
        }
    }
    
    public var body: some View {
        HStack(alignment: .bottom) {
            if alignment.horizontal == .trailing {
                siteAndFacilitySelector
                levelSelectorContainer
            } else {
                levelSelectorContainer
                siteAndFacilitySelector
            }
        }
        // Ensure space for filter text field on small screens in landscape
        .frame(minHeight: 100)
        .environmentObject(viewModel)
        .disabled(viewModel.isLoading)
        .onChange(of: selection?.wrappedValue) { newValue in
            // Prevent a double-set if the view model triggered the original change.
            guard newValue != viewModel.selection else { return }
            switch newValue {
            case .site(let site): viewModel.setSite(site)
            case .facility(let facility): viewModel.setFacility(facility)
            case .level(let level): viewModel.setLevel(level)
            case .none: viewModel.clearSelection()
            }
        }
        .onChange(of: viewModel.selection) { newValue in
            // Prevent a double-set if the user triggered the original change.
            guard selection?.wrappedValue != newValue else { return }
            selection?.wrappedValue = newValue
        }
        .onChange(of: viewpoint.wrappedValue) { newViewpoint in
            guard isNavigating.wrappedValue else { return }
            if let newViewpoint {
                viewModel.onViewpointChanged(newViewpoint)
            }
        }
    }
    
    /// The width of the level selector.
    /// - Parameter width: The new width for the level selector.
    /// - Returns: The `FloorFilter`.
    public func levelSelectorWidth(_ width: CGFloat) -> Self {
        var copy = self
        copy.levelSelectorWidth = width
        return copy
    }
}
