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
import SwiftyJSON
import XCTest

class TargetTntIdFunctionalTests: TargetFunctionalTestsBase {
    func testSetTntId() {
        XCTAssertNil(target.targetState.tntId)
        XCTAssertNil(target.targetState.edgeHost)
        
        let data: [String: Any] = [
            TargetConstants.EventDataKeys.TNT_ID: "66E5C681-4F70-41A2-86AE-F1E151443B10.35_0",
        ]
        let setTntIdEvent = Event(name: "TargetSetTnTIdentifier", type: "com.adobe.eventType.target", source: "com.adobe.eventSource.requestIdentity", data: data)
        
        // creates a configuration shared state
        mockRuntime.simulateSharedState(extensionName: "com.adobe.module.configuration", event: setTntIdEvent, data: (value: mockConfigSharedState, status: .set))
        
        // registers the event listeners for Target extension
        target.onRegistered()
        
        guard let eventListener: EventListener = mockRuntime.listeners["com.adobe.eventType.target-com.adobe.eventSource.requestIdentity"] else {
            XCTFail()
            return
        }
        
        XCTAssertTrue(target.readyForEvent(setTntIdEvent))
        // handles the set tntId event
        eventListener(setTntIdEvent)
        
        XCTAssertNotNil(target.targetState.tntId)
        XCTAssertEqual(target.targetState.tntId, "66E5C681-4F70-41A2-86AE-F1E151443B10.35_0")
        XCTAssertEqual(target.targetState.edgeHost, "mboxedge35.tt.omtrdc.net")

        let requestDataArray: [[String: Any]?] = [
            TargetRequest(mboxName: "t_test_01", defaultContent: "default", targetParameters: TargetParameters(profileParameters: ["mbox-parameter-key1": "mbox-parameter-value1"]), contentCallback: nil),
        ].map {
            $0.asDictionary()
        }

        let loadRequestData: [String: Any] = [
            "request": requestDataArray,
            "targetparams": TargetParameters(profileParameters: mockProfileParam).asDictionary() as Any,
        ]
        let loadRequestEvent = Event(name: "TargetLoadRequest", type: "com.adobe.eventType.target", source: "com.adobe.eventSource.requestContent", data: loadRequestData)

        // creates a configuration shared state
        mockRuntime.simulateSharedState(extensionName: "com.adobe.module.configuration", event: loadRequestEvent, data: (value: mockConfigSharedState, status: .set))

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
            XCTAssertTrue(request.url.absoluteString.contains("mboxedge35.tt.omtrdc.net"))
            guard let requestJson = try? JSON(data: request.connectPayload) else {
                XCTFail("Target request json should be valid for load request.")
                return nil
            }
            XCTAssertEqual("66E5C681-4F70-41A2-86AE-F1E151443B10.35_0", requestJson["id"]["tntId"].stringValue)
            return nil
        }
        guard let targetRequestListener: EventListener = mockRuntime.listeners["com.adobe.eventType.target-com.adobe.eventSource.requestContent"] else {
            XCTFail()
            return
        }
        XCTAssertTrue(target.readyForEvent(loadRequestEvent))
        // handles the load request event
        targetRequestListener(loadRequestEvent)
    }

    func testSetTntId_emptyString() {
        let data: [String: Any] = [
            TargetConstants.EventDataKeys.TNT_ID: "",
        ]

        let setTntIdEvent = Event(name: "TargetSetTnTIdentifier", type: "com.adobe.eventType.target", source: "com.adobe.eventSource.requestIdentity", data: data)
        mockRuntime.simulateSharedState(extensionName: "com.adobe.module.configuration", event: setTntIdEvent, data: (value: mockConfigSharedState, status: .set))
        
        // registers the event listeners for Target extension
        target.onRegistered()

        guard let eventListener: EventListener = mockRuntime.listeners["com.adobe.eventType.target-com.adobe.eventSource.requestIdentity"] else {
            XCTFail()
            return
        }
        XCTAssertTrue(target.readyForEvent(setTntIdEvent))
        eventListener(setTntIdEvent)
        XCTAssertEqual(target.targetState.tntId, "")
        XCTAssertNil(target.targetState.edgeHost)
    }

    func testNotSetTntId() {
        XCTAssertNil(target.targetState.tntId)
        XCTAssertNil(target.targetState.edgeHost)
        
        let requestDataArray: [[String: Any]?] = [
            TargetRequest(mboxName: "t_test_01", defaultContent: "default", targetParameters: TargetParameters(profileParameters: ["mbox-parameter-key1": "mbox-parameter-value1"]), contentCallback: nil),
        ].map {
            $0.asDictionary()
        }

        let loadRequestData: [String: Any] = [
            "request": requestDataArray,
            "targetparams": TargetParameters(profileParameters: mockProfileParam).asDictionary() as Any,
        ]
        let loadRequestEvent = Event(name: "TargetLoadRequest", type: "com.adobe.eventType.target", source: "com.adobe.eventSource.requestContent", data: loadRequestData)

        // creates a configuration shared state
        mockRuntime.simulateSharedState(extensionName: "com.adobe.module.configuration", event: loadRequestEvent, data: (value: mockConfigSharedState, status: .set))

        // creates a lifecycle shared state
        mockRuntime.simulateSharedState(extensionName: "com.adobe.module.lifecycle", event: loadRequestEvent, data: (value: mockLifecycleData, status: .set))

        // creates an identity shared state
        mockRuntime.simulateSharedState(extensionName: "com.adobe.module.identity", event: loadRequestEvent, data: (value: mockIdentityData, status: .set))

        // registers the event listeners for Target extension
        target.onRegistered()

        // override network service
        let mockNetworkService = TestableNetworkService()
        ServiceProvider.shared.networkService = mockNetworkService
        mockNetworkService.mock { request in
            // verifies network request
            XCTAssertNotNil(request)
            XCTAssertTrue(request.url.absoluteString.contains("acopprod3.tt.omtrdc.net"))
            guard let payloadDictionary = self.payloadAsDictionary(request.connectPayload) else {
                XCTFail("Target request payload should be valid for load request.")
                return nil
            }
            let payloadJson = self.prettify(payloadDictionary)
            XCTAssertFalse(payloadJson.contains("\"tntId\""))
            return nil
        }
        guard let targetRequestListener: EventListener = mockRuntime.listeners["com.adobe.eventType.target-com.adobe.eventSource.requestContent"] else {
            XCTFail()
            return
        }
        XCTAssertTrue(target.readyForEvent(loadRequestEvent))
        // handles the prefetch event
        targetRequestListener(loadRequestEvent)
    }
    
    func testSetTntId_privacyOptOut() {
        let data: [String: Any] = [
            TargetConstants.EventDataKeys.TNT_ID: "66E5C681-4F70-41A2-86AE-F1E151443B10.35_0",
        ]

        let setTntIdEvent = Event(name: "TargetSetTnTIdentifier", type: "com.adobe.eventType.target", source: "com.adobe.eventSource.requestIdentity", data: data)
        mockConfigSharedState["global.privacy"] = "optedout"
        mockRuntime.simulateSharedState(extensionName: "com.adobe.module.configuration", event: setTntIdEvent, data: (value: mockConfigSharedState, status: .set))
        target.targetState.updateConfigurationSharedState(mockConfigSharedState)
        
        // registers the event listeners for Target extension
        target.onRegistered()

        guard let eventListener: EventListener = mockRuntime.listeners["com.adobe.eventType.target-com.adobe.eventSource.requestIdentity"] else {
            XCTFail()
            return
        }
        XCTAssertTrue(target.readyForEvent(setTntIdEvent))
        eventListener(setTntIdEvent)
        XCTAssertNil(target.targetState.tntId)
        XCTAssertNil(target.targetState.edgeHost)
    }

    func testSetTntId_noLocationHint() {
        let data: [String: Any] = [
            TargetConstants.EventDataKeys.TNT_ID: "66E5C681-4F70-41A2-86AE-F1E151443B10",
        ]

        let setTntIdEvent = Event(name: "TargetSetTnTIdentifier", type: "com.adobe.eventType.target", source: "com.adobe.eventSource.requestIdentity", data: data)
        mockRuntime.simulateSharedState(extensionName: "com.adobe.module.configuration", event: setTntIdEvent, data: (value: mockConfigSharedState, status: .set))
        
        // registers the event listeners for Target extension
        target.onRegistered()

        guard let eventListener: EventListener = mockRuntime.listeners["com.adobe.eventType.target-com.adobe.eventSource.requestIdentity"] else {
            XCTFail()
            return
        }
        XCTAssertTrue(target.readyForEvent(setTntIdEvent))
        eventListener(setTntIdEvent)
        XCTAssertEqual(target.targetState.tntId, "66E5C681-4F70-41A2-86AE-F1E151443B10")
        XCTAssertNil(target.targetState.edgeHost)
    }
    
    func testSetTntId_invalidLocationHintFormat() {
        let data: [String: Any] = [
            TargetConstants.EventDataKeys.TNT_ID: "66E5C681-4F70-41A2-86AE-F1E151443B10.a1a_0",
        ]

        let setTntIdEvent = Event(name: "TargetSetTnTIdentifier", type: "com.adobe.eventType.target", source: "com.adobe.eventSource.requestIdentity", data: data)
        mockRuntime.simulateSharedState(extensionName: "com.adobe.module.configuration", event: setTntIdEvent, data: (value: mockConfigSharedState, status: .set))
        
        // registers the event listeners for Target extension
        target.onRegistered()

        guard let eventListener: EventListener = mockRuntime.listeners["com.adobe.eventType.target-com.adobe.eventSource.requestIdentity"] else {
            XCTFail()
            return
        }
        XCTAssertTrue(target.readyForEvent(setTntIdEvent))
        eventListener(setTntIdEvent)
        XCTAssertEqual(target.targetState.tntId, "66E5C681-4F70-41A2-86AE-F1E151443B10.a1a_0")
        XCTAssertNil(target.targetState.edgeHost)
    }

    func testGetTntId() {
        let event = Event(name: "TargetGetTnTIdentifier", type: "com.adobe.eventType.target", source: "com.adobe.eventSource.requestIdentity", data: nil)
        mockRuntime.simulateSharedState(extensionName: "com.adobe.module.configuration", event: event, data: (value: mockConfigSharedState, status: .set))
        
        // registers the event listeners for Target extension
        target.onRegistered()
        
        target.targetState.updateTntId("66E5C681-4F70-41A2-86AE-F1E151443B10.35_0")
        guard let eventListener: EventListener = mockRuntime.listeners["com.adobe.eventType.target-com.adobe.eventSource.requestIdentity"] else {
            XCTFail()
            return
        }
        eventListener(event)
        if let data = mockRuntime.dispatchedEvents[0].data, let id = data[TargetConstants.EventDataKeys.TNT_ID] as? String {
            XCTAssertEqual(mockRuntime.dispatchedEvents[0].type, EventType.target)
            XCTAssertEqual(mockRuntime.dispatchedEvents[0].source, EventSource.responseIdentity)
            XCTAssertEqual(id, "66E5C681-4F70-41A2-86AE-F1E151443B10.35_0")
            XCTAssertEqual(mockRuntime.dispatchedEvents[0].name, "TargetResponseIdentity")
            XCTAssertEqual(event.id, mockRuntime.dispatchedEvents[0].responseID)
            return
        }
        XCTFail()
    }

    func testGetTntId_withoutCachedTntId() {
        let event = Event(name: "TargetGetTnTIdentifier", type: "com.adobe.eventType.target", source: "com.adobe.eventSource.requestIdentity", data: nil)
        mockRuntime.simulateSharedState(extensionName: "com.adobe.module.configuration", event: event, data: (value: mockConfigSharedState, status: .set))
        
        // registers the event listeners for Target extension
        target.onRegistered()
        
        XCTAssertNil(target.targetState.tntId)
        guard let eventListener: EventListener = mockRuntime.listeners["com.adobe.eventType.target-com.adobe.eventSource.requestIdentity"] else {
            XCTFail()
            return
        }
        eventListener(event)
        if let data = mockRuntime.dispatchedEvents[0].data {
            XCTAssertNil(data[TargetConstants.EventDataKeys.TNT_ID])
            XCTAssertEqual(mockRuntime.dispatchedEvents[0].type, EventType.target)
            XCTAssertEqual(mockRuntime.dispatchedEvents[0].source, EventSource.responseIdentity)
            XCTAssertEqual(mockRuntime.dispatchedEvents[0].name, "TargetResponseIdentity")
            XCTAssertEqual(event.id, mockRuntime.dispatchedEvents[0].responseID)
            return
        }
        XCTFail()
    }

    func testTntIdAndEdgeHostAreUpdatedInRequest_WhenNewTntIdSet() {
        let responseString = """
            {
              "status": 200,
              "id": {
                "tntId": "DE03D4AD-1FFE-421F-B2F2-303BF26822C1.35_0",
                "marketingCloudVisitorId": "61055260263379929267175387965071996926"
              },
              "requestId": "01d4a408-6978-48f7-95c6-03f04160b257",
              "client": "acopprod3",
              "edgeHost": "mboxedge35.tt.omtrdc.net",
              "prefetch": {
                "mboxes": [
                  {
                    "index": 0,
                    "name": "Drink_1",
                    "options": [
                      {
                        "content": {
                          "key1": "value1"
                        },
                        "type": "json",
                        "eventToken": "uR0kIAPO+tZtIPW92S0NnWqipfsIHvVzTQxHolz2IpSCnQ9Y9OaLL2gsdrWQTvE54PwSz67rmXWmSnkXpSSS2Q=="
                      }
                    ]
                  }
                ]
              }
            }
        """
        let prefetchDataArray: [[String: Any]?] = [
            TargetPrefetch(name: "Drink_1"),
        ].map {
            $0.asDictionary()
        }

        let prefetchRequestData: [String: Any] = [
            "prefetch": prefetchDataArray,
        ]
        let prefetchEvent = Event(name: "TargetPrefetchRequest", type: "com.adobe.eventType.target", source: "com.adobe.eventSource.requestContent", data: prefetchRequestData)
        // override network service
        let mockNetworkService = TestableNetworkService()
        ServiceProvider.shared.networkService = mockNetworkService
        mockNetworkService.mock { _ in
            let validResponse = HTTPURLResponse(url: URL(string: "https://acopprod3.tt.omtrdc.net/rest/v1/delivery")!, statusCode: 200, httpVersion: nil, headerFields: nil)
            return (data: responseString.data(using: .utf8), response: validResponse, error: nil)
        }
        mockRuntime.simulateSharedState(extensionName: "com.adobe.module.configuration", event: prefetchEvent, data: (value: mockConfigSharedState, status: .set))
        
        // registers the event listeners for Target extension
        target.onRegistered()
        
        XCTAssertNil(target.targetState.tntId)
        XCTAssertNil(target.targetState.edgeHost)

        guard let prefetchEventListener: EventListener = mockRuntime.listeners["com.adobe.eventType.target-com.adobe.eventSource.requestContent"] else {
            XCTFail()
            return
        }
        XCTAssertTrue(target.readyForEvent(prefetchEvent))
        
        // handles the prefetch event
        prefetchEventListener(prefetchEvent)

        XCTAssertEqual("DE03D4AD-1FFE-421F-B2F2-303BF26822C1.35_0", target.targetState.tntId)
        XCTAssertEqual("mboxedge35.tt.omtrdc.net", target.targetState.edgeHost)
        
        mockNetworkService.resolvers.removeAll()
        mockNetworkService.mock { request in
            XCTAssertNotNil(request)
            XCTAssertTrue(request.url.absoluteString.contains("mboxedge32.tt.omtrdc.net"))
            guard let requestJson = try? JSON(data: request.connectPayload) else {
                XCTFail("Target request json should be valid for prefetch request.")
                return nil
            }
            XCTAssertEqual("4DBCC39D-4ACA-47D4-A7D2-A85C1C0CC382.32_0", requestJson["id"]["tntId"].stringValue)
            let validResponse = HTTPURLResponse(url: URL(string: "https://mboxedge32.tt.omtrdc.net/rest/v1/delivery")!, statusCode: 200, httpVersion: nil, headerFields: nil)
            return (data: responseString.data(using: .utf8), response: validResponse, error: nil)
        }
        
        let data: [String: Any] = [
            TargetConstants.EventDataKeys.TNT_ID: "4DBCC39D-4ACA-47D4-A7D2-A85C1C0CC382.32_0",
        ]
        let setTntIdEvent = Event(name: "TargetGetTnTIdentifier", type: "com.adobe.eventType.target", source: "com.adobe.eventSource.requestIdentity", data: data)
        guard let identityEventListener: EventListener = mockRuntime.listeners["com.adobe.eventType.target-com.adobe.eventSource.requestIdentity"] else {
            XCTFail()
            return
        }
        identityEventListener(setTntIdEvent)
        XCTAssertEqual(target.targetState.tntId, "4DBCC39D-4ACA-47D4-A7D2-A85C1C0CC382.32_0")
        XCTAssertEqual(target.targetState.edgeHost, "mboxedge32.tt.omtrdc.net")
        
        let prefetchEvent2 = Event(name: "TargetPrefetchRequest", type: "com.adobe.eventType.target", source: "com.adobe.eventSource.requestContent", data: data)
        prefetchEventListener(prefetchEvent2)
    }

}
   
