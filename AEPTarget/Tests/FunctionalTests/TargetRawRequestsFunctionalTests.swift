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

@testable import AEPCore
@testable import AEPServices
@testable import AEPTarget
import SwiftyJSON
import XCTest

class TargetRawRequestsFunctionalTests: TargetFunctionalTestsBase {
    func testExecuteRawRequest_execute() {
        // mocked network response
        let responseString = """
            {
              "status": 200,
              "id": {
                "tntId": "DE03D4AD-1FFE-421F-B2F2-303BF26822C1.35_0",
                "marketingCloudVisitorId": "38209274908399841237725561727471528301"
              },
              "requestId": "01d4a408-6978-48f7-95c6-03f04160b257",
              "client": "acopprod3",
              "edgeHost": "mboxedge35.tt.omtrdc.net",
              "execute": {
                "mboxes": [
                  {
                    "index": 0,
                    "name": "t_test_01",
                    "options": [
                      {
                        "content": {
                          "key1": "value1"
                        },
                        "type": "json"
                      }
                    ],
                    "analytics" : {
                        "payload" : {"pe" : "tnt", "tnta" : "33333:1:0|12121|1,38711:1:0|1|1"}
                    }
                  },
                  {
                    "index": 1,
                    "name": "t_test_02",
                    "options": [
                      {
                        "content": {
                          "key2": "value2"
                        },
                        "type": "json"
                      }
                    ]
                  }
                ]
              }
            }
        """

        let data: [String: Any] = [
            "execute": [
                "mboxes": [
                    [
                        "index": 0,
                        "name": "t_test_01",
                        "parameters": [
                            "mbox-parameter-key1": "mbox-parameter-value1"
                        ],
                        "profileParameters": [
                            "subscription": "premium"
                        ],
                        "order": [
                            "id": "id1",
                            "total": 100.34,
                            "purchasedProductIds":[
                                "pId1"
                            ]
                        ],
                        "product": [
                            "id": "pId1",
                            "categoryId": "cId1"
                        ]
                    ],
                    [
                        "index": 1,
                        "name": "t_test_02",
                        "parameters": [
                            "mbox-parameter-key2": "mbox-parameter-value2"
                        ],
                        "profileParameters": [
                            "subscription": "basic"
                        ]
                    ]
                ]
            ],
            "israwevent": true
        ]
        let executeRawRequestEvent = Event(name: "TargetRawRequest", type: "com.adobe.eventType.target", source: "com.adobe.eventSource.requestContent", data: data)

        // creates a configuration shared state
        mockRuntime.simulateSharedState(extensionName: "com.adobe.module.configuration", event: executeRawRequestEvent, data: (value: mockConfigSharedState, status: .set))

        // creates a lifecycle shared state
        mockRuntime.simulateSharedState(extensionName: "com.adobe.module.lifecycle", event: executeRawRequestEvent, data: (value: mockLifecycleData, status: .set))

        // creates an identity shared state
        mockRuntime.simulateSharedState(extensionName: "com.adobe.module.identity", event: executeRawRequestEvent, data: (value: mockIdentityData, status: .set))

        // registers the event listeners for Target extension
        target.onRegistered()

        let targetRequestExpectation = XCTestExpectation(description: "Target raw request expectation")
        
        // override network service
        let mockNetworkService = TestableNetworkService()
        ServiceProvider.shared.networkService = mockNetworkService
        mockNetworkService.mock { request in
            // verifies network request
            XCTAssertNotNil(request)
            guard let payloadDictionary = self.payloadAsDictionary(request.connectPayload) else {
                XCTFail()
                return nil
            }
            XCTAssertTrue(request.url.absoluteString.contains("https://acopprod3.tt.omtrdc.net/rest/v1/delivery/?client=acopprod3&sessionId="))
            XCTAssertTrue(Set(payloadDictionary.keys) == Set([
                "id",
                "experienceCloud",
                "context",
                "property",
                "execute",
                "environmentId",
            ]))

            // verifies payloadDictionary["id"]
            guard let idDictionary = payloadDictionary["id"] as? [String: Any] else {
                XCTFail()
                return nil
            }
            XCTAssertEqual("38209274908399841237725561727471528301", idDictionary["marketingCloudVisitorId"] as? String)
            guard let vids = idDictionary["customerIds"] as? [[String: Any]] else {
                XCTFail()
                return nil
            }
            XCTAssertEqual(1, vids.count)
            XCTAssertEqual("unknown", vids[0]["authenticatedState"] as? String)
            XCTAssertEqual("vid_id_1", vids[0]["id"] as? String)
            XCTAssertEqual("vid_type_1", vids[0]["integrationCode"] as? String)

            // verifies payloadDictionary["context"]
            guard let context = payloadDictionary["context"] as? [String: Any] else {
                XCTFail()
                return nil
            }
            XCTAssertTrue(Set(context.keys) == Set([
                "userAgent",
                "mobilePlatform",
                "screen",
                "channel",
                "application",
                "timeOffsetInMinutes",
            ]))

            // verifies payloadDictionary["property"]
            guard let propertyDictionary = payloadDictionary["property"] as? [String: Any] else {
                XCTFail()
                return nil
            }
            XCTAssertEqual("67444eb4-3681-40b4-831d-e082f5ccddcd", propertyDictionary["token"] as? String)
            
            // verifies payloadDictionary["execute"]
            guard let executeDictionary = payloadDictionary["execute"] as? [String: Any] else {
                XCTFail()
                return nil
            }

            XCTAssertTrue(Set(executeDictionary.keys) == Set([
                "mboxes",
            ]))
            guard let mboxes = executeDictionary["mboxes"] as? [[String: Any]] else {
                XCTFail()
                return nil
            }
            XCTAssertEqual(2, mboxes.count)
            let executeJson = JSON(parseJSON: self.prettify(executeDictionary))
            XCTAssertEqual(executeJson["mboxes"][0]["index"].intValue, 0)
            XCTAssertEqual(executeJson["mboxes"][0]["name"].stringValue, "t_test_01")
            XCTAssertEqual(1, executeJson["mboxes"][0]["profileParameters"].count)
            XCTAssertEqual(executeJson["mboxes"][0]["profileParameters"]["subscription"].stringValue, "premium")
            XCTAssertEqual(1, executeJson["mboxes"][0]["parameters"].count)
            XCTAssertEqual(executeJson["mboxes"][0]["parameters"]["mbox-parameter-key1"].stringValue, "mbox-parameter-value1")
            XCTAssertEqual(3, executeJson["mboxes"][0]["order"].count)
            XCTAssertEqual(executeJson["mboxes"][0]["order"]["id"].stringValue, "id1")
            XCTAssertEqual(executeJson["mboxes"][0]["order"]["total"].doubleValue, 100.34)
            XCTAssertEqual(executeJson["mboxes"][0]["order"]["purchasedProductIds"], ["pId1"])
            XCTAssertEqual(2, executeJson["mboxes"][0]["product"].count)
            XCTAssertEqual(executeJson["mboxes"][0]["product"]["id"].stringValue, "pId1")
            XCTAssertEqual(executeJson["mboxes"][0]["product"]["categoryId"].stringValue, "cId1")
            
            XCTAssertEqual(executeJson["mboxes"][1]["index"].intValue, 1)
            XCTAssertEqual(executeJson["mboxes"][1]["name"].stringValue, "t_test_02")
            XCTAssertEqual(1, executeJson["mboxes"][1]["profileParameters"].count)
            XCTAssertEqual(executeJson["mboxes"][1]["profileParameters"]["subscription"].stringValue, "basic")
            XCTAssertEqual(1, executeJson["mboxes"][1]["parameters"].count)
            XCTAssertEqual(executeJson["mboxes"][1]["parameters"]["mbox-parameter-key2"].stringValue, "mbox-parameter-value2")
            
            targetRequestExpectation.fulfill()
            let validResponse = HTTPURLResponse(url: URL(string: "https://acopprod3.tt.omtrdc.net/rest/v1/delivery")!, statusCode: 200, httpVersion: nil, headerFields: nil)
            return (data: responseString.data(using: .utf8), response: validResponse, error: nil)
        }
        guard let eventListener: EventListener = mockRuntime.listeners["com.adobe.eventType.target-com.adobe.eventSource.requestContent"] else {
            XCTFail()
            return
        }
        XCTAssertTrue(target.readyForEvent(executeRawRequestEvent))

        // handles the execute raw request event
        eventListener(executeRawRequestEvent)
        wait(for: [targetRequestExpectation], timeout: 1)

        // verifies the content of network response was stored correctly
        XCTAssertEqual("DE03D4AD-1FFE-421F-B2F2-303BF26822C1.35_0", target.targetState.tntId)
        XCTAssertEqual("mboxedge35.tt.omtrdc.net", target.targetState.edgeHost)
        XCTAssertEqual(0, target.targetState.loadedMboxJsonDicts.count)

        // verifies the Target's shared state
        XCTAssertEqual(1, mockRuntime.createdSharedStates.count)
        XCTAssertEqual("DE03D4AD-1FFE-421F-B2F2-303BF26822C1.35_0", mockRuntime.createdSharedStates[0]?["tntid"] as? String)
        
        // verifies the dispatched event
        XCTAssertEqual(1, mockRuntime.dispatchedEvents.count)
        XCTAssertEqual("TargetRawResponse", mockRuntime.dispatchedEvents[0].name)
        XCTAssertEqual("com.adobe.eventType.target", mockRuntime.dispatchedEvents[0].type)
        XCTAssertEqual("com.adobe.eventSource.responseContent", mockRuntime.dispatchedEvents[0].source)
        XCTAssertNotNil(mockRuntime.dispatchedEvents[0].data?["responsedata"])
    }
    
