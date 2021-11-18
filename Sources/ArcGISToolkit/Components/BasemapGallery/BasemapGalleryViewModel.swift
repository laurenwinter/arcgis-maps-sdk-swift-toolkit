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

/// Manages the state for a `BasemapGallery`.
@MainActor
public class BasemapGalleryViewModel: ObservableObject {
    /// Creates a `BasemapGalleryViewModel`.
    /// - Parameters:
    ///   - geoModel: The `GeoModel`.
    ///   - portal: The `Portal` to load base maps from.
    ///   - basemapGalleryItems: A list of pre-defined base maps to display.
    public init(
        geoModel: GeoModel? = nil,
        portal: Portal? = nil,
        basemapGalleryItems: [BasemapGalleryItem] = []
    ) {
        self.geoModel = geoModel
        self.portal = portal
        self.basemapGalleryItems.append(contentsOf: basemapGalleryItems)
        
        // Note that we don't want to store these tasks and cancel them
        // before kicking off another operation becasue both of these
        // operations could have been started elsewhere as well as here.
        // Canceling them here would also cancel those other operations,
        // which we don't want to do.
        Task { await load(geoModel: geoModel) }
        Task { await fetchBasemaps(from: portal) }
    }
    
    @Published
    /// The error generated by fetching the `Basemaps` from the `Portal`.
    public var fetchBasemapsError: Error? = nil
    
    /// If the `GeoModel` is not loaded when passed to the `BasemapGalleryViewModel`, then
    /// the geoModel will be immediately loaded. The spatial reference of geoModel dictates which
    /// basemaps from the gallery are enabled. When an enabled basemap is selected by the user,
    /// the geoModel will have its basemap replaced with the selected basemap.
    public var geoModel: GeoModel? {
        didSet {
            Task { await load(geoModel: geoModel) }
        }
    }
    
    /// The `Portal` object, if any.  Setting the portal will automatically fetch it's basemaps
    /// and add them to the `basemapGalleryItems` array.
    public var portal: Portal? {
        didSet {
            Task { await fetchBasemaps(from: portal) }
        }
    }
    
    /// The list of basemaps currently visible in the gallery.  It is comprised of items passed into
    /// the `BasemapGalleryItem` constructor and items loaded from the `Portal`.
    @Published
    public var basemapGalleryItems: [BasemapGalleryItem] = []
    
    /// `BasemapGalleryItem` representing the `GeoModel`'s current base map. This may be a
    /// basemap which does not exist in the gallery.
    @Published
    public private(set) var currentBasemapGalleryItem: BasemapGalleryItem? = nil {
        didSet {
            guard let item = currentBasemapGalleryItem else { return }
            geoModel?.basemap = item.basemap
        }
    }
    
    @Published
    /// The error signifying the spatial reference of the GeoModel and that of a potential
    /// current `BasemapGalleryItem` do not match.
    public private(set) var spatialReferenceMismatchError: SpatialReferenceMismatchError? = nil
    
    /// This attempts to set `currentBasemapGalleryItem`. `currentBasemapGalleryItem`
    /// will be set if it's spatialReference matches that of the current geoModel.  If the spatialReferences
    /// do not match, `currentBasemapGalleryItem` will be unchanged.
    /// - Parameter basemapGalleryItem: The new, potential, `BasemapGalleryItem`.
    public func updateCurrentBasemapGalleryItem(_ basemapGalleryItem: BasemapGalleryItem) {
        Task {
            try await basemapGalleryItem.updateSpatialReferenceStatus(
                geoModel?.actualSpatialReference
            )
            await MainActor.run {
                if basemapGalleryItem.spatialReferenceStatus == .match ||
                    basemapGalleryItem.spatialReferenceStatus == .unknown {
                    currentBasemapGalleryItem = basemapGalleryItem
                }
                else {
                    spatialReferenceMismatchError = SpatialReferenceMismatchError(
                        basemapSR: basemapGalleryItem.spatialReference,
                        geoModelSR: geoModel?.actualSpatialReference
                    )
                }
            }
        }
    }
}

private extension GeoModel {
    var actualSpatialReference: SpatialReference? {
        (self as? ArcGIS.Scene)?.sceneViewTilingScheme == .webMercator ?
        SpatialReference.webMercator :
        spatialReference
    }
}

private extension BasemapGalleryViewModel {
    func fetchBasemaps(from portal: Portal?) async {
        guard let portal = portal else { return }
        
        do {
            basemapGalleryItems += try await portal.developerBasemaps.map {
                BasemapGalleryItem(basemap: $0)
            }
        } catch {
            fetchBasemapsError = error
        }
    }
    
    func load(geoModel: GeoModel?) async {
        guard let geoModel = geoModel else { return }
        
        do {
            try await geoModel.load()
            if let basemap = geoModel.basemap {
                currentBasemapGalleryItem = BasemapGalleryItem(basemap: basemap)
            }
            else {
                currentBasemapGalleryItem = nil
            }
        } catch { }
    }
}
