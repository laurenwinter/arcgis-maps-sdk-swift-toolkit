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

@MainActor final class QueuedArcGISChallengeTests: XCTestCase {
    func testInit() {
        let challenge = QueuedArcGISChallenge(host: "host.com") { _ in
            fatalError()
        }
        
        XCTAssertEqual(challenge.host, "host.com")
        XCTAssertNotNil(challenge.tokenCredentialProvider)
    }
    
    func testResumeWithLogin() async {
        struct MockError: Error {}
        
        let challenge = QueuedArcGISChallenge(host: "host.com") { _ in
            throw MockError()
        }
        challenge.resume(with: .init(username: "user1", password: "1234"))
        
        let result = await challenge.result
        XCTAssertTrue(result.error is MockError)
        
        // Make sure multiple simultaneous listeners can await the completion.
        let t1 = Task { await challenge.complete() }
        let t2 = Task { await challenge.complete() }
        await t1.value
        await t2.value
    }
    
    func testCancel() async {
        let challenge = QueuedArcGISChallenge(host: "host.com") { _ in
            fatalError()
        }
        challenge.cancel()
        
        let result = await challenge.result
        XCTAssertEqual(result.value, .cancelAuthenticationChallenge)
    }
}

private extension Result {
    /// The error that is encapsulated in the failure case when this result is a failure.
    var error: Error? {
        switch self {
        case .failure(let error):
            return error
        case .success:
            return nil
        }
    }
    
    /// The success value that is encapsulated in the success case when this result is a success.
    var value: Success? {
        switch self {
        case .failure:
            return nil
        case .success(let value):
            return value
        }
    }
}
