// Copyright 2021 Esri.

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

/// Defines how many results to return; one, many, or automatic based on circumstance.
public enum SearchResultMode {
    /// Search should always result in at most one result.
    case single
    /// Search should always try to return multiple results.
    case multiple
    /// Search should make a choice based on context. E.g. 'coffee shop' should be multiple results,
    /// while '380 New York St. Redlands' should be one result.
    case automatic
}

/// The outcome of a geocode operation (search or suggestion).
///
/// An empty results or suggestions array means there were no results.
///
/// The `failure` case contains the error (if any) generated by the last search or suggestion
/// operation.
public enum SearchOutcome {
    case results([SearchResult])
    case suggestions([SearchSuggestion])
    case failure(String)
}

/// Performs searches and manages search state for a search, or optionally without a UI connection.
@MainActor final class SearchViewModel: ObservableObject {
    /// Creates a `SearchViewModel`.
    /// - Parameters:
    ///   - sources: Collection of search sources to be used.
    ///   - viewpoint: The `Viewpoint` used to pan/zoom to results. If `nil`, there will be
    ///   no zooming to results.
    init(
        sources: [SearchSource] = [],
        viewpoint: Binding<Viewpoint?>? = nil
    ) {
        self.sources = sources
        self.viewpoint = viewpoint
    }
    
    /// The active search source.  If `nil`, the first item in `sources` is used.
    private var activeSource: SearchSource? = nil
    
    /// Tracks the current user-entered query. This property drives both suggestions and searches.
    @Published var currentQuery = "" {
        willSet {
            isEligibleForRequery = false
            
            guard let searchOutcome = searchOutcome else { return }
            switch searchOutcome {
            case .suggestions(_):
                if currentQuery.isEmpty {
                    self.searchOutcome = nil
                }
            default:
                self.searchOutcome = nil
            }
        }
    }
    
    /// The extent at the time of the last search.
    private var lastSearchExtent: Envelope? = nil {
        didSet {
            isEligibleForRequery = false
        }
    }
    
    /// The current map/scene view extent. Defaults to `nil`.
    ///
    /// This should be updated as the user navigates the map/scene. It will be
    /// used to determine the value of `isEligibleForRequery` for the 'Repeat
    /// search here' behavior. If that behavior is not wanted, it should be left `nil`.
    var geoViewExtent: Envelope? = nil {
        willSet {
            guard isGeoViewNavigating,
                  !isEligibleForRequery,
                  !currentQuery.isEmpty,
                  let lastExtent = lastSearchExtent,
                  let newExtent = newValue
            else { return }
            
            viewpoint?.wrappedValue = nil
            
            // Check extent difference.
            let widthDiff = abs(lastExtent.width - newExtent.width)
            let heightDiff = abs(lastExtent.height - newExtent.height)
            
            let widthThreshold = lastExtent.width * 0.25
            let heightThreshold = lastExtent.height * 0.25
            
            isEligibleForRequery = widthDiff > widthThreshold || heightDiff > heightThreshold
            guard !isEligibleForRequery else { return }
            
            // Check center difference.
            let centerDiff = GeometryEngine.distance(
                from: lastExtent.center,
                to: newExtent.center
            )
            let currentExtentAvg = (lastExtent.width + lastExtent.height) / 2.0
            let threshold = currentExtentAvg * 0.25
            isEligibleForRequery = (centerDiff ?? 0.0) > threshold
        }
    }
    
    /// `true` when the geoView is navigating, `false` otherwise. Set by the external client.
    var isGeoViewNavigating = false
    
    /// The `Viewpoint` used to pan/zoom to results. If `nil`, there will be no zooming to results.
    var viewpoint: Binding<Viewpoint?>? = nil
    
    /// The `GraphicsOverlay` used to display results. If `nil`, no results will be displayed.
    var resultsOverlay: GraphicsOverlay? = nil
    
    /// If `true`, will set the viewpoint to the extent of the results, plus a little buffer, which will
    /// cause the geoView to zoom to the extent of the results. If `false`,
    /// no setting of the viewpoint will occur.
    private var shouldZoomToResults = true
    
    /// `true` if the extent has changed by a set amount after a `Search` or `AcceptSuggestion`
    /// call. This property is used by the view to enable 'Repeat search here' functionality. This property is
    /// observable, and the view should use it to hide and show the 'repeat search' button.
    /// Changes to this property are driven by changes to the `geoViewExtent` property. This value will be
    /// `true` if the extent center changes by more than 25% of the average of the extent's height and width
    /// at the time of the last search or if the extent width/height changes by the same amount.
    @Published private(set) var isEligibleForRequery = false
    