    func testExecuteRawRequest_prefetch() {
        // mocked network response
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
                    "name": "t_test_01",
                    "options": [
                      {
                        "content": {
                          "key1": "value1"
                        },
                        "type": "json",
                        "eventToken": "uR0kIAPO+tZtIPW92S0NnWqipfsIHvVzTQxHolz2IpSCnQ9Y9OaLL2gsdrWQTvE54PwSz67rmXWmSnkXpSSS2Q=="
                      }
                    ],
                    "state": "SGFZpwAqaqFTayhAT2xsgzG3+2fw4m+O9FK8c0QoOHff8UsFN93WCBONELFJ28p04DGGaJY+cq6eLyMJgllj/IUmSZgVHoQb6nD7ZRlTTPzyOc/CdEzn6tjn1cPyTVt8"
                  },
                  {
                    "index": 1,
                    "name": "t_test_02",
                    "options": [
                      {
                        "content": {
                          "key2": "value2"
                        },
                        "type": "json",
                        "eventToken": "v6n3Lx+N4lhgIQKde5Zv2pNWHtnQtQrJfmRrQugEa2qCnQ9Y9OaLL2gsdrWQTvE54PwSz67rmXWmSnkXpSSS2Q=="
                      }
                    ],
                    "state": "SGFZpwAqaqFTayhAT2xsgzG3+2fw4m+O9FK8c0QoOHfX3MH/pY4Hm2ah2Kshfl0aTQIkGbrN+vG4IpgrdkGV8IUmSZgVHoQb6nD7ZRlTTPzyOc/CdEzn6tjn1cPyTVt8"
                  }
                ]
              }
            }
        """

        let data: [String: Any] = [
            "prefetch": [
                "mboxes": [
                    [
                        "index": 0,
                        "name": "t_test_01",
                        "parameters": [
                            "mbox-parameter-key1": "mbox-parameter-value1"
                        ],
                        "profileParameters": [
                            "subscription": "premium"
                        ],
                        "order": [
                            "id": "id1",
                            "total": 100.34,
                            "purchasedProductIds":[
                                "pId1"
                            ]
                        ],
                        "product": [
                            "id": "pId1",
                            "categoryId": "cId1"
                        ]
                    ],
                    [
                        "index": 1,
                        "name": "t_test_02",
                        "parameters": [
                            "mbox-parameter-key2": "mbox-parameter-value2"
                        ],
                        "profileParameters": [
                            "subscription": "basic"
                        ]
                    ]
                ]
            ],
            "israwevent": true
        ]
        
        let executeRawRequestEvent = Event(name: "TargetRawRequest", type: "com.adobe.eventType.target", source: "com.adobe.eventSource.requestContent", data: data)

        // creates a configuration shared state
        mockRuntime.simulateSharedState(extensionName: "com.adobe.module.configuration", event: executeRawRequestEvent, data: (value: mockConfigSharedState, status: .set))

        // creates a lifecycle shared state
        mockRuntime.simulateSharedState(extensionName: "com.adobe.module.lifecycle", event: executeRawRequestEvent, data: (value: mockLifecycleData, status: .set))

        // creates an identity shared state
        mockRuntime.simulateSharedState(extensionName: "com.adobe.module.identity", event: executeRawRequestEvent, data: (value: mockIdentityData, status: .set))

        // registers the event listeners for Target extension
        target.onRegistered()

        let targetRequestExpectation = XCTestExpectation(description: "Target raw request expectation")
        
        // override network service
        let mockNetworkService = TestableNetworkService()
        ServiceProvider.shared.networkService = mockNetworkService
        mockNetworkService.mock { request in
            // verifies network request
            XCTAssertNotNil(request)
            guard let payloadDictionary = self.payloadAsDictionary(request.connectPayload) else {
                XCTFail()
                return nil
            }
            XCTAssertTrue(request.url.absoluteString.contains("https://acopprod3.tt.omtrdc.net/rest/v1/delivery/?client=acopprod3&sessionId="))
            XCTAssertTrue(Set(payloadDictionary.keys) == Set([
                "id",
                "experienceCloud",
                "context",
                "property",
                "prefetch",
                "environmentId",
            ]))

            // verifies payloadDictionary["id"]
            guard let idDictionary = payloadDictionary["id"] as? [String: Any] else {
                XCTFail()
                return nil
            }
            XCTAssertEqual("38209274908399841237725561727471528301", idDictionary["marketingCloudVisitorId"] as? String)
            guard let vids = idDictionary["customerIds"] as? [[String: Any]] else {
                XCTFail()
                return nil
            }
            XCTAssertEqual(1, vids.count)
            XCTAssertEqual("unknown", vids[0]["authenticatedState"] as? String)
            XCTAssertEqual("vid_id_1", vids[0]["id"] as? String)
            XCTAssertEqual("vid_type_1", vids[0]["integrationCode"] as? String)

            // verifies payloadDictionary["context"]
            guard let context = payloadDictionary["context"] as? [String: Any] else {
                XCTFail()
                return nil
            }
            XCTAssertTrue(Set(context.keys) == Set([
                "userAgent",
                "mobilePlatform",
                "screen",
                "channel",
                "application",
                "timeOffsetInMinutes",
            ]))

            // verifies payloadDictionary["property"]
            guard let propertyDictionary = payloadDictionary["property"] as? [String: Any] else {
                XCTFail()
                return nil
            }
            XCTAssertEqual("67444eb4-3681-40b4-831d-e082f5ccddcd", propertyDictionary["token"] as? String)
            
            // verifies payloadDictionary["prefetch"]
            guard let prefetchDictionary = payloadDictionary["prefetch"] as? [String: Any] else {
                XCTFail()
                return nil
            }

            XCTAssertTrue(Set(prefetchDictionary.keys) == Set([
                "mboxes",
            ]))
            
            guard let mboxes = prefetchDictionary["mboxes"] as? [[String: Any]] else {
                XCTFail()
                return nil
            }

            XCTAssertEqual(2, mboxes.count)
            let prefetchJson = JSON(parseJSON: self.prettify(prefetchDictionary))
            XCTAssertEqual(prefetchJson["mboxes"][0]["index"].intValue, 0)
            XCTAssertEqual(prefetchJson["mboxes"][0]["name"].stringValue, "t_test_01")
            XCTAssertEqual(1, prefetchJson["mboxes"][0]["profileParameters"].count)
            XCTAssertEqual(prefetchJson["mboxes"][0]["profileParameters"]["subscription"].stringValue, "premium")
            XCTAssertEqual(1, prefetchJson["mboxes"][0]["parameters"].count)
            XCTAssertEqual(prefetchJson["mboxes"][0]["parameters"]["mbox-parameter-key1"].stringValue, "mbox-parameter-value1")
            XCTAssertEqual(3, prefetchJson["mboxes"][0]["order"].count)
            XCTAssertEqual(prefetchJson["mboxes"][0]["order"]["id"].stringValue, "id1")
            XCTAssertEqual(prefetchJson["mboxes"][0]["order"]["total"].doubleValue, 100.34)
            XCTAssertEqual(prefetchJson["mboxes"][0]["order"]["purchasedProductIds"], ["pId1"])
            XCTAssertEqual(2, prefetchJson["mboxes"][0]["product"].count)
            XCTAssertEqual(prefetchJson["mboxes"][0]["product"]["id"].stringValue, "pId1")
            XCTAssertEqual(prefetchJson["mboxes"][0]["product"]["categoryId"].stringValue, "cId1")
            
            XCTAssertEqual(prefetchJson["mboxes"][1]["index"].intValue, 1)
            XCTAssertEqual(prefetchJson["mboxes"][1]["name"].stringValue, "t_test_02")
            XCTAssertEqual(1, prefetchJson["mboxes"][1]["profileParameters"].count)
            XCTAssertEqual(prefetchJson["mboxes"][1]["profileParameters"]["subscription"].stringValue, "basic")
            XCTAssertEqual(1, prefetchJson["mboxes"][1]["parameters"].count)
            XCTAssertEqual(prefetchJson["mboxes"][1]["parameters"]["mbox-parameter-key2"].stringValue, "mbox-parameter-value2")
            
            targetRequestExpectation.fulfill()
            let validResponse = HTTPURLResponse(url: URL(string: "https://acopprod3.tt.omtrdc.net/rest/v1/delivery")!, statusCode: 200, httpVersion: nil, headerFields: nil)
            return (data: responseString.data(using: .utf8), response: validResponse, error: nil)
        }
        guard let eventListener: EventListener = mockRuntime.listeners["com.adobe.eventType.target-com.adobe.eventSource.requestContent"] else {
            XCTFail()
            return
        }
        XCTAssertTrue(target.readyForEvent(executeRawRequestEvent))
        
        // handles the execute raw request event
        eventListener(executeRawRequestEvent)
        wait(for: [targetRequestExpectation], timeout: 1)
        
        // verifies the content of network response was stored correctly
        XCTAssertEqual("DE03D4AD-1FFE-421F-B2F2-303BF26822C1.35_0", target.targetState.tntId)
        XCTAssertEqual("mboxedge35.tt.omtrdc.net", target.targetState.edgeHost)
        XCTAssertEqual(0, target.targetState.prefetchedMboxJsonDicts.count)
        
        // verifies the Target's shared state
        XCTAssertEqual(1, mockRuntime.createdSharedStates.count)
        XCTAssertEqual("DE03D4AD-1FFE-421F-B2F2-303BF26822C1.35_0", mockRuntime.createdSharedStates[0]?["tntid"] as? String)

        // verifies the dispatched event
        XCTAssertEqual(1, mockRuntime.dispatchedEvents.count)
        XCTAssertEqual("TargetRawResponse", mockRuntime.dispatchedEvents[0].name)
        XCTAssertEqual("com.adobe.eventType.target", mockRuntime.dispatchedEvents[0].type)
        XCTAssertEqual("com.adobe.eventSource.responseContent", mockRuntime.dispatchedEvents[0].source)
        XCTAssertNotNil(mockRuntime.dispatchedEvents[0].data?["responsedata"])
    }

    func testExecuteRawRequest_prefetchInPreviewMode() {
        // mocked network response
        let responseString = """
            {
              "status": 200,
              "id": {
                "tntId": "DE03D4AD-1FFE-421F-B2F2-303BF26822C1.35_0",
                "marketingCloudVisitorId": "38209274908399841237725561727471528301"
              },
              "requestId": "01d4a408-6978-48f7-95c6-03f04160b257",
              "client": "acopprod3",
              "edgeHost": "mboxedge35.tt.omtrdc.net",
              "prefetch": {
                "mboxes": [
                  {
                    "index": 0,
                    "name": "t_test_01",
                    "options": [
                      {
                        "content": "someContent",
                        "type": "html",
                        "eventToken": "v6n3Lx+N4lhgIQKde5Zv2pNWHtnQtQrJfmRrQugEa2qCnQ9Y9OaLL2gsdrWQTvE54PwSz67rmXWmSnkXpSSS2Q=="
                      }
                    ]
                  }
                ]
              }
            }
        """
        
        let data: [String: Any] = [
            "prefetch": [
                "mboxes": [
                    [
                        "index": 0,
                        "name": "t_test_01",
                        "parameters": [
                            "mbox-parameter-key1": "mbox-parameter-value1"
                        ]
                    ]
                ]
            ],
            "israwevent": true
        ]
        
        let executeRawRequestEvent = Event(name: "TargetRawRequest", type: "com.adobe.eventType.target", source: "com.adobe.eventSource.requestContent", data: data)

        // creates a configuration shared state
        mockRuntime.simulateSharedState(extensionName: "com.adobe.module.configuration", event: executeRawRequestEvent, data: (value: mockConfigSharedState, status: .set))
        
        // creates an identity shared state
        mockRuntime.simulateSharedState(extensionName: "com.adobe.module.identity", event: executeRawRequestEvent, data: (value: mockIdentityData, status: .set))
        
        // registers the event listeners for Target extension
        target.onRegistered()
        
        let targetRequestExpectation = XCTestExpectation(description: "Target raw request expectation")
        
        let mockNetworkService = TestableNetworkService()
        ServiceProvider.shared.networkService = mockNetworkService
        mockNetworkService.mock { request in
            // verifies network request
            if request.url.absoluteString.contains("https://acopprod3.tt.omtrdc.net/rest/v1/delivery/?client=acopprod3&sessionId=") {
                targetRequestExpectation.fulfill()
                let validResponse = HTTPURLResponse(url: URL(string: "https://acopprod3.tt.omtrdc.net/rest/v1/delivery")!, statusCode: 200, httpVersion: nil, headerFields: nil)
                return (data: responseString.data(using: .utf8), response: validResponse, error: nil)
            }
            return (data: nil, response: nil, error: nil)
        }
        
        let mockedPreviewManager = MockTargetPreviewManager()
        mockedPreviewManager.previewParameters = "not empty"
        target.previewManager = mockedPreviewManager

        guard let eventListener: EventListener = mockRuntime.listeners["com.adobe.eventType.target-com.adobe.eventSource.requestContent"] else {
            XCTFail()
            return
        }
        XCTAssertTrue(target.readyForEvent(executeRawRequestEvent))
        
        // handles the execute raw request event
        eventListener(executeRawRequestEvent)
        wait(for: [targetRequestExpectation], timeout: 1)
        
        // verifies the dispatched event
        XCTAssertEqual(1, mockRuntime.dispatchedEvents.count)
        XCTAssertEqual("TargetRawResponse", mockRuntime.dispatchedEvents[0].name)
        XCTAssertEqual("com.adobe.eventType.target", mockRuntime.dispatchedEvents[0].type)
        XCTAssertEqual("com.adobe.eventSource.responseContent", mockRuntime.dispatchedEvents[0].source)
        XCTAssertNil(mockRuntime.dispatchedEvents[0].data?["responseerror"])
        XCTAssertNotNil(mockRuntime.dispatchedEvents[0].data?["responsedata"])
    }
    
    func testExecuteRawRequest_withPropertyTokenInEventData() {
        mockConfigSharedState = ["target.clientCode": "acopprod3", "global.privacy": "optedin"]

        // mocked network response
        let responseString = """
            {
              "status": 200,
              "id": {
                "tntId": "DE03D4AD-1FFE-421F-B2F2-303BF26822C1.35_0",
                "marketingCloudVisitorId": "38209274908399841237725561727471528301"
              },
              "requestId": "01d4a408-6978-48f7-95c6-03f04160b257",
              "client": "acopprod3",
              "edgeHost": "mboxedge35.tt.omtrdc.net",
              "execute": {
                "mboxes": [
                  {
                    "index": 0,
                    "name": "t_test_01",
                    "options": [
                      {
                        "content": {
                          "key1": "value1"
                        },
                        "type": "json"
                      }
                    ]
                  }
                ]
              }
            }
        """

        let data: [String: Any] = [
            "execute": [
                "mboxes": [
                    [
                        "index": 0,
                        "name": "t_test_01",
                        "parameters": [
                            "mbox-parameter-key1": "mbox-parameter-value1"
                        ]
                    ]
                ]
            ],
            "israwevent": true,
            "property": [
                "token": "a2ec61d0-fab8-42f9-bf0f-699d169b48d8"
            ]
        ]
        
        let executeRawRequestEvent = Event(name: "TargetRawRequest", type: "com.adobe.eventType.target", source: "com.adobe.eventSource.requestContent", data: data)

        // creates a configuration shared state
        mockRuntime.simulateSharedState(extensionName: "com.adobe.module.configuration", event: executeRawRequestEvent, data: (value: mockConfigSharedState, status: .set))

        // creates an identity shared state
        mockRuntime.simulateSharedState(extensionName: "com.adobe.module.identity", event: executeRawRequestEvent, data: (value: mockIdentityData, status: .set))

        // registers the event listeners for Target extension
        target.onRegistered()

        let targetRequestExpectation = XCTestExpectation(description: "Target raw request expectation")
        
        // override network service
        let mockNetworkService = TestableNetworkService()
        ServiceProvider.shared.networkService = mockNetworkService
        mockNetworkService.mock { request in
            // verifies network request
            XCTAssertNotNil(request)
            guard let payloadDictionary = self.payloadAsDictionary(request.connectPayload) else {
                XCTFail()
                return nil
            }
            XCTAssertTrue(request.url.absoluteString.contains("https://acopprod3.tt.omtrdc.net/rest/v1/delivery/?client=acopprod3&sessionId="))
            XCTAssertTrue(Set(payloadDictionary.keys) == Set([
                "id",
                "experienceCloud",
                "context",
                "property",
                "execute",
                "environmentId",
            ]))

            // verifies payloadDictionary["id"]
            guard let idDictionary = payloadDictionary["id"] as? [String: Any] else {
                XCTFail()
                return nil
            }
            XCTAssertEqual("38209274908399841237725561727471528301", idDictionary["marketingCloudVisitorId"] as? String)
            guard let vids = idDictionary["customerIds"] as? [[String: Any]] else {
                XCTFail()
                return nil
            }
            XCTAssertEqual(1, vids.count)
            XCTAssertEqual("unknown", vids[0]["authenticatedState"] as? String)
            XCTAssertEqual("vid_id_1", vids[0]["id"] as? String)
            XCTAssertEqual("vid_type_1", vids[0]["integrationCode"] as? String)

            // verifies payloadDictionary["context"]
            guard let context = payloadDictionary["context"] as? [String: Any] else {
                XCTFail()
                return nil
            }
            XCTAssertTrue(Set(context.keys) == Set([
                "userAgent",
                "mobilePlatform",
                "screen",
                "channel",
                "application",
                "timeOffsetInMinutes",
            ]))

            // verifies payloadDictionary["property"]
            guard let propertyDictionary = payloadDictionary["property"] as? [String: Any] else {
                XCTFail()
                return nil
            }
            XCTAssertEqual("a2ec61d0-fab8-42f9-bf0f-699d169b48d8", propertyDictionary["token"] as? String)
            
            // verifies payloadDictionary["execute"]
            guard let executeDictionary = payloadDictionary["execute"] as? [String: Any] else {
                XCTFail()
                return nil
            }

            XCTAssertTrue(Set(executeDictionary.keys) == Set([
                "mboxes",
            ]))
            guard let mboxes = executeDictionary["mboxes"] as? [[String: Any]] else {
                XCTFail()
                return nil
            }
            XCTAssertEqual(1, mboxes.count)
            let executeJson = JSON(parseJSON: self.prettify(executeDictionary))
            XCTAssertEqual(executeJson["mboxes"][0]["index"].intValue, 0)
            XCTAssertEqual(executeJson["mboxes"][0]["name"].stringValue, "t_test_01")
            XCTAssertEqual(1, executeJson["mboxes"][0]["parameters"].count)
            XCTAssertEqual(executeJson["mboxes"][0]["parameters"]["mbox-parameter-key1"].stringValue, "mbox-parameter-value1")
            
            targetRequestExpectation.fulfill()
            let validResponse = HTTPURLResponse(url: URL(string: "https://acopprod3.tt.omtrdc.net/rest/v1/delivery")!, statusCode: 200, httpVersion: nil, headerFields: nil)
            return (data: responseString.data(using: .utf8), response: validResponse, error: nil)
        }
        guard let eventListener: EventListener = mockRuntime.listeners["com.adobe.eventType.target-com.adobe.eventSource.requestContent"] else {
            XCTFail()
            return
        }
        XCTAssertTrue(target.readyForEvent(executeRawRequestEvent))
        
        // handles the execute raw request event
        eventListener(executeRawRequestEvent)
        wait(for: [targetRequestExpectation], timeout: 1)

        // verifies the content of network response was stored correctly
        XCTAssertEqual("DE03D4AD-1FFE-421F-B2F2-303BF26822C1.35_0", target.targetState.tntId)
        XCTAssertEqual("mboxedge35.tt.omtrdc.net", target.targetState.edgeHost)
        XCTAssertEqual(0, target.targetState.loadedMboxJsonDicts.count)

        // verifies the Target's shared state
        XCTAssertEqual(1, mockRuntime.createdSharedStates.count)
        XCTAssertEqual("DE03D4AD-1FFE-421F-B2F2-303BF26822C1.35_0", mockRuntime.createdSharedStates[0]?["tntid"] as? String)
    }
    
    func testExecuteRawRequest_withPropertyTokenInConfigurationAndEventData() {
        // mocked network response
        let responseString = """
            {
              "status": 200,
              "id": {
                "tntId": "DE03D4AD-1FFE-421F-B2F2-303BF26822C1.35_0",
                "marketingCloudVisitorId": "38209274908399841237725561727471528301"
              },
              "requestId": "01d4a408-6978-48f7-95c6-03f04160b257",
              "client": "acopprod3",
              "edgeHost": "mboxedge35.tt.omtrdc.net",
              "execute": {
                "mboxes": [
                  {
                    "index": 0,
                    "name": "t_test_01",
                    "options": [
                      {
                        "content": {
                          "key1": "value1"
                        },
                        "type": "json"
                      }
                    ]
                  }
                ]
              }
            }
        """

        let data: [String: Any] = [
            "execute": [
                "mboxes": [
                    [
                        "index": 0,
                        "name": "t_test_01",
                        "parameters": [
                            "mbox-parameter-key1": "mbox-parameter-value1"
                        ]
                    ]
                ]
            ],
            "israwevent": true,
            "property": [
                "token": "a2ec61d0-fab8-42f9-bf0f-699d169b48d8"
            ]
        ]
        
        let executeRawRequestEvent = Event(name: "TargetRawRequest", type: "com.adobe.eventType.target", source: "com.adobe.eventSource.requestContent", data: data)

        // creates a configuration shared state
        mockRuntime.simulateSharedState(extensionName: "com.adobe.module.configuration", event: executeRawRequestEvent, data: (value: mockConfigSharedState, status: .set))

        // creates an identity shared state
        mockRuntime.simulateSharedState(extensionName: "com.adobe.module.identity", event: executeRawRequestEvent, data: (value: mockIdentityData, status: .set))

        // registers the event listeners for Target extension
        target.onRegistered()

        let targetRequestExpectation = XCTestExpectation(description: "Target raw request expectation")
        
        // override network service
        let mockNetworkService = TestableNetworkService()
        ServiceProvider.shared.networkService = mockNetworkService
        mockNetworkService.mock { request in
            // verifies network request
            XCTAssertNotNil(request)
            guard let payloadDictionary = self.payloadAsDictionary(request.connectPayload) else {
                XCTFail()
                return nil
            }
            XCTAssertTrue(request.url.absoluteString.contains("https://acopprod3.tt.omtrdc.net/rest/v1/delivery/?client=acopprod3&sessionId="))
            XCTAssertTrue(Set(payloadDictionary.keys) == Set([
                "id",
                "experienceCloud",
                "context",
                "property",
                "execute",
                "environmentId",
            ]))

            // verifies payloadDictionary["id"]
            guard let idDictionary = payloadDictionary["id"] as? [String: Any] else {
                XCTFail()
                return nil
            }
            XCTAssertEqual("38209274908399841237725561727471528301", idDictionary["marketingCloudVisitorId"] as? String)
            guard let vids = idDictionary["customerIds"] as? [[String: Any]] else {
                XCTFail()
                return nil
            }
            XCTAssertEqual(1, vids.count)
            XCTAssertEqual("unknown", vids[0]["authenticatedState"] as? String)
            XCTAssertEqual("vid_id_1", vids[0]["id"] as? String)
            XCTAssertEqual("vid_type_1", vids[0]["integrationCode"] as? String)

            // verifies payloadDictionary["context"]
            guard let context = payloadDictionary["context"] as? [String: Any] else {
                XCTFail()
                return nil
            }
            XCTAssertTrue(Set(context.keys) == Set([
                "userAgent",
                "mobilePlatform",
                "screen",
                "channel",
                "application",
                "timeOffsetInMinutes",
            ]))

            // verifies payloadDictionary["property"]
            guard let propertyDictionary = payloadDictionary["property"] as? [String: Any] else {
                XCTFail()
                return nil
            }
            XCTAssertEqual("67444eb4-3681-40b4-831d-e082f5ccddcd", propertyDictionary["token"] as? String)
            
            // verifies payloadDictionary["execute"]
            guard let executeDictionary = payloadDictionary["execute"] as? [String: Any] else {
                XCTFail()
                return nil
            }

            XCTAssertTrue(Set(executeDictionary.keys) == Set([
                "mboxes",
            ]))
            guard let mboxes = executeDictionary["mboxes"] as? [[String: Any]] else {
                XCTFail()
                return nil
            }
            XCTAssertEqual(1, mboxes.count)
            let executeJson = JSON(parseJSON: self.prettify(executeDictionary))
            XCTAssertEqual(executeJson["mboxes"][0]["index"].intValue, 0)
            XCTAssertEqual(executeJson["mboxes"][0]["name"].stringValue, "t_test_01")
            XCTAssertEqual(1, executeJson["mboxes"][0]["parameters"].count)
            XCTAssertEqual(executeJson["mboxes"][0]["parameters"]["mbox-parameter-key1"].stringValue, "mbox-parameter-value1")
            
            targetRequestExpectation.fulfill()
            let validResponse = HTTPURLResponse(url: URL(string: "https://acopprod3.tt.omtrdc.net/rest/v1/delivery")!, statusCode: 200, httpVersion: nil, headerFields: nil)
            return (data: responseString.data(using: .utf8), response: validResponse, error: nil)
        }
        guard let eventListener: EventListener = mockRuntime.listeners["com.adobe.eventType.target-com.adobe.eventSource.requestContent"] else {
            XCTFail()
            return
        }
        XCTAssertTrue(target.readyForEvent(executeRawRequestEvent))
        
        // handles the load request event
        eventListener(executeRawRequestEvent)
        wait(for: [targetRequestExpectation], timeout: 1)

        // verifies the content of network response was stored correctly
        XCTAssertEqual("DE03D4AD-1FFE-421F-B2F2-303BF26822C1.35_0", target.targetState.tntId)
        XCTAssertEqual("mboxedge35.tt.omtrdc.net", target.targetState.edgeHost)
        XCTAssertEqual(0, target.targetState.loadedMboxJsonDicts.count)

        // verifies the Target's shared state
        XCTAssertEqual(1, mockRuntime.createdSharedStates.count)
        XCTAssertEqual("DE03D4AD-1FFE-421F-B2F2-303BF26822C1.35_0", mockRuntime.createdSharedStates[0]?["tntid"] as? String)
    }

    func testExecuteRawRequest_withEnvironmentIdInConfigurationAndEventData() {
        mockConfigSharedState = ["target.clientCode": "acopprod3", "global.privacy": "optedin", "target.environmentId": 4455, "target.propertyToken": "67444eb4-3681-40b4-831d-e082f5ccddcd"]

        // mocked network response
        let responseString = """
            {
              "status": 200,
              "id": {
                "tntId": "DE03D4AD-1FFE-421F-B2F2-303BF26822C1.35_0",
                "marketingCloudVisitorId": "38209274908399841237725561727471528301"
              },
              "requestId": "01d4a408-6978-48f7-95c6-03f04160b257",
              "client": "acopprod3",
              "edgeHost": "mboxedge35.tt.omtrdc.net",
              "execute": {
                "mboxes": [
                  {
                    "index": 0,
                    "name": "t_test_01",
                    "options": [
                      {
                        "content": {
                          "key1": "value1"
                        },
                        "type": "json"
                      }
                    ]
                  }
                ]
              }
            }
        """

        let data: [String: Any] = [
            "execute": [
                "mboxes": [
                    [
                        "index": 0,
                        "name": "t_test_01",
                        "parameters": [
                            "mbox-parameter-key1": "mbox-parameter-value1"
                        ]
                    ]
                ]
            ],
            "israwevent": true,
            "environmentId": 8899
        ]
        
        let executeRawRequestEvent = Event(name: "TargetRawRequest", type: "com.adobe.eventType.target", source: "com.adobe.eventSource.requestContent", data: data)

        // creates a configuration shared state
        mockRuntime.simulateSharedState(extensionName: "com.adobe.module.configuration", event: executeRawRequestEvent, data: (value: mockConfigSharedState, status: .set))

        // creates an identity shared state
        mockRuntime.simulateSharedState(extensionName: "com.adobe.module.identity", event: executeRawRequestEvent, data: (value: mockIdentityData, status: .set))

        // registers the event listeners for Target extension
        target.onRegistered()

        let targetRequestExpectation = XCTestExpectation(description: "Target raw request expectation")
        
        // override network service
        let mockNetworkService = TestableNetworkService()
        ServiceProvider.shared.networkService = mockNetworkService
        mockNetworkService.mock { request in
            // verifies network request
            XCTAssertNotNil(request)
            guard let payloadDictionary = self.payloadAsDictionary(request.connectPayload) else {
                XCTFail()
                return nil
            }
            XCTAssertTrue(request.url.absoluteString.contains("https://acopprod3.tt.omtrdc.net/rest/v1/delivery/?client=acopprod3&sessionId="))
            XCTAssertTrue(Set(payloadDictionary.keys) == Set([
                "id",
                "experienceCloud",
                "context",
                "property",
                "execute",
                "environmentId",
            ]))

            // verifies payloadDictionary["id"]
            guard let idDictionary = payloadDictionary["id"] as? [String: Any] else {
                XCTFail()
                return nil
            }
            XCTAssertEqual("38209274908399841237725561727471528301", idDictionary["marketingCloudVisitorId"] as? String)
            guard let vids = idDictionary["customerIds"] as? [[String: Any]] else {
                XCTFail()
                return nil
            }
            XCTAssertEqual(1, vids.count)
            XCTAssertEqual("unknown", vids[0]["authenticatedState"] as? String)
            XCTAssertEqual("vid_id_1", vids[0]["id"] as? String)
            XCTAssertEqual("vid_type_1", vids[0]["integrationCode"] as? String)

            // verifies payloadDictionary["context"]
            guard let context = payloadDictionary["context"] as? [String: Any] else {
                XCTFail()
                return nil
            }
            XCTAssertTrue(Set(context.keys) == Set([
                "userAgent",
                "mobilePlatform",
                "screen",
                "channel",
                "application",
                "timeOffsetInMinutes",
            ]))

            // verifies payloadDictionary["property"]
            guard let propertyDictionary = payloadDictionary["property"] as? [String: Any] else {
                XCTFail()
                return nil
            }
            XCTAssertEqual("67444eb4-3681-40b4-831d-e082f5ccddcd", propertyDictionary["token"] as? String)
            
            // verifies payloadDictionary["environmentId"]
            XCTAssertEqual(4455, payloadDictionary["environmentId"] as? Int64)
            
            // verifies payloadDictionary["execute"]
            guard let executeDictionary = payloadDictionary["execute"] as? [String: Any] else {
                XCTFail()
                return nil
            }

            XCTAssertTrue(Set(executeDictionary.keys) == Set([
                "mboxes",
            ]))
            guard let mboxes = executeDictionary["mboxes"] as? [[String: Any]] else {
                XCTFail()
                return nil
            }
            XCTAssertEqual(1, mboxes.count)
            let executeJson = JSON(parseJSON: self.prettify(executeDictionary))
            XCTAssertEqual(executeJson["mboxes"][0]["index"].intValue, 0)
            XCTAssertEqual(executeJson["mboxes"][0]["name"].stringValue, "t_test_01")
            XCTAssertEqual(1, executeJson["mboxes"][0]["parameters"].count)
            XCTAssertEqual(executeJson["mboxes"][0]["parameters"]["mbox-parameter-key1"].stringValue, "mbox-parameter-value1")
            
            targetRequestExpectation.fulfill()
            let validResponse = HTTPURLResponse(url: URL(string: "https://acopprod3.tt.omtrdc.net/rest/v1/delivery")!, statusCode: 200, httpVersion: nil, headerFields: nil)
            return (data: responseString.data(using: .utf8), response: validResponse, error: nil)
        }
        guard let eventListener: EventListener = mockRuntime.listeners["com.adobe.eventType.target-com.adobe.eventSource.requestContent"] else {
            XCTFail()
            return
        }
        XCTAssertTrue(target.readyForEvent(executeRawRequestEvent))
        
        // handles the execute raw request event
        eventListener(executeRawRequestEvent)
        wait(for: [targetRequestExpectation], timeout: 2)

        // verifies the content of network response was stored correctly
        XCTAssertEqual("DE03D4AD-1FFE-421F-B2F2-303BF26822C1.35_0", target.targetState.tntId)
        XCTAssertEqual("mboxedge35.tt.omtrdc.net", target.targetState.edgeHost)
        XCTAssertEqual(0, target.targetState.loadedMboxJsonDicts.count)

        // verifies the Target's shared state
        XCTAssertEqual(1, mockRuntime.createdSharedStates.count)
        XCTAssertEqual("DE03D4AD-1FFE-421F-B2F2-303BF26822C1.35_0", mockRuntime.createdSharedStates[0]?["tntid"] as? String)
    }
    
    func testExecuteRawRequest_withEnvironmentIdInEventData() {
        // mocked network response
        let responseString = """
            {
              "status": 200,
              "id": {
                "tntId": "DE03D4AD-1FFE-421F-B2F2-303BF26822C1.35_0",
                "marketingCloudVisitorId": "38209274908399841237725561727471528301"
              },
              "requestId": "01d4a408-6978-48f7-95c6-03f04160b257",
              "client": "acopprod3",
              "edgeHost": "mboxedge35.tt.omtrdc.net",
              "execute": {
                "mboxes": [
                  {
                    "index": 0,
                    "name": "t_test_01",
                    "options": [
                      {
                        "content": {
                          "key1": "value1"
                        },
                        "type": "json"
                      }
                    ]
                  }
                ]
              }
            }
        """

        let data: [String: Any] = [
            "execute": [
                "mboxes": [
                    [
                        "index": 0,
                        "name": "t_test_01",
                        "parameters": [
                            "mbox-parameter-key1": "mbox-parameter-value1"
                        ]
                    ]
                ]
            ],
            "israwevent": true,
            "environmentId": Int64(8899)
        ]
        
        let executeRawRequestEvent = Event(name: "TargetRawRequest", type: "com.adobe.eventType.target", source: "com.adobe.eventSource.requestContent", data: data)

        // creates a configuration shared state
        mockRuntime.simulateSharedState(extensionName: "com.adobe.module.configuration", event: executeRawRequestEvent, data: (value: mockConfigSharedState, status: .set))

        // creates an identity shared state
        mockRuntime.simulateSharedState(extensionName: "com.adobe.module.identity", event: executeRawRequestEvent, data: (value: mockIdentityData, status: .set))

        // registers the event listeners for Target extension
        target.onRegistered()

        let targetRequestExpectation = XCTestExpectation(description: "Target raw request expectation")
        
        // override network service
        let mockNetworkService = TestableNetworkService()
        ServiceProvider.shared.networkService = mockNetworkService
        mockNetworkService.mock { request in
            // verifies network request
            XCTAssertNotNil(request)
            guard let payloadDictionary = self.payloadAsDictionary(request.connectPayload) else {
                XCTFail()
                return nil
            }
            XCTAssertTrue(request.url.absoluteString.contains("https://acopprod3.tt.omtrdc.net/rest/v1/delivery/?client=acopprod3&sessionId="))
            XCTAssertTrue(Set(payloadDictionary.keys) == Set([
                "id",
                "experienceCloud",
                "context",
                "property",
                "execute",
                "environmentId",
            ]))

            // verifies payloadDictionary["id"]
            guard let idDictionary = payloadDictionary["id"] as? [String: Any] else {
                XCTFail()
                return nil
            }
            XCTAssertEqual("38209274908399841237725561727471528301", idDictionary["marketingCloudVisitorId"] as? String)
            guard let vids = idDictionary["customerIds"] as? [[String: Any]] else {
                XCTFail()
                return nil
            }
            XCTAssertEqual(1, vids.count)
            XCTAssertEqual("unknown", vids[0]["authenticatedState"] as? String)
            XCTAssertEqual("vid_id_1", vids[0]["id"] as? String)
            XCTAssertEqual("vid_type_1", vids[0]["integrationCode"] as? String)

            // verifies payloadDictionary["context"]
            guard let context = payloadDictionary["context"] as? [String: Any] else {
                XCTFail()
                return nil
            }
            XCTAssertTrue(Set(context.keys) == Set([
                "userAgent",
                "mobilePlatform",
                "screen",
                "channel",
                "application",
                "timeOffsetInMinutes",
            ]))

            // verifies payloadDictionary["property"]
            guard let propertyDictionary = payloadDictionary["property"] as? [String: Any] else {
                XCTFail()
                return nil
            }
            XCTAssertEqual("67444eb4-3681-40b4-831d-e082f5ccddcd", propertyDictionary["token"] as? String)
            
            // verifies payloadDictionary["environmentId"]
            XCTAssertEqual(8899, payloadDictionary["environmentId"] as? Int64)
            
            // verifies payloadDictionary["execute"]
            guard let executeDictionary = payloadDictionary["execute"] as? [String: Any] else {
                XCTFail()
                return nil
            }

            XCTAssertTrue(Set(executeDictionary.keys) == Set([
                "mboxes",
            ]))
            guard let mboxes = executeDictionary["mboxes"] as? [[String: Any]] else {
                XCTFail()
                return nil
            }
            XCTAssertEqual(1, mboxes.count)
            let executeJson = JSON(parseJSON: self.prettify(executeDictionary))
            XCTAssertEqual(executeJson["mboxes"][0]["index"].intValue, 0)
            XCTAssertEqual(executeJson["mboxes"][0]["name"].stringValue, "t_test_01")
            XCTAssertEqual(1, executeJson["mboxes"][0]["parameters"].count)
            XCTAssertEqual(executeJson["mboxes"][0]["parameters"]["mbox-parameter-key1"].stringValue, "mbox-parameter-value1")
            
            targetRequestExpectation.fulfill()
            let validResponse = HTTPURLResponse(url: URL(string: "https://acopprod3.tt.omtrdc.net/rest/v1/delivery")!, statusCode: 200, httpVersion: nil, headerFields: nil)
            return (data: responseString.data(using: .utf8), response: validResponse, error: nil)
        }
        guard let eventListener: EventListener = mockRuntime.listeners["com.adobe.eventType.target-com.adobe.eventSource.requestContent"] else {
            XCTFail()
            return
        }
        XCTAssertTrue(target.readyForEvent(executeRawRequestEvent))
        
        // handles the execute raw request event
        eventListener(executeRawRequestEvent)
        wait(for: [targetRequestExpectation], timeout: 2)

        // verifies the content of network response was stored correctly
        XCTAssertEqual("DE03D4AD-1FFE-421F-B2F2-303BF26822C1.35_0", target.targetState.tntId)
        XCTAssertEqual("mboxedge35.tt.omtrdc.net", target.targetState.edgeHost)
        XCTAssertEqual(0, target.targetState.loadedMboxJsonDicts.count)

        // verifies the Target's shared state
        XCTAssertEqual(1, mockRuntime.createdSharedStates.count)
        XCTAssertEqual("DE03D4AD-1FFE-421F-B2F2-303BF26822C1.35_0", mockRuntime.createdSharedStates[0]?["tntid"] as? String)
    }
    
    func testExecuteRawRequest_noPrefetchOrExecuteRequestsInDictionary() {
        MockNetworkService.request = nil
        ServiceProvider.shared.networkService = MockNetworkService()
    
        let data: [String: Any] = [
            "israwevent": true
        ]
        let executeRawRequestEvent = Event(name: "TargetRawRequest", type: "com.adobe.eventType.target", source: "com.adobe.eventSource.requestContent", data: data)
        
        // creates a configuration shared state
        mockRuntime.simulateSharedState(extensionName: "com.adobe.module.configuration", event: executeRawRequestEvent, data: (value: mockConfigSharedState, status: .set))
        
        target.onRegistered()
        
        let targetRequestExpectation = XCTestExpectation(description: "Target raw request expectation")
        
        let mockNetworkService = TestableNetworkService()
        ServiceProvider.shared.networkService = mockNetworkService
        mockNetworkService.mock { request in
            // verifies network request
            if request.url.absoluteString.contains("https://acopprod3.tt.omtrdc.net/rest/v1/delivery/?client=acopprod3&sessionId=") {
                targetRequestExpectation.fulfill()
            }
            return nil
        }

        guard let eventListener: EventListener = mockRuntime.listeners["com.adobe.eventType.target-com.adobe.eventSource.requestContent"] else {
            XCTFail()
            return
        }
        XCTAssertTrue(target.readyForEvent(executeRawRequestEvent))
        
        // handles the execute raw request event
        eventListener(executeRawRequestEvent)
        wait(for: [targetRequestExpectation], timeout: 1)
    }

    func testExecuteRawRequest_errorResponse() {
        // mocked network response
        let responseString = """
            {
              "message": "error_message"
            }
        """

        let data: [String: Any] = [
            "execute": [
                "mboxes": [
                    [
                        "index": 0,
                        "name": "t_test_01",
                        "parameters": [
                            "mbox-parameter-key1": "mbox-parameter-value1"
                        ]
                    ]
                ]
            ],
            "israwevent": true
        ]
        let executeRawRequestEvent = Event(name: "TargetRawRequest", type: "com.adobe.eventType.target", source: "com.adobe.eventSource.requestContent", data: data)

        // creates a configuration shared state
        mockRuntime.simulateSharedState(extensionName: "com.adobe.module.configuration", event: executeRawRequestEvent, data: (value: mockConfigSharedState, status: .set))

        // creates an identity shared state
        mockRuntime.simulateSharedState(extensionName: "com.adobe.module.identity", event: executeRawRequestEvent, data: (value: mockIdentityData, status: .set))

        // registers the event listeners for Target extension
        target.onRegistered()
        
        let targetRequestExpectation = XCTestExpectation(description: "Target raw request expectation")
        // override network service
        let mockNetworkService = TestableNetworkService()
        ServiceProvider.shared.networkService = mockNetworkService

        mockNetworkService.mock { request in
            XCTAssertNotNil(request)
            if request.url.absoluteString.contains("https://acopprod3.tt.omtrdc.net/rest/v1/delivery/?client=acopprod3&sessionId=") {
                targetRequestExpectation.fulfill()
                
                let validResponse = HTTPURLResponse(url: URL(string: "https://acopprod3.tt.omtrdc.net/rest/v1/delivery")!, statusCode: 400, httpVersion: nil, headerFields: nil)

                return (data: responseString.data(using: .utf8), response: validResponse, error: nil)
            }
            return nil
        }
        guard let eventListener: EventListener = mockRuntime.listeners["com.adobe.eventType.target-com.adobe.eventSource.requestContent"] else {
            XCTFail()
            return
        }
        
        XCTAssertTrue(target.readyForEvent(executeRawRequestEvent))
        
        // handles the execute raw request event
        eventListener(executeRawRequestEvent)
        wait(for: [targetRequestExpectation], timeout: 2)

        // Check the notifications are cleared
        XCTAssertTrue(target.targetState.notifications.isEmpty)
        XCTAssertEqual(0, target.targetState.loadedMboxJsonDicts.count)
        
        XCTAssertEqual(1, mockRuntime.dispatchedEvents.count)
        XCTAssertEqual("com.adobe.eventSource.responseContent", mockRuntime.dispatchedEvents[0].source)
        XCTAssertEqual("com.adobe.eventType.target", mockRuntime.dispatchedEvents[0].type)
        let eventData = mockRuntime.dispatchedEvents[0].data
        XCTAssertEqual("error_message", eventData?["responseerror"] as? String)
        XCTAssertNil(eventData?["responsedata"])
    }
    
    func testExecuteRawRequest_emptyExecuteMboxesResponse() {
        let responseString = """
            {
              "status": 200,
              "id": {
                "tntId": "DE03D4AD-1FFE-421F-B2F2-303BF26822C1.35_0",
                "marketingCloudVisitorId": "38209274908399841237725561727471528301"
              },
              "requestId": "01d4a408-6978-48f7-95c6-03f04160b257",
              "client": "acopprod3",
              "edgeHost": "mboxedge35.tt.omtrdc.net",
              "execute": {
                "mboxes": []
              }
            }
        """

        let data: [String: Any] = [
            "execute": [
                "mboxes": [
                    [
                        "index": 0,
                        "name": "t_test_01",
                        "parameters": [
                            "mbox-parameter-key1": "mbox-parameter-value1"
                        ]
                    ]
                ]
            ],
            "israwevent": true
        ]
        let executeRawRequestEvent = Event(name: "TargetRawRequest", type: "com.adobe.eventType.target", source: "com.adobe.eventSource.requestContent", data: data)

        // creates a configuration shared state
        mockRuntime.simulateSharedState(extensionName: "com.adobe.module.configuration", event: executeRawRequestEvent, data: (value: mockConfigSharedState, status: .set))
        
        // registers the event listeners for Target extension
        target.onRegistered()

        let targetRequestExpectation = XCTestExpectation(description: "Target raw request expectation")
        
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
            
            if request.url.absoluteString.contains("https://acopprod3.tt.omtrdc.net/rest/v1/delivery/?client=acopprod3&sessionId=") {
                targetRequestExpectation.fulfill()
                
                let validResponse = HTTPURLResponse(url: URL(string: "https://acopprod3.tt.omtrdc.net/rest/v1/delivery")!, statusCode: 200, httpVersion: nil, headerFields: nil)
                return (data: responseString.data(using: .utf8), response: validResponse, error: nil)
            }
            return nil
        }
        guard let eventListener: EventListener = mockRuntime.listeners["com.adobe.eventType.target-com.adobe.eventSource.requestContent"] else {
            XCTFail()
            return
        }
        XCTAssertTrue(target.readyForEvent(executeRawRequestEvent))
        
        // handles the execute raw request event
        eventListener(executeRawRequestEvent)
        wait(for: [targetRequestExpectation], timeout: 2)

        // verifies the content of network response was stored correctly
        XCTAssertEqual(1, mockRuntime.dispatchedEvents.count)
        XCTAssertNotNil(mockRuntime.dispatchedEvents[0].data)
        let responseData = mockRuntime.dispatchedEvents[0].data?["responsedata"] as? [String: Any]
        let execute = responseData?["execute"] as? [String: Any]
        let mboxes = execute?["mboxes"] as? [[String: Any]]
        XCTAssertEqual(true, mboxes?.isEmpty)
    }
    
    func testExecuteRawRequest_noTargetClientCodeInConfig() {
        mockConfigSharedState = ["global.privacy": "optedin"]
        
        let data: [String: Any] = [
            "prefetch": [
                "mboxes": [
                    [
                        "index": 0,
                        "name": "t_test_01",
                        "parameters": [
                            "mbox-parameter-key1": "mbox-parameter-value1"
                        ]
                    ]
                ]
            ],
            "israwevent": true
        ]
        
        let executeRawRequestEvent = Event(name: "TargetRawRequest", type: "com.adobe.eventType.target", source: "com.adobe.eventSource.requestContent", data: data)
        
        // creates a configuration shared state
        mockRuntime.simulateSharedState(extensionName: "com.adobe.module.configuration", event: executeRawRequestEvent, data: (value: mockConfigSharedState, status: .set))

        // creates an identity shared state
        mockRuntime.simulateSharedState(extensionName: "com.adobe.module.identity", event: executeRawRequestEvent, data: (value: mockIdentityData, status: .set))

        // registers the event listeners for Target extension
        target.onRegistered()
        
        let targetRequestExpectation = XCTestExpectation(description: "Target raw request expectation")
        targetRequestExpectation.isInverted = true

        // override network service
        let mockNetworkService = TestableNetworkService()
        ServiceProvider.shared.networkService = mockNetworkService
        mockNetworkService.mock { request in
            // verifies network request
            if request.url.absoluteString.contains("https://acopprod3.tt.omtrdc.net/rest/v1/delivery/?client=acopprod3&sessionId=") {
                targetRequestExpectation.fulfill()
            }
            return nil
        }

        guard let eventListener: EventListener = mockRuntime.listeners["com.adobe.eventType.target-com.adobe.eventSource.requestContent"] else {
            XCTFail()
            return
        }
        XCTAssertTrue(target.readyForEvent(executeRawRequestEvent))
        
        // handles the execute raw request event
        eventListener(executeRawRequestEvent)
        wait(for: [targetRequestExpectation], timeout: 1)

        // verifies the Target's shared state
        XCTAssertEqual(0, mockRuntime.createdSharedStates.count)
        

        // verifies the dispatched event
        XCTAssertEqual(1, mockRuntime.dispatchedEvents.count)
        XCTAssertEqual("TargetRawResponse", mockRuntime.dispatchedEvents[0].name)
        XCTAssertEqual("com.adobe.eventType.target", mockRuntime.dispatchedEvents[0].type)
        XCTAssertEqual("com.adobe.eventSource.responseContent", mockRuntime.dispatchedEvents[0].source)
        XCTAssertNil(mockRuntime.dispatchedEvents[0].data?["responsedata"])
        XCTAssertEqual("Missing client code", mockRuntime.dispatchedEvents[0].data?["responseerror"] as? String)
    }

    func testExecuteRawRequest_privacyNotOptedIn() {
        mockConfigSharedState = ["target.clientCode": "acopprod3", "global.privacy": "optedout"]

        let data: [String: Any] = [
            "prefetch": [
                "mboxes": [
                    [
                        "index": 0,
                        "name": "t_test_01",
                        "parameters": [
                            "mbox-parameter-key1": "mbox-parameter-value1"
                        ]
                    ]
                ]
            ],
            "israwevent": true
        ]
        
        let executeRawRequestEvent = Event(name: "TargetRawRequest", type: "com.adobe.eventType.target", source: "com.adobe.eventSource.requestContent", data: data)
        
        // creates a configuration shared state
        mockRuntime.simulateSharedState(extensionName: "com.adobe.module.configuration", event: executeRawRequestEvent, data: (value: mockConfigSharedState, status: .set))

        // creates an identity shared state
        mockRuntime.simulateSharedState(extensionName: "com.adobe.module.identity", event: executeRawRequestEvent, data: (value: mockIdentityData, status: .set))

        // registers the event listeners for Target extension
        target.onRegistered()

        let targetRequestExpectation = XCTestExpectation(description: "Target raw request expectation")
        targetRequestExpectation.isInverted = true
        
        // override network service
        let mockNetworkService = TestableNetworkService()
        ServiceProvider.shared.networkService = mockNetworkService
        mockNetworkService.mock { request in
            // verifies network request
            if request.url.absoluteString.contains("https://acopprod3.tt.omtrdc.net/rest/v1/delivery/?client=acopprod3&sessionId=") {
                targetRequestExpectation.fulfill()
            }
            return nil
        }
        
        guard let eventListener: EventListener = mockRuntime.listeners["com.adobe.eventType.target-com.adobe.eventSource.requestContent"] else {
            XCTFail()
            return
        }
        XCTAssertTrue(target.readyForEvent(executeRawRequestEvent))

        // handles the execute raw request event
        eventListener(executeRawRequestEvent)
        wait(for: [targetRequestExpectation], timeout: 1)

        // verifies the Target's shared state
        XCTAssertEqual(0, mockRuntime.createdSharedStates.count)

        // verifies the dispatched event
        XCTAssertEqual(1, mockRuntime.dispatchedEvents.count)
        XCTAssertEqual("TargetRawResponse", mockRuntime.dispatchedEvents[0].name)
        XCTAssertEqual("com.adobe.eventType.target", mockRuntime.dispatchedEvents[0].type)
        XCTAssertEqual("com.adobe.eventSource.responseContent", mockRuntime.dispatchedEvents[0].source)
        XCTAssertNil(mockRuntime.dispatchedEvents[0].data?["responsedata"])
        XCTAssertEqual("Privacy status is not opted in", mockRuntime.dispatchedEvents[0].data?["responseerror"] as? String)
    }
    
    func testExecuteRawRequest_privacyUnknown() {
        mockConfigSharedState = ["target.clientCode": "acopprod3", "global.privacy": "unknown"]

        let data: [String: Any] = [
            "prefetch": [
                "mboxes": [
                    [
                        "index": 0,
                        "name": "t_test_01",
                        "parameters": [
                            "mbox-parameter-key1": "mbox-parameter-value1"
                        ]
                    ]
                ]
            ],
            "israwevent": true
        ]
        
        let executeRawRequestEvent = Event(name: "TargetRawRequest", type: "com.adobe.eventType.target", source: "com.adobe.eventSource.requestContent", data: data)
        
        // creates a configuration shared state
        mockRuntime.simulateSharedState(extensionName: "com.adobe.module.configuration", event: executeRawRequestEvent, data: (value: mockConfigSharedState, status: .set))

        // creates an identity shared state
        mockRuntime.simulateSharedState(extensionName: "com.adobe.module.identity", event: executeRawRequestEvent, data: (value: mockIdentityData, status: .set))

        // registers the event listeners for Target extension
        target.onRegistered()

        let targetRequestExpectation = XCTestExpectation(description: "Target raw request expectation")
        targetRequestExpectation.isInverted = true
        
        // override network service
        let mockNetworkService = TestableNetworkService()
        ServiceProvider.shared.networkService = mockNetworkService
        mockNetworkService.mock { request in
            // verifies network request
            if request.url.absoluteString.contains("https://acopprod3.tt.omtrdc.net/rest/v1/delivery/?client=acopprod3&sessionId=") {
                targetRequestExpectation.fulfill()
            }
            return nil
        }
        
        guard let eventListener: EventListener = mockRuntime.listeners["com.adobe.eventType.target-com.adobe.eventSource.requestContent"] else {
            XCTFail()
            return
        }
        XCTAssertTrue(target.readyForEvent(executeRawRequestEvent))

        // handles the execute raw request event
        eventListener(executeRawRequestEvent)
        wait(for: [targetRequestExpectation], timeout: 1)

        // verifies the Target's shared state
        XCTAssertEqual(0, mockRuntime.createdSharedStates.count)

        // verifies the dispatched event
        XCTAssertEqual(1, mockRuntime.dispatchedEvents.count)
        XCTAssertEqual("TargetRawResponse", mockRuntime.dispatchedEvents[0].name)
        XCTAssertEqual("com.adobe.eventType.target", mockRuntime.dispatchedEvents[0].type)
        XCTAssertEqual("com.adobe.eventSource.responseContent", mockRuntime.dispatchedEvents[0].source)
        XCTAssertNil(mockRuntime.dispatchedEvents[0].data?["responsedata"])
        XCTAssertEqual("Privacy status is not opted in", mockRuntime.dispatchedEvents[0].data?["responseerror"] as? String)
    }
    
    func testSendRawNotifications() {
        // mocked network response
        let responseString = """
            {
              "status": 200,
              "id": {
                "tntId": "DE03D4AD-1FFE-421F-B2F2-303BF26822C1.35_0",
                "marketingCloudVisitorId": "38209274908399841237725561727471528301"
              },
              "requestId": "01d4a408-6978-48f7-95c6-03f04160b257",
              "client": "acopprod3",
              "edgeHost": "mboxedge35.tt.omtrdc.net",
              "notifications": {
                    "id": "4BA0B2EF-9A20-4BDC-9F97-0B955BC5FF84",
              }
            }
        """

        // Build the location data
        let data: [String: Any] = [
            "notifications": [
                [
                    "id": "0",
                    "mbox": [
                        "name": "t_test_01"
                    ],
                    "type": "click",
                    "timestamp": Int64(Date().timeIntervalSince1970 * 1000.0),
                    "tokens": ["QPaLjCeI9qKCBUylkRQKBg=="],
                    "parameters": [
                        "mbox-parameter-key1": "mbox-parameter-value1"
                    ],
                    "profileParameters": [
                        "subscription": "premium"
                    ],
                    "order": [
                        "id": "id1",
                        "total": 100.34,
                        "purchasedProductIds":[
                            "pId1"
                        ]
                    ],
                    "product": [
                        "id": "pId1",
                        "categoryId": "cId1"
                    ]
                ]
            ],
            "israwevent": true
        ]
        
        let sendRawNotificationsEvent = Event(name: "TargetRawNotifications", type: "com.adobe.eventType.target", source: "com.adobe.eventSource.requestContent", data: data)
        
        // creates a configuration shared state
        mockRuntime.simulateSharedState(extensionName: "com.adobe.module.configuration", event: sendRawNotificationsEvent, data: (value: mockConfigSharedState, status: .set))

        // creates a lifecycle shared state
        mockRuntime.simulateSharedState(extensionName: "com.adobe.module.lifecycle", event: sendRawNotificationsEvent, data: (value: mockLifecycleData, status: .set))

        // creates an identity shared state
        mockRuntime.simulateSharedState(extensionName: "com.adobe.module.identity", event: sendRawNotificationsEvent, data: (value: mockIdentityData, status: .set))

        target.onRegistered()

        let notificationExpectation = XCTestExpectation(description: "Target raw notification expectation")
        
        // override network service
        let mockNetworkService = TestableNetworkService()
        ServiceProvider.shared.networkService = mockNetworkService
        mockNetworkService.mock { request in
            // verifies network request
            XCTAssertNotNil(request)
            guard let payloadDictionary = self.payloadAsDictionary(request.connectPayload) else {
                XCTFail()
                return (data: nil, response: nil, error: nil)
            }

            XCTAssertTrue(request.url.absoluteString.contains("https://acopprod3.tt.omtrdc.net/rest/v1/delivery/?client=acopprod3&sessionId="))
            XCTAssertTrue(Set(payloadDictionary.keys) == Set([
                "id",
                "experienceCloud",
                "context",
                "property",
                "notifications",
                "environmentId",
            ]))

            // verifies payloadDictionary["id"]
            guard let idDictionary = payloadDictionary["id"] as? [String: Any] else {
                XCTFail()
                return (data: nil, response: nil, error: nil)
            }
            XCTAssertEqual("38209274908399841237725561727471528301", idDictionary["marketingCloudVisitorId"] as? String)
            guard let vids = idDictionary["customerIds"] as? [[String: Any]] else {
                XCTFail()
                return (data: nil, response: nil, error: nil)
            }
            XCTAssertEqual(1, vids.count)
            XCTAssertEqual("unknown", vids[0]["authenticatedState"] as? String)
            XCTAssertEqual("vid_id_1", vids[0]["id"] as? String)
            XCTAssertEqual("vid_type_1", vids[0]["integrationCode"] as? String)

            // verifies payloadDictionary["context"]
            guard let context = payloadDictionary["context"] as? [String: Any] else {
                XCTFail()
                return (data: nil, response: nil, error: nil)
            }
            XCTAssertTrue(Set(context.keys) == Set([
                "userAgent",
                "mobilePlatform",
                "screen",
                "channel",
                "application",
                "timeOffsetInMinutes",
            ]))

            // verifies payloadDictionary["property"]
            guard let propertyDictionary = payloadDictionary["property"] as? [String: Any] else {
                XCTFail()
                return (data: nil, response: nil, error: nil)
            }
            XCTAssertEqual("67444eb4-3681-40b4-831d-e082f5ccddcd", propertyDictionary["token"] as? String)
            
            // verifies payloadDictionary["notifications"]
            guard let notificationsArray = payloadDictionary["notifications"] as? [[String: Any]] else {
                XCTFail()
                return (data: nil, response: nil, error: nil)
            }
            
            XCTAssertNotNil(notificationsArray)
            XCTAssertEqual(1, notificationsArray.count)

            let notificationsJson = JSON(parseJSON: self.prettify(notificationsArray))
            XCTAssertNotNil(notificationsJson[0]["id"])
            XCTAssertNotNil(notificationsJson[0]["timestamp"])
            XCTAssertEqual("t_test_01", notificationsJson[0]["mbox"]["name"])
            XCTAssertEqual(1, notificationsJson[0]["tokens"].count)
            XCTAssertEqual("QPaLjCeI9qKCBUylkRQKBg==", notificationsJson[0]["tokens"][0])
            XCTAssertEqual("click", notificationsJson[0]["type"])
            XCTAssertEqual(1, notificationsJson[0]["parameters"].count)
            XCTAssertEqual("mbox-parameter-value1", notificationsJson[0]["parameters"]["mbox-parameter-key1"].stringValue)
            XCTAssertEqual(1, notificationsJson[0]["profileParameters"].count)
            XCTAssertEqual("premium", notificationsJson[0]["profileParameters"]["subscription"])
            XCTAssertEqual(3, notificationsJson[0]["order"].count)
            XCTAssertEqual(notificationsJson[0]["order"]["id"].stringValue, "id1")
            XCTAssertEqual(notificationsJson[0]["order"]["total"].doubleValue, 100.34)
            XCTAssertEqual(notificationsJson[0]["order"]["purchasedProductIds"], ["pId1"])
            XCTAssertEqual(2, notificationsJson[0]["product"].count)
            XCTAssertEqual(notificationsJson[0]["product"]["id"].stringValue, "pId1")
            XCTAssertEqual(notificationsJson[0]["product"]["categoryId"].stringValue, "cId1")

            notificationExpectation.fulfill()
            let validResponse = HTTPURLResponse(url: URL(string: "https://acopprod3.tt.omtrdc.net/rest/v1/delivery")!, statusCode: 200, httpVersion: nil, headerFields: nil)
            return (data: responseString.data(using: .utf8), response: validResponse, error: nil)
        }

        guard let eventListener: EventListener = mockRuntime.listeners["com.adobe.eventType.target-com.adobe.eventSource.requestContent"] else {
            XCTFail()
            return
        }

        XCTAssertTrue(target.readyForEvent(sendRawNotificationsEvent))
        
        // handles the send raw notification event
        eventListener(sendRawNotificationsEvent)
        wait(for: [notificationExpectation], timeout: 2)

        // Check the notifications are cleared
        XCTAssertTrue(target.targetState.notifications.isEmpty)

        // verifies the content of network response was stored correctly
        XCTAssertEqual("DE03D4AD-1FFE-421F-B2F2-303BF26822C1.35_0", target.targetState.tntId)
        XCTAssertEqual("mboxedge35.tt.omtrdc.net", target.targetState.edgeHost)

        // verifies the Target's shared state
        XCTAssertEqual(1, mockRuntime.createdSharedStates.count)
        XCTAssertEqual("DE03D4AD-1FFE-421F-B2F2-303BF26822C1.35_0", mockRuntime.createdSharedStates[0]?["tntid"] as? String)
    }

    func testSendRawNotifications_withPropertyTokenInEventData() {
        mockConfigSharedState = ["target.clientCode": "acopprod3", "global.privacy": "optedin"]
        
        // mocked network response
        let responseString = """
            {
              "status": 200,
              "id": {
                "tntId": "DE03D4AD-1FFE-421F-B2F2-303BF26822C1.35_0",
                "marketingCloudVisitorId": "38209274908399841237725561727471528301"
              },
              "requestId": "01d4a408-6978-48f7-95c6-03f04160b257",
              "client": "acopprod3",
              "edgeHost": "mboxedge35.tt.omtrdc.net",
              "notifications": {
                    "id": "4BA0B2EF-9A20-4BDC-9F97-0B955BC5FF84",
              }
            }
        """

        // Build the location data
        let data: [String: Any] = [
            "notifications": [
                [
                    "id": "0",
                    "mbox": [
                        "name": "t_test_01"
                    ],
                    "type": "click",
                    "timestamp": Int64(Date().timeIntervalSince1970 * 1000.0),
                    "tokens": ["QPaLjCeI9qKCBUylkRQKBg=="],
                    "parameters": [
                        "mbox-parameter-key1": "mbox-parameter-value1"
                    ]
                ]
            ],
            "property":[
                "token": "a2ec61d0-fab8-42f9-bf0f-699d169b48d8"
            ],
            "israwevent": true
        ]
        
        let sendRawNotificationsEvent = Event(name: "TargetRawNotifications", type: "com.adobe.eventType.target", source: "com.adobe.eventSource.requestContent", data: data)
        
        // creates a configuration shared state
        mockRuntime.simulateSharedState(extensionName: "com.adobe.module.configuration", event: sendRawNotificationsEvent, data: (value: mockConfigSharedState, status: .set))

        // creates an identity shared state
        mockRuntime.simulateSharedState(extensionName: "com.adobe.module.identity", event: sendRawNotificationsEvent, data: (value: mockIdentityData, status: .set))

        target.onRegistered()

        let notificationExpectation = XCTestExpectation(description: "Target raw notification expectation")
        
        // override network service
        let mockNetworkService = TestableNetworkService()
        ServiceProvider.shared.networkService = mockNetworkService
        mockNetworkService.mock { request in
            // verifies network request
            XCTAssertNotNil(request)
            guard let payloadDictionary = self.payloadAsDictionary(request.connectPayload) else {
                XCTFail()
                return nil
            }
            XCTAssertTrue(request.url.absoluteString.contains("https://acopprod3.tt.omtrdc.net/rest/v1/delivery/?client=acopprod3&sessionId="))
            XCTAssertTrue(Set(payloadDictionary.keys) == Set([
                "id",
                "experienceCloud",
                "context",
                "property",
                "notifications",
                "environmentId",
            ]))

            // verifies payloadDictionary["id"]
            guard let idDictionary = payloadDictionary["id"] as? [String: Any] else {
                XCTFail()
                return nil
            }
            XCTAssertEqual("38209274908399841237725561727471528301", idDictionary["marketingCloudVisitorId"] as? String)
            guard let vids = idDictionary["customerIds"] as? [[String: Any]] else {
                XCTFail()
                return nil
            }
            XCTAssertEqual(1, vids.count)
            XCTAssertEqual("unknown", vids[0]["authenticatedState"] as? String)
            XCTAssertEqual("vid_id_1", vids[0]["id"] as? String)
            XCTAssertEqual("vid_type_1", vids[0]["integrationCode"] as? String)

            // verifies payloadDictionary["context"]
            guard let context = payloadDictionary["context"] as? [String: Any] else {
                XCTFail()
                return nil
            }
            XCTAssertTrue(Set(context.keys) == Set([
                "userAgent",
                "mobilePlatform",
                "screen",
                "channel",
                "application",
                "timeOffsetInMinutes",
            ]))
            
            // verifies payloadDictionary["property"]
            guard let propertyDictionary = payloadDictionary["property"] as? [String: Any] else {
                XCTFail()
                return nil
            }
            XCTAssertEqual("a2ec61d0-fab8-42f9-bf0f-699d169b48d8", propertyDictionary["token"] as? String)

            // verifies payloadDictionary["notifications"]
            guard let notificationsArray = payloadDictionary["notifications"] as? [[String: Any]] else {
                XCTFail()
                return nil
            }

            XCTAssertNotNil(notificationsArray)
            XCTAssertEqual(1, notificationsArray.count)

            let notificationsJson = JSON(parseJSON: self.prettify(notificationsArray))
            XCTAssertNotNil(notificationsJson[0]["id"])
            XCTAssertNotNil(notificationsJson[0]["timestamp"])
            XCTAssertEqual("t_test_01", notificationsJson[0]["mbox"]["name"])
            XCTAssertEqual(1, notificationsJson[0]["tokens"].count)
            XCTAssertEqual("QPaLjCeI9qKCBUylkRQKBg==", notificationsJson[0]["tokens"][0])
            XCTAssertEqual("click", notificationsJson[0]["type"])
            XCTAssertEqual(1, notificationsJson[0]["parameters"].count)
            XCTAssertEqual("mbox-parameter-value1", notificationsJson[0]["parameters"]["mbox-parameter-key1"].stringValue)
            
            notificationExpectation.fulfill()
            let validResponse = HTTPURLResponse(url: URL(string: "https://acopprod3.tt.omtrdc.net/rest/v1/delivery")!, statusCode: 200, httpVersion: nil, headerFields: nil)
            return (data: responseString.data(using: .utf8), response: validResponse, error: nil)
        }

        guard let eventListener: EventListener = mockRuntime.listeners["com.adobe.eventType.target-com.adobe.eventSource.requestContent"] else {
            XCTFail()
            return
        }

        XCTAssertTrue(target.readyForEvent(sendRawNotificationsEvent))
        // handles the send raw notification event
        eventListener(sendRawNotificationsEvent)
        wait(for: [notificationExpectation], timeout: 2)

        // Check the notifications are cleared
        XCTAssertTrue(target.targetState.notifications.isEmpty)

        // verifies the content of network response was stored correctly
        XCTAssertEqual("DE03D4AD-1FFE-421F-B2F2-303BF26822C1.35_0", target.targetState.tntId)
        XCTAssertEqual("mboxedge35.tt.omtrdc.net", target.targetState.edgeHost)

        // verifies the Target's shared state
        XCTAssertEqual(1, mockRuntime.createdSharedStates.count)
        XCTAssertEqual("DE03D4AD-1FFE-421F-B2F2-303BF26822C1.35_0", mockRuntime.createdSharedStates[0]?["tntid"] as? String)
    }
    
    func testSendRawNotifications_withPropertyTokenInConfigurationAndEventData() {
        // mocked network response
        let responseString = """
            {
              "status": 200,
              "id": {
                "tntId": "DE03D4AD-1FFE-421F-B2F2-303BF26822C1.35_0",
                "marketingCloudVisitorId": "38209274908399841237725561727471528301"
              },
              "requestId": "01d4a408-6978-48f7-95c6-03f04160b257",
              "client": "acopprod3",
              "edgeHost": "mboxedge35.tt.omtrdc.net",
              "notifications": {
                    "id": "4BA0B2EF-9A20-4BDC-9F97-0B955BC5FF84",
              }
            }
        """

        // Build the location data
        let data: [String: Any] = [
            "notifications": [
                [
                    "id": "0",
                    "mbox": [
                        "name": "t_test_01"
                    ],
                    "type": "click",
                    "timestamp": Int64(Date().timeIntervalSince1970 * 1000.0),
                    "tokens": ["QPaLjCeI9qKCBUylkRQKBg=="],
                    "parameters": [
                        "mbox-parameter-key1": "mbox-parameter-value1"
                    ]
                ]
            ],
            "property":[
                "token": "a2ec61d0-fab8-42f9-bf0f-699d169b48d8"
            ],
            "israwevent": true
        ]
        
        let sendRawNotificationsEvent = Event(name: "TargetRawNotifications", type: "com.adobe.eventType.target", source: "com.adobe.eventSource.requestContent", data: data)
        
        // creates a configuration shared state
        mockRuntime.simulateSharedState(extensionName: "com.adobe.module.configuration", event: sendRawNotificationsEvent, data: (value: mockConfigSharedState, status: .set))

        // creates an identity shared state
        mockRuntime.simulateSharedState(extensionName: "com.adobe.module.identity", event: sendRawNotificationsEvent, data: (value: mockIdentityData, status: .set))

        target.onRegistered()

        let notificationExpectation = XCTestExpectation(description: "Target raw notification expectation")
        
        // override network service
        let mockNetworkService = TestableNetworkService()
        ServiceProvider.shared.networkService = mockNetworkService
        mockNetworkService.mock { request in
            // verifies network request
            XCTAssertNotNil(request)
            guard let payloadDictionary = self.payloadAsDictionary(request.connectPayload) else {
                XCTFail()
                return nil
            }
            XCTAssertTrue(request.url.absoluteString.contains("https://acopprod3.tt.omtrdc.net/rest/v1/delivery/?client=acopprod3&sessionId="))
            XCTAssertTrue(Set(payloadDictionary.keys) == Set([
                "id",
                "experienceCloud",
                "context",
                "property",
                "notifications",
                "environmentId",
            ]))

            // verifies payloadDictionary["id"]
            guard let idDictionary = payloadDictionary["id"] as? [String: Any] else {
                XCTFail()
                return nil
            }
            XCTAssertEqual("38209274908399841237725561727471528301", idDictionary["marketingCloudVisitorId"] as? String)
            guard let vids = idDictionary["customerIds"] as? [[String: Any]] else {
                XCTFail()
                return nil
            }
            XCTAssertEqual(1, vids.count)
            XCTAssertEqual("unknown", vids[0]["authenticatedState"] as? String)
            XCTAssertEqual("vid_id_1", vids[0]["id"] as? String)
            XCTAssertEqual("vid_type_1", vids[0]["integrationCode"] as? String)

            // verifies payloadDictionary["context"]
            guard let context = payloadDictionary["context"] as? [String: Any] else {
                XCTFail()
                return nil
            }
            XCTAssertTrue(Set(context.keys) == Set([
                "userAgent",
                "mobilePlatform",
                "screen",
                "channel",
                "application",
                "timeOffsetInMinutes",
            ]))
            
            // verifies payloadDictionary["property"]
            guard let propertyDictionary = payloadDictionary["property"] as? [String: Any] else {
                XCTFail()
                return nil
            }
            XCTAssertEqual("67444eb4-3681-40b4-831d-e082f5ccddcd", propertyDictionary["token"] as? String)

            // verifies payloadDictionary["notifications"]
            guard let notificationsArray = payloadDictionary["notifications"] as? [[String: Any]] else {
                XCTFail()
                return nil
            }

            XCTAssertNotNil(notificationsArray)
            XCTAssertEqual(1, notificationsArray.count)

            let notificationsJson = JSON(parseJSON: self.prettify(notificationsArray))
            XCTAssertNotNil(notificationsJson[0]["id"])
            XCTAssertNotNil(notificationsJson[0]["timestamp"])
            XCTAssertEqual("t_test_01", notificationsJson[0]["mbox"]["name"])
            XCTAssertEqual(1, notificationsJson[0]["tokens"].count)
            XCTAssertEqual("QPaLjCeI9qKCBUylkRQKBg==", notificationsJson[0]["tokens"][0])
            XCTAssertEqual("click", notificationsJson[0]["type"])
            XCTAssertEqual(1, notificationsJson[0]["parameters"].count)
            XCTAssertEqual("mbox-parameter-value1", notificationsJson[0]["parameters"]["mbox-parameter-key1"].stringValue)
            
            notificationExpectation.fulfill()
            let validResponse = HTTPURLResponse(url: URL(string: "https://acopprod3.tt.omtrdc.net/rest/v1/delivery")!, statusCode: 200, httpVersion: nil, headerFields: nil)
            return (data: responseString.data(using: .utf8), response: validResponse, error: nil)
        }

        guard let eventListener: EventListener = mockRuntime.listeners["com.adobe.eventType.target-com.adobe.eventSource.requestContent"] else {
            XCTFail()
            return
        }

        XCTAssertTrue(target.readyForEvent(sendRawNotificationsEvent))
        // handles the send raw notification event
        eventListener(sendRawNotificationsEvent)
        wait(for: [notificationExpectation], timeout: 2)

        // Check the notifications are cleared
        XCTAssertTrue(target.targetState.notifications.isEmpty)

        // verifies the content of network response was stored correctly
        XCTAssertEqual("DE03D4AD-1FFE-421F-B2F2-303BF26822C1.35_0", target.targetState.tntId)
        XCTAssertEqual("mboxedge35.tt.omtrdc.net", target.targetState.edgeHost)

        // verifies the Target's shared state
        XCTAssertEqual(1, mockRuntime.createdSharedStates.count)
        XCTAssertEqual("DE03D4AD-1FFE-421F-B2F2-303BF26822C1.35_0", mockRuntime.createdSharedStates[0]?["tntid"] as? String)
    }

    func testSendRawNotifications_afterRawExecuteRequestForClick() {
        // mocked network response
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
              "execute": {
                "mboxes": [
                  {
                    "index": 0,
                    "name": "t_test_01",
                    "options": [
                      {
                        "content": {
                          "key1": "value1"
                        },
                        "type": "json"
                      }
                    ],
                    "metrics": [
                     {
                        "type":"click",
                        "eventToken":"ABPi/uih7s0vo6/8kqyxjA=="
                     }
                    ]
                  }
                ]
              }
            }
        """

        let data: [String: Any] = [
            "execute": [
                "mboxes": [
                    [
                        "index": 0,
                        "name": "t_test_01",
                        "parameters": [
                            "mbox-parameter-key1": "mbox-parameter-value1"
                        ]
                    ]
                ]
            ],
            "israwevent": true
        ]
        let executeRawRequestEvent = Event(name: "TargetRawRequest", type: "com.adobe.eventType.target", source: "com.adobe.eventSource.requestContent", data: data)

        // creates a configuration shared state
        mockRuntime.simulateSharedState(extensionName: "com.adobe.module.configuration", event: executeRawRequestEvent, data: (value: mockConfigSharedState, status: .set))

        // creates an identity shared state
        mockRuntime.simulateSharedState(extensionName: "com.adobe.module.identity", event: executeRawRequestEvent, data: (value: mockIdentityData, status: .set))

        // registers the event listeners for Target extension
        target.onRegistered()

        let targetRequestExpectation = XCTestExpectation(description: "Target raw request expectation")
        
        // override network service
        let mockNetworkService = TestableNetworkService()
        ServiceProvider.shared.networkService = mockNetworkService
        mockNetworkService.mock { request in
            XCTAssertNotNil(request)
            if request.url.absoluteString.contains("https://acopprod3.tt.omtrdc.net/rest/v1/delivery/?client=acopprod3&sessionId=") {
                targetRequestExpectation.fulfill()
                let validResponse = HTTPURLResponse(url: URL(string: "https://acopprod3.tt.omtrdc.net/rest/v1/delivery")!, statusCode: 200, httpVersion: nil, headerFields: nil)
                return (data: responseString.data(using: .utf8), response: validResponse, error: nil)
            }
            return nil
        }

        guard let eventListener: EventListener = mockRuntime.listeners["com.adobe.eventType.target-com.adobe.eventSource.requestContent"] else {
            XCTFail()
            return
        }

        XCTAssertTrue(target.readyForEvent(executeRawRequestEvent))
        
        // handles execute raw request event
        eventListener(executeRawRequestEvent)
        wait(for: [targetRequestExpectation], timeout: 2)

        XCTAssertEqual(1, mockRuntime.dispatchedEvents.count)
        XCTAssertEqual("com.adobe.eventSource.responseContent", mockRuntime.dispatchedEvents[0].source)
        XCTAssertEqual("com.adobe.eventType.target", mockRuntime.dispatchedEvents[0].type)
        guard
            let responseData = mockRuntime.dispatchedEvents[0].data?["responsedata"] as? [String: Any],
            let execute = responseData["execute"] as? [String: Any],
            let executeMboxes = execute["mboxes"] as? [[String: Any]]
        else {
            XCTFail()
            return
        }
           
        XCTAssertEqual(1, executeMboxes.count)
        XCTAssertEqual("t_test_01", executeMboxes[0]["name"] as? String)
        let metrics = executeMboxes[0]["metrics"] as? [[String: Any]]
        XCTAssertEqual(1, metrics?.count)
        XCTAssertEqual("click", metrics?[0]["type"] as? String)
        let notificationToken = metrics?[0]["eventToken"] as? String
        XCTAssertEqual("ABPi/uih7s0vo6/8kqyxjA==", notificationToken)
        
        mockRuntime.createdSharedStates = []
        let notificationResponseString = """
            {
              "status": 200,
              "id": {
                "tntId": "DE03D4AD-1FFE-421F-B2F2-303BF26822C1.35_0",
                "marketingCloudVisitorId": "38209274908399841237725561727471528301"
              },
              "requestId": "01d4a408-6978-48f7-95c6-03f04160b257",
              "client": "acopprod3",
              "edgeHost": "mboxedge35.tt.omtrdc.net",
              "notifications": {
                    "id": "4BA0B2EF-9A20-4BDC-9F97-0B955BC5FF84",
              }
            }
        """
        
        // Build the notification data
        let notificationData: [String: Any] = [
            "notifications": [
                [
                    "id": "0",
                    "mbox": [
                        "name": "t_test_01"
                    ],
                    "type": "click",
                    "timestamp": Int64(Date().timeIntervalSince1970 * 1000.0),
                    "tokens": [notificationToken],
                    "parameters": [
                        "mbox-parameter-key2": "mbox-parameter-value2"
                    ]
                ]
            ],
            "israwevent": true
        ]

        let sendRawNotificationsEvent = Event(name: "TargetRawNotifications", type: "com.adobe.eventType.target", source: "com.adobe.eventSource.requestContent", data: notificationData)
        
        let notificationExpectation = XCTestExpectation(description: "Target raw notification expectation")
        
        mockNetworkService.resolvers.removeAll()
        mockNetworkService.mock { request in
            XCTAssertNotNil(request)
            if !request.url.absoluteString.contains("https://mboxedge35.tt.omtrdc.net/rest/v1/delivery/?client=acopprod3&sessionId=") {
                XCTFail()
                return nil
            }

            guard let payloadDictionary = self.payloadAsDictionary(request.connectPayload) else {
                XCTFail()
                return nil
            }

            guard let notificationsArray = payloadDictionary["notifications"] as? [[String: Any]] else {
                XCTFail()
                return nil
            }

            XCTAssertEqual(1, notificationsArray.count)
            let notificationsJson = JSON(parseJSON: self.prettify(notificationsArray))
            XCTAssertNotNil(notificationsJson[0]["id"])
            XCTAssertNotNil(notificationsJson[0]["timestamp"])
            XCTAssertEqual("t_test_01", notificationsJson[0]["mbox"]["name"])
            XCTAssertEqual(1, notificationsJson[0]["tokens"].count)
            XCTAssertEqual("ABPi/uih7s0vo6/8kqyxjA==", notificationsJson[0]["tokens"][0])
            XCTAssertEqual("click", notificationsJson[0]["type"])
            XCTAssertEqual(1, notificationsJson[0]["parameters"].count)
            XCTAssertEqual("mbox-parameter-value2", notificationsJson[0]["parameters"]["mbox-parameter-key2"].stringValue)
            
            notificationExpectation.fulfill()
            
            let validResponse = HTTPURLResponse(url: URL(string: "https://acopprod3.tt.omtrdc.net/rest/v1/delivery")!, statusCode: 200, httpVersion: nil, headerFields: nil)
            return (data: notificationResponseString.data(using: .utf8), response: validResponse, error: nil)
        }

        // simulate send raw notification event
        mockRuntime.simulateComingEvent(event: sendRawNotificationsEvent)
        wait(for: [notificationExpectation], timeout: 2)
        
        // Check the notifications are cleared
        XCTAssertTrue(target.targetState.notifications.isEmpty)
        
        // verifies the content of network response was stored correctly
        XCTAssertEqual("DE03D4AD-1FFE-421F-B2F2-303BF26822C1.35_0", target.targetState.tntId)
        XCTAssertEqual("mboxedge35.tt.omtrdc.net", target.targetState.edgeHost)

        // verifies the Target's shared state
        XCTAssertEqual(1, mockRuntime.createdSharedStates.count)
        XCTAssertEqual("DE03D4AD-1FFE-421F-B2F2-303BF26822C1.35_0", mockRuntime.createdSharedStates[0]?["tntid"] as? String)
    }
    
    func testSendRawNotifications_afterRawPrefetchRequestForDisplay() {
        // mocked network response
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
                    "name": "t_test_01",
                    "options": [
                      {
                        "content": {
                          "key1": "value1"
                        },
                        "type": "json",
                        "eventToken": "v6n3Lx+N4lhgIQKde5Zv2pNWHtnQtQrJfmRrQugEa2qCnQ9Y9OaLL2gsdrWQTvE54PwSz67rmXWmSnkXpSSS2Q=="
                      }
                    ]
                  }
                ]
              }
            }
        """

        let data: [String: Any] = [
            "execute": [
                "mboxes": [
                    [
                        "index": 0,
                        "name": "t_test_01",
                        "parameters": [
                            "mbox-parameter-key1": "mbox-parameter-value1"
                        ]
                    ]
                ]
            ],
            "israwevent": true
        ]
        let executeRawRequestEvent = Event(name: "TargetRawRequest", type: "com.adobe.eventType.target", source: "com.adobe.eventSource.requestContent", data: data)

        // creates a configuration shared state
        mockRuntime.simulateSharedState(extensionName: "com.adobe.module.configuration", event: executeRawRequestEvent, data: (value: mockConfigSharedState, status: .set))

        // creates an identity shared state
        mockRuntime.simulateSharedState(extensionName: "com.adobe.module.identity", event: executeRawRequestEvent, data: (value: mockIdentityData, status: .set))

        // registers the event listeners for Target extension
        target.onRegistered()

        let targetRequestExpectation = XCTestExpectation(description: "Target raw request expectation")
        
        // override network service
        let mockNetworkService = TestableNetworkService()
        ServiceProvider.shared.networkService = mockNetworkService
        mockNetworkService.mock { request in
            XCTAssertNotNil(request)
            if request.url.absoluteString.contains("https://acopprod3.tt.omtrdc.net/rest/v1/delivery/?client=acopprod3&sessionId=") {
                targetRequestExpectation.fulfill()
                let validResponse = HTTPURLResponse(url: URL(string: "https://acopprod3.tt.omtrdc.net/rest/v1/delivery")!, statusCode: 200, httpVersion: nil, headerFields: nil)
                return (data: responseString.data(using: .utf8), response: validResponse, error: nil)
            }
            return nil
        }

        guard let eventListener: EventListener = mockRuntime.listeners["com.adobe.eventType.target-com.adobe.eventSource.requestContent"] else {
            XCTFail()
            return
        }

        XCTAssertTrue(target.readyForEvent(executeRawRequestEvent))
        
        // handles execute raw request event
        eventListener(executeRawRequestEvent)
        wait(for: [targetRequestExpectation], timeout: 2)

        XCTAssertEqual(1, mockRuntime.dispatchedEvents.count)
        XCTAssertEqual("com.adobe.eventSource.responseContent", mockRuntime.dispatchedEvents[0].source)
        XCTAssertEqual("com.adobe.eventType.target", mockRuntime.dispatchedEvents[0].type)
        guard
            let responseData = mockRuntime.dispatchedEvents[0].data?["responsedata"] as? [String: Any],
            let prefetch = responseData["prefetch"] as? [String: Any],
            let prefetchMboxes = prefetch["mboxes"] as? [[String: Any]]
        else {
            XCTFail()
            return
        }
           
        XCTAssertEqual(1, prefetchMboxes.count)
        XCTAssertEqual("t_test_01", prefetchMboxes[0]["name"] as? String)
        let options = prefetchMboxes[0]["options"] as? [[String: Any]]
        XCTAssertEqual(1, options?.count)
        let notificationToken = options?[0]["eventToken"] as? String
        XCTAssertEqual("v6n3Lx+N4lhgIQKde5Zv2pNWHtnQtQrJfmRrQugEa2qCnQ9Y9OaLL2gsdrWQTvE54PwSz67rmXWmSnkXpSSS2Q==", notificationToken)
        
        mockRuntime.createdSharedStates = []
        let notificationResponseString = """
            {
              "status": 200,
              "id": {
                "tntId": "DE03D4AD-1FFE-421F-B2F2-303BF26822C1.35_0",
                "marketingCloudVisitorId": "38209274908399841237725561727471528301"
              },
              "requestId": "01d4a408-6978-48f7-95c6-03f04160b257",
              "client": "acopprod3",
              "edgeHost": "mboxedge35.tt.omtrdc.net",
              "notifications": {
                    "id": "4BA0B2EF-9A20-4BDC-9F97-0B955BC5FF84",
              }
            }
        """
        
        // Build the notification data
        let notificationData: [String: Any] = [
            "notifications": [
                [
                    "id": "0",
                    "mbox": [
                        "name": "t_test_01"
                    ],
                    "type": "display",
                    "timestamp": Int64(Date().timeIntervalSince1970 * 1000.0),
                    "tokens": [notificationToken],
                    "parameters": [
                        "mbox-parameter-key2": "mbox-parameter-value2"
                    ]
                ]
            ],
            "israwevent": true
        ]

        let sendRawNotificationsEvent = Event(name: "TargetRawNotifications", type: "com.adobe.eventType.target", source: "com.adobe.eventSource.requestContent", data: notificationData)
        
        let notificationExpectation = XCTestExpectation(description: "Target raw notification expectation")
        
        mockNetworkService.resolvers.removeAll()
        mockNetworkService.mock { request in
            XCTAssertNotNil(request)
            if !request.url.absoluteString.contains("https://mboxedge35.tt.omtrdc.net/rest/v1/delivery/?client=acopprod3&sessionId=") {
                XCTFail()
                return nil
            }

            guard let payloadDictionary = self.payloadAsDictionary(request.connectPayload) else {
                XCTFail()
                return nil
            }

            guard let notificationsArray = payloadDictionary["notifications"] as? [[String: Any]] else {
                XCTFail()
                return nil
            }

            XCTAssertEqual(1, notificationsArray.count)
            let notificationsJson = JSON(parseJSON: self.prettify(notificationsArray))
            XCTAssertNotNil(notificationsJson[0]["id"])
            XCTAssertNotNil(notificationsJson[0]["timestamp"])
            XCTAssertEqual("t_test_01", notificationsJson[0]["mbox"]["name"])
            XCTAssertEqual(1, notificationsJson[0]["tokens"].count)
            XCTAssertEqual("v6n3Lx+N4lhgIQKde5Zv2pNWHtnQtQrJfmRrQugEa2qCnQ9Y9OaLL2gsdrWQTvE54PwSz67rmXWmSnkXpSSS2Q==", notificationsJson[0]["tokens"][0])
            XCTAssertEqual("display", notificationsJson[0]["type"])
            XCTAssertEqual(1, notificationsJson[0]["parameters"].count)
            XCTAssertEqual("mbox-parameter-value2", notificationsJson[0]["parameters"]["mbox-parameter-key2"].stringValue)
            
            notificationExpectation.fulfill()
            
            let validResponse = HTTPURLResponse(url: URL(string: "https://acopprod3.tt.omtrdc.net/rest/v1/delivery")!, statusCode: 200, httpVersion: nil, headerFields: nil)
            return (data: notificationResponseString.data(using: .utf8), response: validResponse, error: nil)
        }

        // simulate send raw notification event
        mockRuntime.simulateComingEvent(event: sendRawNotificationsEvent)
        wait(for: [notificationExpectation], timeout: 2)
        
        // Check the notifications are cleared
        XCTAssertTrue(target.targetState.notifications.isEmpty)
        
        // verifies the content of network response was stored correctly
        XCTAssertEqual("DE03D4AD-1FFE-421F-B2F2-303BF26822C1.35_0", target.targetState.tntId)
        XCTAssertEqual("mboxedge35.tt.omtrdc.net", target.targetState.edgeHost)

        // verifies the Target's shared state
        XCTAssertEqual(1, mockRuntime.createdSharedStates.count)
        XCTAssertEqual("DE03D4AD-1FFE-421F-B2F2-303BF26822C1.35_0", mockRuntime.createdSharedStates[0]?["tntid"] as? String)
    }

    func testSendRawNotifications_noNotificationsInDictionary() {
        MockNetworkService.request = nil
        ServiceProvider.shared.networkService = MockNetworkService()
        
        let data: [String: Any] = [
            "israwevent": true
        ]
        
        let sendRawNotificationsEvent = Event(name: "TargetRawNotifications", type: "com.adobe.eventType.target", source: "com.adobe.eventSource.requestContent", data: data)
        
        // creates a configuration shared state
        mockRuntime.simulateSharedState(extensionName: "com.adobe.module.configuration", event: sendRawNotificationsEvent, data: (value: mockConfigSharedState, status: .set))
        
        target.onRegistered()

        let notificationExpectation = XCTestExpectation(description: "Target raw notification expectation")
        
        let mockNetworkService = TestableNetworkService()
        ServiceProvider.shared.networkService = mockNetworkService
        mockNetworkService.mock { request in
            // verifies network request
            if request.url.absoluteString.contains("https://acopprod3.tt.omtrdc.net/rest/v1/delivery/?client=acopprod3&sessionId=") {
                notificationExpectation.fulfill()
            }
            return nil
        }

        guard let eventListener: EventListener = mockRuntime.listeners["com.adobe.eventType.target-com.adobe.eventSource.requestContent"] else {
            XCTFail()
            return
        }
        XCTAssertTrue(target.readyForEvent(sendRawNotificationsEvent))
        
        // handles the send raw notification event
        eventListener(sendRawNotificationsEvent)
        wait(for: [notificationExpectation], timeout: 1)
    }

    func testSendRawNotifications_notificationErrorResponse() {
        // mocked network response
        let responseString = """
            {
              "message": "Notifications error"
            }
        """

        // Build the location data
        let data: [String: Any] = [
            "notifications": [
                [
                    "id": "0",
                    "mbox": [
                        "name": "t_test_01"
                    ],
                    "type": "click",
                    "timestamp": Int64(Date().timeIntervalSince1970 * 1000.0),
                    "tokens": ["QPaLjCeI9qKCBUylkRQKBg=="],
                    "parameters": [
                        "mbox-parameter-key1": "mbox-parameter-value1"
                    ]
                ]
            ],
            "israwevent": true
        ]
        
        let sendRawNotificationsEvent = Event(name: "TargetRawNotifications", type: "com.adobe.eventType.target", source: "com.adobe.eventSource.requestContent", data: data)
        
        // creates a configuration shared state
        mockRuntime.simulateSharedState(extensionName: "com.adobe.module.configuration", event: sendRawNotificationsEvent, data: (value: mockConfigSharedState, status: .set))

        // creates an identity shared state
        mockRuntime.simulateSharedState(extensionName: "com.adobe.module.identity", event: sendRawNotificationsEvent, data: (value: mockIdentityData, status: .set))

        target.onRegistered()

        let notificationExpectation = XCTestExpectation(description: "Target raw notification expectation")
        
        // override network service
        let mockNetworkService = TestableNetworkService()
        ServiceProvider.shared.networkService = mockNetworkService
        mockNetworkService.mock { request in
            XCTAssertNotNil(request)
            notificationExpectation.fulfill()
            let targetResponse = HTTPURLResponse(url: URL(string: "https://acopprod3.tt.omtrdc.net/rest/v1/delivery")!, statusCode: 400, httpVersion: nil, headerFields: nil)

            return (data: responseString.data(using: .utf8), response: targetResponse, error: nil)
        }

        guard let eventListener: EventListener = mockRuntime.listeners["com.adobe.eventType.target-com.adobe.eventSource.requestContent"] else {
            XCTFail()
            return
        }
        XCTAssertTrue(target.readyForEvent(sendRawNotificationsEvent))

        // handles the send raw notification event
        eventListener(sendRawNotificationsEvent)
        wait(for: [notificationExpectation], timeout: 2)

        // Check the notifications are cleared
        XCTAssertTrue(target.targetState.notifications.isEmpty)

        // verifies the content of network response was stored correctly
        XCTAssertNotEqual("DE03D4AD-1FFE-421F-B2F2-303BF26822C1.35_0", target.targetState.tntId)
        XCTAssertNotEqual("mboxedge35.tt.omtrdc.net", target.targetState.edgeHost)

        // verifies the Target shared state
        XCTAssertEqual(0, mockRuntime.createdSharedStates.count)
    }
}
