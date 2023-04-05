/*
 Copyright 2021 Adobe. All rights reserved.
 This file is licensed to you under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License. You may obtain a copy
 of the License at http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, software distributed under
 the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
 OF ANY KIND, either express or implied. See the License for the specific language
 governing permissions and limitations under the License.
 */
#if os(iOS)
import Foundation

extension TargetRequest {
    /// Constructs a `TargetRequest` object from the event data.
    /// - Parameter dictionary: the event data used to build a `TargetRequest` object
    /// - Returns: `TargetRequest` object
    static func from(dictionary: [String: Any]) -> TargetRequest? {
        if let jsonData = try? JSONSerialization.data(withJSONObject: dictionary), let requestObject = try? JSONDecoder().decode(TargetRequest.self, from: jsonData) {
            return requestObject
        }
        return nil
    }

    /// Constructs an array of `TargetRequest` objects from the event data.
    /// - Parameter dictionaries: the event data used to build`TargetRequest` objects
    /// - Returns: an array of `TargetRequest` objects
    static func from(dictionaries: [[String: Any]]?) -> [TargetRequest]? {
        guard let dictionaries = dictionaries else {
            return nil
        }
        var requests = [TargetRequest]()
        for dictionary in dictionaries {
            if let request = TargetRequest.from(dictionary: dictionary) {
                requests.append(request)
            }
        }
        return requests
    }
}
#endif
