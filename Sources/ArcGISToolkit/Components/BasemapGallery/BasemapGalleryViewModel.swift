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
    /// - Remark: If `portal` is non-nil, the portal's basemaps will be loaded.  If `portal` is
    /// `nil`, ArcGISOnline's developer basemaps will be loaded.  In both cases, the basemaps
    /// will be added to `basemapGalleryItems`.
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
        
        // Note that we don't want to store this tasks and cancel it
        // before kicking off another operation because these operations
        // could have been started elsewhere as well as here.
        // Canceling them here would also cancel those other operations,
        // which we don't want to do.
        Task {
            // Load the geomodel.
            await load(geoModel: geoModel)

            // If we have a portal or no basemapGalleryItems were supplied,
            // then load the default basemaps from the portal, if any, or AGOL.
            if portal != nil || basemapGalleryItems.isEmpty {
                var thePortal = portal
                var useDeveloperBasemaps = false
                if thePortal == nil {
                    thePortal = Portal.arcGISOnline(isLoginRequired: false)
                    useDeveloperBasemaps = true
                }
                await fetchBasemaps(
                    from: thePortal,
                    useDeveloperBasemaps: useDeveloperBasemaps
                )
            }
        }
    }
    
    /// The error generated by fetching the `Basemaps` from the `Portal`.
    @Published
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
    /// and replace the`basemapGalleryItems` array with the fetched basemaps.
    public var portal: Portal? {
        didSet {
            Task { await fetchBasemaps(from: portal, append: false) }
        }
    }
    
    /// The list of basemaps currently visible in the gallery.  It is comprised of items passed into
    /// the `BasemapGalleryItem` constructor property and items loaded either from `portal` or
    /// from ArcGISOnline if `portal` is `nil`.
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
    
    /// The error signifying the spatial reference of the GeoModel and that of a potential
    /// current `BasemapGalleryItem` do not match.
    @Published
    public private(set) var spatialReferenceMismatchError: SpatialReferenceMismatchError? = nil
    
    /// This attempts to set `currentBasemapGalleryItem`. `currentBasemapGalleryItem`
    /// will be set if it's spatialReference matches that of the current geoModel.  If the spatialReferences
    /// do not match, `currentBasemapGalleryItem` will be unchanged.
    /// - Parameter basemapGalleryItem: The new, potential, `BasemapGalleryItem`.
    public func updateCurrentBasemapGalleryItem(_ basemapGalleryItem: BasemapGalleryItem) {
        Task {
            // Ensure the geoModel is loaded.
            try await geoModel?.load()
            
            // Reset the mismatch error.
            spatialReferenceMismatchError = nil
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

internal extension GeoModel {
    var actualSpatialReference: SpatialReference? {
        (self as? ArcGIS.Scene)?.sceneViewTilingScheme == .webMercator ?
        SpatialReference.webMercator :
        spatialReference
    }
}

private extension BasemapGalleryViewModel {
    /// Fetches the basemaps from the given portal and populates `basemapGalleryItems` with
    /// items created from the fetched basemaps.
    /// - Parameters:
    ///   - portal: Portal to fetch basemaps from
    ///   - useDeveloperBasemaps: If `true`, will always use the portal's developer basemaps.  If
    ///   `false`, it will use either the portal's basemaps or vector basemaps, depending on the value of
    ///   `portal.portalInfo.useVectorBasemaps`.
    ///   - append: If `true`, will appended fetched basemaps to `basemapGalleryItems`.
    ///   If `false`, it will clear `basemapGalleryItems` before adding the fetched basemaps.
    func fetchBasemaps(
        from portal: Portal?,
        useDeveloperBasemaps: Bool = false,
        append: Bool = true
    ) async {
        guard let portal = portal else { return }
        
        do {
            try await portal.load()
        
            var tmpItems = [BasemapGalleryItem]()
            if useDeveloperBasemaps {
                tmpItems += try await portal.developerBasemaps.map {
                    BasemapGalleryItem(basemap: $0)
                }
            } else if let portalInfo = portal.portalInfo,
                      portalInfo.useVectorBasemaps {
                tmpItems += try await portal.vectorBasemaps.map {
                    BasemapGalleryItem(basemap: $0)
                }
            } else {
                tmpItems += try await portal.basemaps.map {
                    BasemapGalleryItem(basemap: $0)
                }
            }
            
            if append {
                basemapGalleryItems += tmpItems
            }
            else {
                basemapGalleryItems = tmpItems
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

/// A value that represents a SpatialReference mismatch.
public struct SpatialReferenceMismatchError: Error {
    /// The basemap's spatial reference
    public let basemapSR: SpatialReference?

    /// The geomodel's spatial reference
    public let geoModelSR: SpatialReference?
}

extension SpatialReferenceMismatchError: Equatable {}
