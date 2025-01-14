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

import ArcGIS
import SwiftUI

/// `Bookmarks` allows a user to view and select from a set of bookmarks.
public struct Bookmarks: View {
    /// A list of selectable bookmarks.
    @State private var bookmarks: [Bookmark] = []
    
    /// A map or scene containing bookmarks.
    private var geoModel: GeoModel?
    
    /// Indicates if bookmarks have loaded and are ready for display.
    @State private var isGeoModelLoaded = false
    
    /// The height of the header content.
    @State private var headerHeight: CGFloat = .zero
    
    /// Determines if the bookmarks list is currently shown or not.
    @Binding private var isPresented: Bool
    
    /// The height of the list content.
    @State private var listHeight: CGFloat = .zero
    
    /// A bookmark that was selected.
    @State private var selectedBookmark: Bookmark? = nil
    
    /// User defined action to be performed when a bookmark is selected.
    ///
    /// Use this when you prefer to self-manage the response to a bookmark selection. Use either
    /// `onSelectionChanged(perform:)` or `viewpoint` exclusively.
    var selectionChangedAction: ((Bookmark) -> Void)? = nil
    
    /// If non-`nil`, this viewpoint is updated when a bookmark is selected.
    private var viewpoint: Binding<Viewpoint?>?
    
    /// Sets an action to perform when the bookmark selection changes.
    /// - Parameter action: The action to perform when the bookmark selection has changed.
    public func onSelectionChanged(
        perform action: @escaping (Bookmark) -> Void
    ) -> Bookmarks {
        var copy = self
        copy.selectionChangedAction = action
        return copy
    }
    
    /// Performs the necessary actions when a bookmark is selected.
    ///
    /// This includes indicating that bookmarks should be set to a hidden state, and changing the viewpoint
    /// binding (if provided) or calling the action provided by the `onSelectionChanged(perform:)` modifier.
    /// - Parameter bookmark: The bookmark that was selected.
    func selectBookmark(_ bookmark: Bookmark) {
        isPresented = false
        if let viewpoint = viewpoint {
            viewpoint.wrappedValue = bookmark.viewpoint
        } else if let onSelectionChanged = selectionChangedAction {
            onSelectionChanged(bookmark)
        }
    }
    
    /// Creates a `Bookmarks` component.
    /// - Parameters:
    ///   - isPresented: Determines if the bookmarks list is presented.
    ///   - bookmarks: An array of bookmarks. Use this when displaying bookmarks defined at runtime.
    ///   - viewpoint: A viewpoint binding that will be updated when a bookmark is selected.
    ///   Alternately, you can use the `onSelectionChanged(perform:)` modifier to handle
    ///   bookmark selection.
    public init(
        isPresented: Binding<Bool>,
        bookmarks: [Bookmark],
        viewpoint: Binding<Viewpoint?>? = nil
    ) {
        _isPresented = isPresented
        self.bookmarks = bookmarks
        self.viewpoint = viewpoint
    }
    
    /// Creates a `Bookmarks` component.
    /// - Parameters:
    ///   - isPresented: Determines if the bookmarks list is presented.
    ///   - geoModel: A `GeoModel` authored with pre-existing bookmarks.
    ///   - viewpoint: A viewpoint binding that will be updated when a bookmark is selected.
    ///   Alternately, you can use the `onSelectionChanged(perform:)` modifier to handle
    ///   bookmark selection.
    public init(
        isPresented: Binding<Bool>,
        geoModel: GeoModel,
        viewpoint: Binding<Viewpoint?>? = nil
    ) {
        self.geoModel = geoModel
        self.viewpoint = viewpoint
        _isPresented = isPresented
    }
    
    public var body: some View {
        VStack {
            BookmarksHeader(isPresented: $isPresented)
                .padding([.horizontal, .top])
                .onSizeChange {
                    headerHeight = $0.height
                }
            ScrollView {
                VStack {
                    if geoModel == nil || isGeoModelLoaded {
                        BookmarksList(bookmarks: bookmarks)
                            .onSelectionChanged {
                                selectBookmark($0)
                            }
                    } else {
                        loadingView
                    }
                }
                .onSizeChange {
                    listHeight = $0.height
                }
            }
        }
        .frame(idealHeight: headerHeight + listHeight)
    }
    
    /// A view that is shown while a `GeoModel` is loading.
    private var loadingView: some View {
        ProgressView()
            .padding()
            .task {
                do {
                    try await geoModel?.load()
                    bookmarks = geoModel?.bookmarks ?? []
                    isGeoModelLoaded = true
                } catch {
                    print(error.localizedDescription)
                }
            }
    }
}
