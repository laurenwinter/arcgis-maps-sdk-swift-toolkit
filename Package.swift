// swift-tools-version:5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.
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

import PackageDescription

let package = Package(
    name: "arcgis-maps-sdk-swift-toolkit",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v15),
        .macCatalyst(.v15)
    ],
    products: [
        .library(
            name: "ArcGISToolkit",
            targets: ["ArcGISToolkit"]
        ),
        .library(
            name: "ArcGIS",
            targets: ["ArcGIS"]
        ),
        .library(
            name: "CoreArcGIS",
            targets: ["CoreArcGIS"]
        ),
    ],
    targets: [
        .target(
            name: "ArcGISToolkit",
            dependencies: [
                "ArcGIS",
                "CoreArcGIS"
            ]
        ),
        .testTarget(
            name: "ArcGISToolkitTests",
            dependencies: ["ArcGISToolkit"]
        ),
        .binaryTarget(name: "ArcGIS", url: "https://sitescan-ios-dependencies.s3.amazonaws.com/ArcGIS/ArcGIS_200.1.0_3801/ArcGIS.xcframework.zip",
                      checksum: "0865e516b90bf6c0e2c7a5253ce058a20902e2db8d073944b894c4eeb66728ef"),
        .binaryTarget(name: "CoreArcGIS", url: "https://sitescan-ios-dependencies.s3.amazonaws.com/ArcGIS/CoreArcGIS_200.1.0_3801/CoreArcGIS.xcframework.zip",
                      checksum: "e557e5a658858d8434bec33032f5f1eebb3f568c77032304c631ffcb822535ba")
    ]
)
