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

@testable import AEPCore
@testable import AEPServices
@testable import AEPTarget
import XCTest

class TargetStateTests: XCTestCase {
    override func setUpWithError() throws {
        UserDefaults.clear()
        ServiceProvider.shared.namedKeyValueService.setAppGroup(nil)
    }

    private func getTargetDataStore() -> NamedCollectionDataStore {
        return NamedCollectionDataStore(name: "com.adobe.module.target")
    }

    func testUpdateConfigurationSharedState() {
        let targetState = TargetState()
        XCTAssertNil(targetState.storedConfigurationSharedState)
        targetState.updateConfigurationSharedState([
            "target.clientCode": "code_123",
            "global.privacy": "optedin",
        ])
        XCTAssertEqual(NSDictionary(dictionary: ["target.clientCode": "code_123", "global.privacy": "optedin"]), targetState.storedConfigurationSharedState as NSDictionary?)
    }

    func testUpdateConfigurationSharedStateWithNewClientCode() {
        let targetState = TargetState()
        targetState.updateConfigurationSharedState([
            "target.clientCode": "code_123",
            "global.privacy": "optedin",
        ])
        targetState.updateEdgeHost("edge-host-1")
        targetState.updateSessionTimestamp()
        targetState.updateConfigurationSharedState([
            "target.clientCode": "code_456",
            "global.privacy": "optedin",
        ])
        XCTAssertEqual(NSDictionary(dictionary: ["target.clientCode": "code_456", "global.privacy": "optedin"]), targetState.storedConfigurationSharedState as NSDictionary?)
        XCTAssertNil(targetState.edgeHost)
    }

    func testPrivacyStatus() {
        let targetState = TargetState()
        targetState.updateConfigurationSharedState([
            "target.clientCode": "code_123",
            "global.privacy": "optedin",
        ])
        XCTAssertTrue(targetState.privacyStatusIsOptIn)
        targetState.updateConfigurationSharedState([
            "target.clientCode": "code_123",
            "global.privacy": "optedout",
        ])
        XCTAssertTrue(targetState.privacyStatusIsOptOut)
    }

    func testClientCode() {
        let targetState = TargetState()
        XCTAssertEqual(nil, targetState.clientCode)
        targetState.updateConfigurationSharedState([
            "target.clientCode": "code_123",
            "global.privacy": "optedin",
        ])
        XCTAssertEqual("code_123", targetState.clientCode)
        targetState.updateConfigurationSharedState([
            "target.clientCode": "code_456",
            "global.privacy": "optedin",
        ])
        XCTAssertEqual("code_456", targetState.clientCode)
    }

    func testEnvironmentId() {
        let targetState = TargetState()
        XCTAssertEqual(0, targetState.environmentId)
        targetState.updateConfigurationSharedState([
            "target.clientCode": "code_123",
            "global.privacy": "optedin",
            "target.environmentId": 45,
        ])
        XCTAssertEqual(45, targetState.environmentId)
    }

    func testPropertyToken() {
        let targetState = TargetState()
        XCTAssertTrue(targetState.propertyToken.isEmpty)
        targetState.updateConfigurationSharedState([
            "target.clientCode": "code_123",
            "global.privacy": "optedin",
            "target.environmentId": 45,
            "target.propertyToken": "configAtProperty",
        ])
        XCTAssertEqual("configAtProperty", targetState.propertyToken)
    }

    func testTargetServer() {
        let targetState = TargetState()
        XCTAssertNil(targetState.targetServer)
        targetState.updateConfigurationSharedState([
            "target.clientCode": "code_123",
            "global.privacy": "optedin",
            "target.environmentId": 45,
            "target.server": "myHost.here.com",
        ])
        XCTAssertEqual("myHost.here.com", targetState.targetServer)
    }

    func testNetworkTimeout() {
        let targetState = TargetState()
        XCTAssertEqual(5.0, targetState.networkTimeout)
        targetState.updateConfigurationSharedState([
            "target.clientCode": "code_123",
            "global.privacy": "optedin",
            "target.environmentId": 45,
            "target.timeout": 10,
        ])
        XCTAssertEqual(10.0, targetState.networkTimeout)
    }

    func testSessionId() {
        let targetState = TargetState()
        let targetDataStore = getTargetDataStore()
        targetState.updateConfigurationSharedState([
            "target.clientCode": "code_123",
            "global.privacy": "optedin",
            "target.timeout": 10,
            "target.sessionTimeout": 1800,
        ])

        let sessionId = "mockSessionId"
        targetState.updateSessionId(sessionId)
        XCTAssertEqual(sessionId, targetState.sessionId)
        XCTAssertEqual(sessionId, targetDataStore.getString(key: "session.id"))

        targetState.updateSessionId("")

        let newSessionId = targetState.sessionId
        XCTAssertFalse(newSessionId.isEmpty)
        XCTAssertEqual(newSessionId, targetDataStore.getString(key: "session.id"))

        XCTAssertNotEqual(sessionId, newSessionId)
    }

    func testSessionId_whenSessionIsExpired() {
        let targetState = TargetState()
        let targetDataStore = getTargetDataStore()
        targetState.updateConfigurationSharedState([
            "target.clientCode": "code_123",
            "global.privacy": "optedin",
            "target.timeout": 10,
            "target.sessionTimeout": 2,
        ])

        let sessionId = targetState.sessionId
        XCTAssertFalse(sessionId.isEmpty)
        XCTAssertEqual(sessionId, targetDataStore.getString(key: "session.id"))

        sleep(3)

        let newSessionId = targetState.sessionId
        XCTAssertFalse(newSessionId.isEmpty)
        XCTAssertEqual(newSessionId, targetDataStore.getString(key: "session.id"))

        XCTAssertNotEqual(sessionId, newSessionId)
    }

    func testSessionId_whenSessionIsNotExpired() {
        let targetState = TargetState()
        let targetDataStore = getTargetDataStore()
        targetState.updateConfigurationSharedState([
            "target.clientCode": "code_123",
            "global.privacy": "optedin",
            "target.timeout": 10,
            "target.sessionTimeout": 100,
        ])

        let sessionId = targetState.sessionId
        XCTAssertFalse(sessionId.isEmpty)
        XCTAssertEqual(sessionId, targetDataStore.getString(key: "session.id"))

        sleep(3)

        let newSessionId = targetState.sessionId
        XCTAssertFalse(newSessionId.isEmpty)
        XCTAssertEqual(newSessionId, targetDataStore.getString(key: "session.id"))

        XCTAssertEqual(sessionId, newSessionId)
    }
}
