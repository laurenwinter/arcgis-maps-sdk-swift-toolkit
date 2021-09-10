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

import Swift
import SwiftUI
import ArcGIS
import Combine

/// Performs searches and manages search state for a Search, or optionally without a UI connection.
@MainActor
public class SearchViewModel: ObservableObject {
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
    
    /// Creates a `SearchViewModel`.
    /// - Parameters:
    ///   - defaultPlaceholder: The string shown in the search view when no user query is entered.
    ///   - activeSource: Tracks the currently active search source.
    ///   - queryArea: The search area to be used for the current query.
    ///   - queryCenter: Defines the center for the search.
    ///   - resultMode: Defines how many results to return.
    ///   - sources: Collection of search sources to be used.
    public convenience init(
        defaultPlaceholder: String = .defaultPlaceholder,
        activeSource: SearchSourceProtocol? = nil,
        queryArea: Geometry? = nil,
        queryCenter: Point? = nil,
        resultMode: SearchResultMode = .automatic,
        sources: [SearchSourceProtocol] = []
    ) {
        self.init()
        self.defaultPlaceholder = defaultPlaceholder
        self.activeSource = activeSource
        self.queryArea = queryArea
        self.queryCenter = queryCenter
        self.resultMode = resultMode
        self.sources = sources
    }
    
    /// The string shown in the search view when no user query is entered.
    /// Default is "Find a place or address".
    public var defaultPlaceholder: String = .defaultPlaceholder
    
    /// The active search source.  If `nil`, the first item in `sources` is used.
    public var activeSource: SearchSourceProtocol?
    
    /// Tracks the current user-entered query. This property drives both suggestions and searches.
    @Published
    public var currentQuery: String = "" {
        didSet {
            results = nil
            if currentQuery.isEmpty {
                suggestions = nil
            }
        }
    }
    
    /// The search area to be used for the current query.  This property should be updated
    /// as the user navigates the map/scene, or at minimum before calling `commitSearch`.
    public var queryArea: Geometry? = nil
    
    /// Defines the center for the search. For most use cases, this should be updated by the view
    /// every time the user navigates the map.
    public var queryCenter: Point?
    
    /// Defines how many results to return. Defaults to Automatic. In automatic mode, an appropriate
    /// number of results is returned based on the type of suggestion chosen
    /// (driven by the IsCollection property).
    public var resultMode: SearchResultMode = .automatic
    
    /// Collection of results. `nil` means no query has been made. An empty array means there
    /// were no results, and the view should show an appropriate 'no results' message.
    @Published
    public private(set) var results: Result<[SearchResult], SearchError>? {
        didSet {
            switch results {
            case .success(let results):
                if results.count == 1 {
                    selectedResult = results.first
                }
            default:
                selectedResult = nil
            }
        }
    }
    
    /// Tracks selection of results from the `results` collection. When there is only one result,
    /// that result is automatically assigned to this property. If there are multiple results, the view sets
    /// this property upon user selection. This property is observable. The view should observe this
    /// property and update the associated GeoView's viewpoint, if configured.
    @Published
    public var selectedResult: SearchResult?
    
    /// Collection of search sources to be used. This list is maintained over time and is not nullable.
    /// The view should observe this list for changes. Consumers should add and remove sources from
    /// this list as needed.
    /// NOTE:  only the first source is currently used; multiple sources are not yet supported.
    public var sources: [SearchSourceProtocol] = []
    
    /// Collection of suggestion results. Defaults to `nil`. This collection will be set to empty when there
    /// are no suggestions, `nil` when no suggestions have been requested. If the list is empty,
    /// a useful 'no results' message should be shown by the view.
    @Published
    public private(set) var suggestions: Result<[SearchSuggestion], SearchError>?
    
    private var subscriptions = Set<AnyCancellable>()
    
    /// The currently executing async task.  `currentTask` should be cancelled
    /// prior to starting another async task.
    private var currentTask: Task<Void, Never>?
    
    private func makeEffectiveSource(
        with searchArea: Geometry?,
        preferredSearchLocation: Point?
    ) -> SearchSourceProtocol? {
        guard var source = currentSource() else { return nil }
        source.searchArea = searchArea ?? queryArea
        source.preferredSearchLocation = preferredSearchLocation
        return source
    }
    
