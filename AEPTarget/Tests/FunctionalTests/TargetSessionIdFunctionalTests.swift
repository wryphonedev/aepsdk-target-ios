/*
 Copyright 2022 Adobe. All rights reserved.
 This file is licensed to you under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License. You may obtain a copy
 of the License at http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, software distributed under
 the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
 OF ANY KIND, either express or implied. See the License for the specific language
 governing permissions and limitations under the License.
 */

import Foundation

@testable import AEPCore
@testable import AEPServices
@testable import AEPTarget
import XCTest

class TargetSessionIdFunctionalTests: TargetFunctionalTestsBase {
    
    func testSetSessionId() {
        let data: [String: Any] = [
            "sessionid": "mockSessionId",
        ]
        let event = Event(name: "TargetSetSessionIdentifier", type: "com.adobe.eventType.target", source: "com.adobe.eventSource.requestIdentity", data: data)
        
        // creates a configuration shared state
        mockRuntime.simulateSharedState(extensionName: "com.adobe.module.configuration", event: event, data: (value: mockConfigSharedState, status: .set))
        
        // registers the event listeners for Target extension
        target.onRegistered()
        
        guard let eventListener: EventListener = mockRuntime.listeners["com.adobe.eventType.target-com.adobe.eventSource.requestIdentity"] else {
            XCTFail()
            return
        }
        XCTAssertTrue(target.readyForEvent(event))
        eventListener(event)
        
        XCTAssertEqual("mockSessionId", target.targetState.sessionId)

        let requestDataArray: [[String: Any]?] = [
            TargetRequest(mboxName: "t_test_01", defaultContent: "default", targetParameters: TargetParameters(parameters: ["mbox-parameter-key1": "mbox-parameter-value1"]), contentCallback: nil),
        ].map {
            $0.asDictionary()
        }

        let loadRequestData: [String: Any] = [
            "request": requestDataArray,
            "targetparams": TargetParameters(profileParameters: mockProfileParam).asDictionary() as Any,
        ]
        let loadRequestEvent = Event(name: "TargetLoadRequest", type: "com.adobe.eventType.target", source: "com.adobe.eventSource.requestContent", data: loadRequestData)

        // creates a lifecycle shared state
        mockRuntime.simulateSharedState(extensionName: "com.adobe.module.lifecycle", event: loadRequestEvent, data: (value: mockLifecycleData, status: .set))

        // creates an identity shared state
        mockRuntime.simulateSharedState(extensionName: "com.adobe.module.identity", event: loadRequestEvent, data: (value: mockIdentityData, status: .set))

        // override network service
        let mockNetworkService = TestableNetworkService()
        ServiceProvider.shared.networkService = mockNetworkService
        mockNetworkService.mock { request in
            // verifies network request
            XCTAssertNotNil(request)
            guard let _ = self.payloadAsDictionary(request.connectPayload) else {
                XCTFail()
                return nil
            }
            XCTAssertTrue(request.url.absoluteString.contains("https://acopprod3.tt.omtrdc.net/rest/v1/delivery/?client=acopprod3&sessionId=mockSessionId"))
            return nil
        }
        guard let targetRequestListener: EventListener = mockRuntime.listeners["com.adobe.eventType.target-com.adobe.eventSource.requestContent"] else {
            XCTFail()
            return
        }
        XCTAssertTrue(target.readyForEvent(loadRequestEvent))
        targetRequestListener(loadRequestEvent)
    }

    func testSetSessionId_emptyString() {
        let data: [String: Any] = [
            "sessionid": "",
        ]

        let event = Event(name: "TargetSetSessionIdentifier", type: "com.adobe.eventType.target", source: "com.adobe.eventSource.requestIdentity", data: data)
        mockRuntime.simulateSharedState(extensionName: "com.adobe.module.configuration", event: event, data: (value: mockConfigSharedState, status: .set))
        target.onRegistered()
        guard let eventListener: EventListener = mockRuntime.listeners["com.adobe.eventType.target-com.adobe.eventSource.requestIdentity"] else {
            XCTFail()
            return
        }
        eventListener(event)
        XCTAssertEqual("", target.targetState.storedSessionId)
    }

