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

import Foundation
import ArcGIS

/// A type that represents a challenge in the queue of authentication challenges.
protocol QueuedChallenge: AnyObject {
    /// Waits for the challenge to complete.
    func complete() async
}

/// An object that represents an ArcGIS authentication challenge in the queue of challenges.
final class QueuedArcGISChallenge: QueuedChallenge {
    /// The ArcGIS authentication challenge.
    let arcGISChallenge: ArcGISAuthenticationChallenge
    
    /// Creates a `QueuedArcGISChallenge`.
    /// - Parameter arcGISChallenge: The associated ArcGIS authentication challenge.
    init(arcGISChallenge: ArcGISAuthenticationChallenge) {
        self.arcGISChallenge = arcGISChallenge
    }
    
    /// Resumes the challenge with a result.
    /// - Parameter result: The result of the challenge.
    func resume(with result: Result<ArcGISAuthenticationChallenge.Disposition, Error>) {
        guard _result == nil else { return }
        _result = result
    }
    
    /// Cancels the challenge.
    func cancel() {
        guard _result == nil else { return }
        _result = .success(.cancelAuthenticationChallenge)
    }
    
    /// Use a streamed property because we need to support multiple listeners
    /// to know when the challenge completed.
    @Streamed private var _result: Result<ArcGISAuthenticationChallenge.Disposition, Error>?
    
    /// The result of the challenge.
    var result: Result<ArcGISAuthenticationChallenge.Disposition, Error> {
        get async {
            await $_result
                .compactMap({ $0 })
                .first(where: { _ in true })!
        }
    }
    
    public func complete() async {
        _ = await result
    }
}

/// An object that represents a network authentication challenge in the queue of challenges.
final class QueuedNetworkChallenge: QueuedChallenge {
    /// The associated network authentication challenge.
    let networkChallenge: NetworkAuthenticationChallenge
    
    /// Creates a `QueuedNetworkChallenge`.
    /// - Parameter networkChallenge: The associated network authentication challenge.
    init(networkChallenge: NetworkAuthenticationChallenge) {
        self.networkChallenge = networkChallenge
    }
    
    /// Resumes the queued challenge.
    /// - Parameter disposition: The disposition to resume with.
    func resume(with disposition: NetworkAuthenticationChallengeDisposition) {
        guard _disposition == nil else { return }
        _disposition = disposition
    }
    
    /// Use a streamed property because we need to support multiple listeners
    /// to know when the challenge completed.
    @Streamed private var _disposition: (NetworkAuthenticationChallengeDisposition)?
    
    /// The resulting disposition of the challenge.
    var disposition: NetworkAuthenticationChallengeDisposition {
        get async {
            await $_disposition
                .compactMap({ $0 })
                .first(where: { _ in true })!
        }
    }
    
    public func complete() async {
        _ = await disposition
    }
    
    /// An enumeration that describes the kind of challenge.
    enum Kind {
        /// A challenge for an untrusted host.
        case serverTrust
        /// A challenge that requires a login via username and password.
        case login
        /// A challenge that requires a client certificate.
        case certificate
    }
    
    /// The kind of challenge.
    var kind: Kind {
        switch networkChallenge.kind {
        case .serverTrust:
            return .serverTrust
        case .ntlm, .basic, .digest:
            return .login
        case .pki:
            return .certificate
        case .htmlForm, .negotiate:
            fatalError("TODO: ")
        }
    }
}