    /// The search area to be used for the current query. Results will be limited to those.
    /// within `QueryArea`. Defaults to `nil`.
    var queryArea: Geometry? = nil
    
    /// Defines the center for the search. For most use cases, this should be updated by the view
    /// every time the user navigates the map.
    var queryCenter: Point?
    
    /// Defines how many results to return. Defaults to ``SearchResultMode/automatic``.
    /// In automatic mode, an appropriate number of results is returned based on the type of suggestion
    /// chosen (driven by the suggestion's `isCollection` property).
    var resultMode: SearchResultMode = .automatic
    
    /// A search outcome that contains the search and suggestion results. A `nil` value means no
    /// query has been made.
    @Published private(set) var searchOutcome: SearchOutcome? {
        didSet {
            if case let .results(results) = searchOutcome {
                display(searchResults: results)
                selectedResult = results.count == 1 ? results.first : nil
            } else {
                display(searchResults: [])
                selectedResult = nil
            }
        }
    }
    
    /// Tracks selection of results from the `results` collection. When there is only one result,
    /// that result is automatically assigned to this property. If there are multiple results, the view sets
    /// this property upon user selection. This property is observable. The view should observe this
    /// property and update the associated GeoView's viewpoint, if configured.
    var selectedResult: SearchResult? {
        willSet {
            (selectedResult?.geoElement as? Graphic)?.isSelected = false
        }
        didSet {
            (selectedResult?.geoElement as? Graphic)?.isSelected = true
            display(selectedResult: selectedResult)
        }
    }
    
    /// Collection of search sources to be used. This list is maintained over time and is not nullable.
    /// The view should observe this list for changes. Consumers should add and remove sources from
    /// this list as needed.
    /// NOTE: Only the first source is currently used; multiple sources are not yet supported.
    var sources: [SearchSource] = []
    
    /// The currently executing async task. `currentTask` will be cancelled
    /// prior to starting another async task.
    private var currentTask: Task<Void, Never>? {
        willSet {
            currentTask?.cancel()
        }
    }
    
    /// Starts a search. `selectedResult` and `results`, among other properties, are set
    /// asynchronously. Other query properties are read to define the parameters of the search.
    func commitSearch() {
        currentTask = Task { await self.doSearch() }
    }
    
    /// Repeats the last search, limiting results to the extent specified in `geoViewExtent`.
    func repeatSearch() {
        currentTask = Task { await self.doRepeatSearch() }
    }
    
    /// Updates suggestions list asynchronously.
    func updateSuggestions() {
        guard currentSuggestion == nil
        else {
            // Don't update suggestions if currently searching for one.
            return
        }
        
        currentTask = Task { await self.doUpdateSuggestions() }
    }
    
    /// The suggestion currently selected by the user.
    var currentSuggestion: SearchSuggestion? {
        didSet {
            if let currentSuggestion = currentSuggestion {
                acceptSuggestion(currentSuggestion)
            }
        }
    }
    
    /// Commits a search from a specific suggestion. Results will be set asynchronously. Behavior is
    /// generally the same as `commitSearch`, except `searchSuggestion` is used instead of the
    /// `currentQuery` property.
    /// - Parameter searchSuggestion: The suggestion to use to commit the search.
    func acceptSuggestion(_ searchSuggestion: SearchSuggestion) {
        currentQuery = searchSuggestion.displayTitle
        currentTask = Task { await self.doAcceptSuggestion(searchSuggestion) }
    }
}

private extension SearchViewModel {
    /// Method to execute an async `repeatSearch` operation.
    func doRepeatSearch() async {
        guard !currentQuery.trimmingCharacters(in: .whitespaces).isEmpty,
              let queryExtent = geoViewExtent,
              let source = currentSource()
        else { return }
        
        // We're repeating a search, don't zoom to results.
        shouldZoomToResults = false
        await search(with: {
            try await source.repeatSearch(
                currentQuery,
                searchExtent: queryExtent
            )
        })
    }
    
    /// Method to execute an async `search` operation.
    func doSearch() async {
        guard !currentQuery.trimmingCharacters(in: .whitespaces).isEmpty,
              let source = currentSource()
        else { return }
        
        await search(with: {
            try await source.search(
                currentQuery,
                searchArea: queryArea,
                preferredSearchLocation: queryCenter
            )
        } )
    }
    