    func testSetSessionId_privacyOptOut() {
        let data: [String: Any] = [
            "sessionid": "mockSessionId",
        ]

        let event = Event(name: "TargetSetSessionIdentifier", type: "com.adobe.eventType.target", source: "com.adobe.eventSource.requestIdentity", data: data)
        mockRuntime.simulateSharedState(extensionName: "com.adobe.module.configuration", event: event, data: (value: mockConfigSharedState, status: .set))
        mockConfigSharedState["global.privacy"] = "optedout"
        target.targetState.updateConfigurationSharedState(mockConfigSharedState)
        target.onRegistered()
        guard let eventListener: EventListener = mockRuntime.listeners["com.adobe.eventType.target-com.adobe.eventSource.requestIdentity"] else {
            XCTFail()
            return
        }
        eventListener(event)
        XCTAssertEqual("", target.targetState.storedSessionId)
        XCTAssertNotEqual("mockSessionId", target.targetState.storedSessionId)
    }
    
    func testGetSessionId() {
        let event = Event(name: "TargetGetSessionIdentifier", type: "com.adobe.eventType.target", source: "com.adobe.eventSource.requestIdentity", data: nil)
        mockRuntime.simulateSharedState(extensionName: "com.adobe.module.configuration", event: event, data: (value: mockConfigSharedState, status: .set))
        target.onRegistered()
        target.targetState.updateSessionId("mockSessionId")
        guard let eventListener: EventListener = mockRuntime.listeners["com.adobe.eventType.target-com.adobe.eventSource.requestIdentity"] else {
            XCTFail()
            return
        }
        eventListener(event)
        XCTAssertEqual(1, mockRuntime.dispatchedEvents.count)
        XCTAssertEqual(mockRuntime.dispatchedEvents[0].name, "TargetResponseIdentity")
        XCTAssertEqual(mockRuntime.dispatchedEvents[0].type, "com.adobe.eventType.target")
        XCTAssertEqual(mockRuntime.dispatchedEvents[0].source, "com.adobe.eventSource.responseIdentity")
        XCTAssertEqual(event.id, mockRuntime.dispatchedEvents[0].responseID)
        if let data = mockRuntime.dispatchedEvents[0].data, let id = data["sessionid"] as? String {
            XCTAssertEqual(id, "mockSessionId")
            return
        }
        XCTFail()
    }

    func testGetSessionId_withEmptyStoredId() {
        let event = Event(name: "TargetGetSessionIdentifier", type: "com.adobe.eventType.target", source: "com.adobe.eventSource.requestIdentity", data: nil)
        mockRuntime.simulateSharedState(extensionName: "com.adobe.module.configuration", event: event, data: (value: mockConfigSharedState, status: .set))
        target.onRegistered()
        target.targetState.updateSessionId("")
        guard let eventListener: EventListener = mockRuntime.listeners["com.adobe.eventType.target-com.adobe.eventSource.requestIdentity"] else {
            XCTFail()
            return
        }
        eventListener(event)
        XCTAssertEqual(1, mockRuntime.dispatchedEvents.count)
        XCTAssertEqual(mockRuntime.dispatchedEvents[0].name, "TargetResponseIdentity")
        XCTAssertEqual(mockRuntime.dispatchedEvents[0].type, "com.adobe.eventType.target")
        XCTAssertEqual(mockRuntime.dispatchedEvents[0].source, "com.adobe.eventSource.responseIdentity")
        XCTAssertEqual(event.id, mockRuntime.dispatchedEvents[0].responseID)
        if let data = mockRuntime.dispatchedEvents[0].data, let id = data["sessionid"] as? String {
            XCTAssertNotEqual("", id)
            return
        } else {
            XCTFail()
        }
    }
}