    /// Starts a search. `selectedResult` and `results`, among other properties, are set
    /// asynchronously. Other query properties are read to define the parameters of the search.
    /// - Parameter searchArea: geometry used to constrain the results.  If `nil`, the
    /// `queryArea` property is used instead.  If `queryArea` is `nil`, results are not constrained.
    public func commitSearch(_ searchArea: Geometry? = nil) {
        guard !currentQuery.trimmingCharacters(in: .whitespaces).isEmpty,
              let source = makeEffectiveSource(with: searchArea, preferredSearchLocation: queryCenter) else {
                  return
              }
        
        kickoffTask(commitSearchTask(source))
    }
    
    /// Updates suggestions list asynchronously.
    @MainActor  // TODO:  ???? yes or no or a better idea?  Maybe model is an Actor and not a class
    public func updateSuggestions() {
        guard !currentQuery.trimmingCharacters(in: .whitespaces).isEmpty,
              let source = makeEffectiveSource(with: queryArea, preferredSearchLocation: queryCenter) else {
                  return
              }
        guard currentSuggestion == nil else {
            // don't update suggestions if currently searching for one
            return
        }
        
        kickoffTask(updateSuggestionsTask(source))
    }
    
    @Published
    public var currentSuggestion: SearchSuggestion? {
        didSet {
            if let currentSuggestion = currentSuggestion {
                currentQuery = currentSuggestion.displayTitle
                kickoffTask(acceptSuggestionTask(currentSuggestion))
            }
        }
    }
    
    /// Commits a search from a specific suggestion. Results will be set asynchronously. Behavior is
    /// generally the same as `commitSearch`, except `searchSuggestion` is used instead of the
    /// `currentQuery` property.
    /// - Parameters:
    ///   - searchSuggestion: The suggestion to use to commit the search.
    public func acceptSuggestion(
        _ searchSuggestion: SearchSuggestion
    ) async -> Void {
        currentQuery = searchSuggestion.displayTitle
        
        suggestions = nil
        
        currentTask?.cancel()
        currentTask = acceptSuggestionTask(searchSuggestion)
        await currentTask?.value
    }
    
    private func kickoffTask(_ task: Task<(), Never>) {
        suggestions = nil
        currentTask?.cancel()
        currentTask = task
    }
    
    /// Clears the search. This will set the results list to null, clear the result selection, clear suggestions,
    /// and reset the current query.
    public func clearSearch() {
        // Setting currentQuery to "" will reset everything necessary.
        currentQuery = ""
    }
}

extension SearchViewModel {
    private func commitSearchTask(_ source: SearchSourceProtocol) -> Task<(), Never> {
        Task {
            do {
                try await process(searchResults: source.search(currentQuery))
            } catch is CancellationError {
                results = nil
            } catch {
                results = .failure(SearchError(error))
            }
        }
    }
    
    private func updateSuggestionsTask(_ source: SearchSourceProtocol) -> Task<(), Never> {
        Task {
            let suggestResult = await Result {
                try await source.suggest(currentQuery)
            }
            
            switch suggestResult {
            case .success(let suggestResults):
                suggestions = .success(suggestResults)
            case .failure(let error):
                suggestions = .failure(SearchError(error))
                break
            case nil:
                suggestions = nil
                break
            }
        }
    }
    
    private func acceptSuggestionTask(_ searchSuggestion: SearchSuggestion) -> Task<(), Never> {
        Task {
            do {
                try await process(searchResults: searchSuggestion.owningSource.search(searchSuggestion))
            } catch is CancellationError {
                results = nil
            } catch {
                results = .failure(SearchError(error))
            }
            // once we are done searching for the suggestion, then reset it to nil
            currentSuggestion = nil
        }
    }
    
    private func process(searchResults: [SearchResult], isCollection: Bool = true) {
        let effectiveResults: [SearchResult]
        
        switch (resultMode) {
        case .single:
            if let firstResult = searchResults.first {
                effectiveResults = [firstResult]
            } else {
                effectiveResults = []
            }
        case .multiple:
            effectiveResults = searchResults
        case .automatic:
            if isCollection {
                effectiveResults = searchResults
            } else {
                if let firstResult = searchResults.first {
                    effectiveResults = [firstResult]
                }
                else {
                    effectiveResults = []
                }
            }
        }
        
        results = .success(effectiveResults)
    }
}

extension SearchViewModel {
    /// Returns the search source to be used in geocode operations.
    /// - Returns: The search source to use.
    func currentSource() -> SearchSourceProtocol? {
        var source: SearchSourceProtocol?
        if let activeSource = activeSource {
            source = activeSource
        } else {
            source = sources.first
        }
        return source
    }
}

public extension String {
    static let defaultPlaceholder = "Find a place or address"
}