    /// Method to execute an async `suggest` operation.
    func doUpdateSuggestions() async {
        guard !currentQuery.trimmingCharacters(in: .whitespaces).isEmpty,
              let source = currentSource()
        else { return }
        
        do {
            let suggestions = try await source.suggest(
                currentQuery,
                searchArea: queryArea,
                preferredSearchLocation: queryCenter
            )
            searchOutcome = .suggestions(suggestions)
        } catch is CancellationError {
            // Do nothing if user cancelled and let next task set searchOutcome.
        } catch {
            searchOutcome = .failure(error.localizedDescription)
        }
    }
    
    /// Method to execute an async `search` operation using a search suggestion..
    /// - Parameter searchSuggestion: The suggestion to search for.
    func doAcceptSuggestion(_ searchSuggestion: SearchSuggestion) async {
        await search(
            with: {
                try await searchSuggestion.owningSource.search(
                    searchSuggestion,
                    searchArea: queryArea,
                    preferredSearchLocation: queryCenter
                )
            },
            isCollection: searchSuggestion.isCollection
        )
        
        // once we are done searching for the suggestion, then reset it to nil
        currentSuggestion = nil
    }
    
    /// Method to execute a search action and process the results.
    /// - Parameter action: The action to perform prior to processing results.
    /// - Parameter isCollection: `true` if the results are based on a collection search.
    func search(
        with action: () async throws -> [SearchResult],
        isCollection: Bool = true) async {
            do {
                // User is performing a search, so set `lastSearchExtent`.
                lastSearchExtent = geoViewExtent
                try await process(searchResults: action(), isCollection: isCollection)
            } catch is CancellationError {
                searchOutcome = nil
            } catch {
                searchOutcome = .failure(error.localizedDescription)
            }
        }
    
    /// Method to process search results based on the current `resultMode`.
    /// - Parameters:
    ///   - searchResults: The array of search results to process.
    ///   - isCollection: `true` if the results are based on a collection search.
    func process(searchResults: [SearchResult], isCollection: Bool) {
        let effectiveResults: [SearchResult]
        
        switch resultMode {
        case .single:
            effectiveResults = Array(searchResults.prefix(1))
        case .multiple:
            effectiveResults = searchResults
        case .automatic:
            if isCollection {
                effectiveResults = searchResults
            } else {
                effectiveResults = Array(searchResults.prefix(1))
            }
        }
        
        searchOutcome = .results(effectiveResults)
    }
}

extension SearchViewModel {
    /// Returns the search source to be used in geocode operations.
    /// - Returns: The search source to use.
    func currentSource() -> SearchSource? {
        let source: SearchSource?
        if let activeSource = activeSource {
            source = activeSource
        } else {
            source = sources.first
        }
        return source
    }
}

private extension SearchViewModel {
    func display(searchResults: [SearchResult]) {
        guard let resultsOverlay = resultsOverlay else { return }
        let resultGraphics: [Graphic] = searchResults.compactMap { result in
            guard let graphic = result.geoElement as? Graphic else { return nil }
            graphic.update(with: result)
            return graphic
        }
        resultsOverlay.removeAllGraphics()
        resultsOverlay.addGraphics(resultGraphics)
        
        // Make sure we have a viewpoint to zoom to.
        guard let viewpoint = viewpoint else { return }
        
        if !resultGraphics.isEmpty,
           let envelope = resultsOverlay.extent,
           shouldZoomToResults {
            let builder = EnvelopeBuilder(envelope: envelope)
            builder.expand(factor: 1.1)
            let targetExtent = builder.toGeometry()
            viewpoint.wrappedValue = Viewpoint(
                targetExtent: targetExtent
            )
            lastSearchExtent = targetExtent
        } else {
            viewpoint.wrappedValue = nil
        }
        
        if !shouldZoomToResults { shouldZoomToResults = true }
    }
    
    func display(selectedResult: SearchResult?) {
        guard let selectedResult = selectedResult else { return }
        viewpoint?.wrappedValue = selectedResult.selectionViewpoint
    }
}

extension SearchOutcome: Equatable {}

private extension Graphic {
    func update(with result: SearchResult) {
        if symbol == nil {
            symbol = Symbol.searchResult()
        }
        setAttributeValue(result.displayTitle, forKey: "displayTitle")
        setAttributeValue(result.displaySubtitle, forKey: "displaySubtitle")
    }
}

private extension Symbol {
    /// A search result marker symbol.
    static func searchResult() -> MarkerSymbol {
        let image = UIImage.mapPin
        let symbol = PictureMarkerSymbol(image: image)
        symbol.offsetY = Float(image.size.height / 2.0)
        return symbol
    }
}

extension UIImage {
    static var mapPin: UIImage {
        return UIImage(named: "MapPin", in: Bundle.module, with: nil)!
    }
}
