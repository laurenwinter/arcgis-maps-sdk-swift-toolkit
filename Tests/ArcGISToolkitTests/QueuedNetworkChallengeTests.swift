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
import XCTest
@testable import ArcGISToolkit

@MainActor final class QueuedNetworkChallengeTests: XCTestCase {
    func testInit() {
        let challenge = QueuedNetworkChallenge(host: "host.com", kind: .serverTrust)
        XCTAssertEqual(challenge.host, "host.com")
        XCTAssertEqual(challenge.kind, .serverTrust)
    }
    
    func testResumeAndComplete() async {
        let challenge = QueuedNetworkChallenge(host: "host.com", kind: .serverTrust)
        challenge.resume(with: .useCredential(.serverTrust))
        let disposition = await challenge.disposition
        XCTAssertEqual(disposition, .useCredential(.serverTrust))
        
        // Make sure multiple simultaneous listeners can await the completion.
        let t1 = Task { await challenge.complete() }
        let t2 = Task { await challenge.complete() }
        await t1.value
        await t2.value
    }
}
