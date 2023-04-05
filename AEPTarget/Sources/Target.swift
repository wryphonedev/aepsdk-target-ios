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
import AEPCore
import AEPServices
import Foundation

@objc(AEPMobileTarget)
public class Target: NSObject, Extension {
    static let LOG_TAG = "Target"

    private(set) var targetState: TargetState

    private var networkService: Networking {
        return ServiceProvider.shared.networkService
    }

    private var inPreviewMode: Bool {
        if let previewParameters = previewManager.previewParameters, !previewParameters.isEmpty {
            return true
        }
        return false
    }

    // MARK: - Extension

    public var name = TargetConstants.EXTENSION_NAME

    public var friendlyName = TargetConstants.FRIENDLY_NAME

    public static var extensionVersion = TargetConstants.EXTENSION_VERSION

    public var metadata: [String: String]?

    public var runtime: ExtensionRuntime

    var previewManager: PreviewManager = TargetPreviewManager()

    public required init?(runtime: ExtensionRuntime) {
        self.runtime = runtime
        TargetV5Migrator.migrate()
        TargetV4Migrator.migrate()
        targetState = TargetState()
        super.init()
    }

    public func onRegistered() {
        registerListener(type: EventType.target, source: EventSource.requestContent, listener: handleRequestContent)
        registerListener(type: EventType.target, source: EventSource.requestReset, listener: handleReset)
        registerListener(type: EventType.target, source: EventSource.requestIdentity, listener: handleRequestIdentity)
        registerListener(type: EventType.configuration, source: EventSource.responseContent, listener: handleConfigurationResponseContent)
        registerListener(type: EventType.genericData, source: EventSource.os, listener: handleGenericDataOS)
    }

    public func onUnregistered() {}

    public func readyForEvent(_ event: Event) -> Bool {
        targetState.updateConfigurationSharedState(retrieveLatestConfiguration(event))
        return targetState.storedConfigurationSharedState != nil
    }

    // MARK: - Event Listeners

    private func handle(event _: Event) {}

    private func handleGenericDataOS(event: Event) {
        if let deeplink = event.data?[TargetConstants.EventDataKeys.DEEPLINK] as? String, !deeplink.isEmpty {
            processPreviewDeepLink(event: event, deeplink: deeplink)
        }
    }

    private func handleRequestIdentity(_ event: Event) {
        if let eventData = event.data {
            if let thirdPartyId = eventData[TargetConstants.EventDataKeys.THIRD_PARTY_ID] as? String {
                setThirdPartyId(thirdPartyId: thirdPartyId, event: event)
                return
            }

            if let tntId = eventData[TargetConstants.EventDataKeys.TNT_ID] as? String {
                setTntId(tntId: tntId, event: event)
                return
            }

            if let sessionId = eventData[TargetConstants.EventDataKeys.TARGET_SESSION_ID] as? String {
                setSessionId(sessionId: sessionId)
                return
            }
        }

        dispatchRequestIdentityResponse(triggerEvent: event)
    }

    private func handleConfigurationResponseContent(_ event: Event) {
        if targetState.privacyStatusIsOptOut {
            resetIdentity()
            createSharedState(data: targetState.generateSharedState(), event: event)
            return
        }
    }

    private func handleReset(_ event: Event) {
        if event.isResetExperienceEvent {
            resetIdentity()
            createSharedState(data: targetState.generateSharedState(), event: event)
        }
        if event.isClearPrefetchCache {
            targetState.clearprefetchedMboxes()
        }
    }

    private func handleRequestContent(_ event: Event) {
        if event.isRawEvent {
            handleRawRequest(event)
            return
        }

        if event.isPrefetchEvent {
            prefetchContent(event)
            return
        }

        if event.isLoadRequest {
            loadRequest(event)
            return
        }

        if event.isLocationsDisplayedEvent {
            displayedLocations(event)
            return
        }

        if event.isLocationClickedEvent {
            clickedLocation(event)
            return
        }

        if let restartDeeplink = event.data?[TargetConstants.EventDataKeys.PREVIEW_RESTART_DEEP_LINK] as? String {
            previewManager.setRestartDeepLink(restartDeeplink)
        }

        Log.debug(label: Target.LOG_TAG, "Unknown event: \(event)")
    }

    // MARK: - Event Handlers

    private func processPreviewDeepLink(event: Event, deeplink: String) {
        guard let configSharedState = getSharedState(extensionName: TargetConstants.Configuration.EXTENSION_NAME, event: event)?.value else {
            Log.warning(label: Target.LOG_TAG, "Target process preview deep link failed, config data is nil")
            return
        }

        if let error = prepareForTargetRequest() {
            Log.error(label: Target.LOG_TAG, "Target is not enabled, cannot enter in preview mode. \(error)")
            return
        }

        let isPreviewEnabled = configSharedState[TargetConstants.Configuration.SharedState.Keys.TARGET_PREVIEW_ENABLED] as? Bool ?? true
        if !isPreviewEnabled {
            Log.error(label: Target.LOG_TAG, "Target preview is disabled, please change the configuration and try again.")
            return
        }

        let clientCode = targetState.clientCode ?? ""
        guard let deeplinkUrl = URL(string: deeplink) else {
            Log.error(label: Target.LOG_TAG, "Deeplink is not a valid url")
            return
        }

        previewManager.enterPreviewModeWithDeepLink(clientCode: clientCode, deepLink: deeplinkUrl)
    }

    private func getDeliveryResponse(_ data: Data?) -> TargetDeliveryResponse? {
        guard let data = data, let responseDict = try? JSONDecoder().decode([String: AnyCodable].self, from: data), let dict = AnyCodable.toAnyDictionary(dictionary: responseDict) else {
            return nil
        }
        return TargetDeliveryResponse(responseJson: dict)
    }

    /// Handle prefetch content request
    /// - Parameter event: an event of type target and  source request content is dispatched by the `EventHub`
    private func prefetchContent(_ event: Event) {
        if inPreviewMode {
            dispatchPrefetchErrorEvent(triggerEvent: event, errorMessage: "Target prefetch can't be used while in preview mode")
            return
        }

        guard let targetPrefetchArray = event.prefetchObjectArray else {
            dispatchPrefetchErrorEvent(triggerEvent: event, errorMessage: "Empty or nil prefetch requests list")
            return
        }

        // Check whether request can be sent
        if let error = prepareForTargetRequest() {
            dispatchPrefetchErrorEvent(triggerEvent: event, errorMessage: error)
            return
        }

        let lifecycleSharedState = getSharedState(extensionName: TargetConstants.Lifecycle.EXTENSION_NAME, event: event)?.value
        let identitySharedState = getSharedState(extensionName: TargetConstants.Identity.EXTENSION_NAME, event: event)?.value

        let error = sendTargetRequest(event,
                                      prefetchRequests: targetPrefetchArray,
                                      targetParameters: event.targetParameters,
                                      lifecycleData: lifecycleSharedState,
                                      identityData: identitySharedState) { connection in
            // Clear notification
            self.targetState.clearNotifications()

            let response = self.getDeliveryResponse(connection.data)

            guard connection.responseCode == 200 else {
                self.dispatchPrefetchErrorEvent(triggerEvent: event, errorMessage: "Errors returned in Target response with response code: \(String(describing: connection.responseCode)), error message : \(String(describing: response?.errorMessage))")
                return
            }

            guard let deliveryResponse = response else {
                self.dispatchPrefetchErrorEvent(triggerEvent: event, errorMessage: "Target response parser initialization failed")
                return
            }
            if let tntId = deliveryResponse.tntId { self.setTntIdInternal(tntId: tntId) }
            if let edgeHost = deliveryResponse.edgeHost { self.targetState.updateEdgeHost(edgeHost) }
            self.createSharedState(data: self.targetState.generateSharedState(), event: event)

            if let mboxes = deliveryResponse.prefetchMboxes {
                var mboxesDictionary = [String: [String: Any]]()
                for mbox in mboxes {
                    if let name = mbox[TargetResponseConstants.JSONKeys.MBOX_NAME] as? String { mboxesDictionary[name] = mbox }
                }
                if !mboxesDictionary.isEmpty { self.targetState.mergePrefetchedMboxJson(mboxesDictionary: mboxesDictionary) }
            }

            // Remove duplicate loaded mboxes
            for (k, _) in self.targetState.prefetchedMboxJsonDicts {
                self.targetState.removeLoadedMbox(mboxName: k)
            }

            self.dispatch(event: event.createResponseEvent(name: TargetConstants.EventName.PREFETCH_RESPOND, type: EventType.target, source: EventSource.responseContent, data: [TargetConstants.EventDataKeys.PREFETCH_RESULT: true]))
        }

        if let err = error {
            dispatchPrefetchErrorEvent(triggerEvent: event, errorMessage: err)
        }
    }

    /// Request multiple Target mboxes in a single network call.
    /// - Parameter event: an event of type target and  source request content is dispatched by the `EventHub`
    private func loadRequest(_ event: Event) {
        guard let targetRequests = event.targetRequests else {
            Log.debug(label: Target.LOG_TAG, "Unable to process the batch requests, Target Batch Requests are null")
            return
        }

        let targetParameters = event.targetParameters

        let lifecycleSharedState = getSharedState(extensionName: TargetConstants.Lifecycle.EXTENSION_NAME, event: event)?.value
        let identitySharedState = getSharedState(extensionName: TargetConstants.Identity.EXTENSION_NAME, event: event)?.value

        // Check whether request can be sent
        if let error = prepareForTargetRequest() {
            Log.debug(label: Target.LOG_TAG, "\(TargetError.ERROR_BATCH_REQUEST_SEND_FAILED) \(error)")
            runDefaultCallbacks(event: event, batchRequests: targetRequests)
            return
        }

        var requestsToSend: [TargetRequest] = targetRequests

        let timestamp = Int64(event.timestamp.timeIntervalSince1970 * 1000.0)

        if !inPreviewMode {
            Log.debug(label: Target.LOG_TAG, "Current cached mboxes : \(targetState.prefetchedMboxJsonDicts.keys.description), size: \(targetState.prefetchedMboxJsonDicts.count)")
            requestsToSend = processCachedTargetRequest(event: event, batchRequests: targetRequests, timeStamp: timestamp)
        }

        if requestsToSend.isEmpty && targetState.notifications.isEmpty {
            Log.warning(label: Target.LOG_TAG, "Unable to process the batch requests, requests and notifications are empty")
            return
        }

        let error = sendTargetRequest(event,
                                      batchRequests: requestsToSend,
                                      targetParameters: targetParameters,
                                      lifecycleData: lifecycleSharedState,
                                      identityData: identitySharedState) { connection in
            self.processTargetRequestResponse(batchRequests: requestsToSend, event: event, connection: connection)
        }

        if let error = error {
            Log.warning(label: Target.LOG_TAG, error)
        }
    }

    /// Sends display notifications to Target
    /// Reads the display tokens from the cache either {@link #prefetchedMbox} or {@link #loadedMbox} to send the display notifications.
    /// The display notification is not sent if,
    /// - Target Extension is not configured.
    /// - Privacy status is opted-out or opt-unknown.
    /// - If the mboxes are either loaded previously or not prefetched.
    private func displayedLocations(_ event: Event) {
        guard let eventData = event.data else {
            Log.warning(label: Target.LOG_TAG, "Unable to handle request content, event data is nil.")
            return
        }

        Log.trace(label: Target.LOG_TAG, "Handling Locations Displayed - event \(event.name) type: \(event.type) source: \(event.source) ")

        // Check whether request can be sent
        if let error = prepareForTargetRequest() {
            Log.warning(label: Target.LOG_TAG, TargetError.ERROR_DISPLAY_NOTIFICATION_SEND_FAILED + error)
            return
        }

        let lifecycleSharedState = getSharedState(extensionName: TargetConstants.Lifecycle.EXTENSION_NAME, event: event)?.value
        let identitySharedState = getSharedState(extensionName: TargetConstants.Identity.EXTENSION_NAME, event: event)?.value

        guard let mboxNames = eventData[TargetConstants.EventDataKeys.MBOX_NAMES] as? [String], !mboxNames.isEmpty else {
            Log.warning(label: Target.LOG_TAG, "Location displayed unsuccessful \(TargetError.ERROR_MBOX_NAMES_NULL_OR_EMPTY)")
            return
        }

        for mboxName in mboxNames {
            // If loadedMbox contains mboxName then do not send analytics request again
            if mboxName.isEmpty || targetState.loadedMboxJsonDicts[mboxName] != nil {
                continue
            }

            guard let mboxJson = targetState.prefetchedMboxJsonDicts[mboxName] else {
                Log.warning(label: Target.LOG_TAG, "\(TargetError.ERROR_NO_CACHED_MBOX_FOUND) \(mboxName).")
                continue
            }

            let timeInMills = Int64(event.timestamp.timeIntervalSince1970 * 1000.0)

            if !addDisplayNotification(mboxName: mboxName, mboxJson: mboxJson, targetParameters: event.targetParameters, lifecycleData: lifecycleSharedState, timestamp: timeInMills) {
                Log.debug(label: Target.LOG_TAG, "displayedLocations - \(mboxName) mbox not added for display notification.")
                continue
            }

            // dispatch internal analytics for target event with analytics payload, if available
            if let analyticsPayload = getAnalyticsForTargetPayload(json: mboxJson) {
                dispatchAnalyticsForTargetRequest(payload: preprocessAnalyticsPayload(analyticsPayload, sessionId: targetState.sessionId))
            }
        }

        if targetState.notifications.isEmpty {
            Log.debug(label: Target.LOG_TAG, "displayedLocations - \(TargetError.ERROR_DISPLAY_NOTIFICATION_NOT_SENT)")
            return
        }

        let error = sendTargetRequest(event, targetParameters: event.targetParameters, lifecycleData: lifecycleSharedState, identityData: identitySharedState) { connection in
            self.processNotificationResponse(event: event, connection: connection)
        }

        if let err = error {
            Log.warning(label: Target.LOG_TAG, err)
        }
    }

    /// Sends a click notification to Target if click metrics are enabled for the provided location name.
    /// Reads the clicked token from the cached either {@link #prefetchedMbox} or {@link #loadedMbox} to send the click notification. The clicked notification is not sent if,
    /// The click notification is not sent if,
    /// - Target Extension is not configured.
    /// - Privacy status is opted-out or opt-unknown.
    /// - If the mbox is either not prefetched or loaded previously.
    /// - If the clicked token is empty or nil for the loaded mbox.
    private func clickedLocation(_ event: Event) {
        if inPreviewMode {
            Log.warning(label: Target.LOG_TAG, "Target location clicked notification can't be sent while in preview mode")
            return
        }

        guard let eventData = event.data else {
            Log.warning(label: Target.LOG_TAG, "Unable to handle request content, event data is nil.")
            return
        }

        guard let mboxName = eventData[TargetConstants.EventDataKeys.MBOX_NAME] as? String else {
            Log.warning(label: Target.LOG_TAG, "Location clicked unsuccessful \(TargetError.ERROR_MBOX_NAME_NULL_OR_EMPTY)")
            return
        }

        Log.trace(label: Target.LOG_TAG, "Handling Location Clicked - event \(event.name) type: \(event.type) source: \(event.source) ")

        // Check if the mbox is already prefetched or loaded.
        // if not, Log and bail out

        guard let mboxJson = targetState.prefetchedMboxJsonDicts[mboxName] ?? targetState.loadedMboxJsonDicts[mboxName] else {
            Log.warning(label: Target.LOG_TAG, "\(TargetError.ERROR_CLICK_NOTIFICATION_SEND_FAILED) \(TargetError.ERROR_NO_CACHED_MBOX_FOUND) \(mboxName).")
            return
        }

        let metric = extractClickMetric(mboxJson: mboxJson)
        guard metric.token != nil else {
            Log.warning(label: Target.LOG_TAG, "\(TargetError.ERROR_CLICK_NOTIFICATION_SEND_FAILED) \(TargetError.ERROR_NO_CLICK_METRICS) \(mboxName).")
            return
        }

        // bail out if the target configuration is not available or if the privacy is opted-out
        if let error = prepareForTargetRequest() {
            Log.warning(label: Target.LOG_TAG, TargetError.ERROR_CLICK_NOTIFICATION_NOT_SENT + error)
            return
        }

        let lifecycleSharedState = getSharedState(extensionName: TargetConstants.Lifecycle.EXTENSION_NAME, event: event)?.value
        let identitySharedState = getSharedState(extensionName: TargetConstants.Identity.EXTENSION_NAME, event: event)?.value

        let timeInMills = Int64(event.timestamp.timeIntervalSince1970 * 1000.0)

        // create and add click notification to the notification list
        if !addClickedNotification(mboxJson: mboxJson, targetParameters: event.targetParameters, lifecycleData: lifecycleSharedState, timestamp: timeInMills) {
            Log.debug(label: Target.LOG_TAG, "handleLocationClicked - \(mboxName) mbox not added for click notification.")
            return
        }

        // dispatch internal analytics for target event with click-tracking analytics payload, if available
        if let analyticsPayload = metric.analyticsPayload {
            dispatchAnalyticsForTargetRequest(payload: preprocessAnalyticsPayload(analyticsPayload, sessionId: targetState.sessionId))
        }

        let error = sendTargetRequest(event, targetParameters: event.targetParameters, lifecycleData: lifecycleSharedState, identityData: identitySharedState) { connection in
            self.processNotificationResponse(event: event, connection: connection)
        }

        if let err = error {
            Log.warning(label: Target.LOG_TAG, err)
        }
    }

    // MARK: - Helpers

    /// Process the network response after the notification network call.
    /// - Parameters:
    ///     - event: event which triggered this network call
    ///     - connection: `NetworkService.HttpConnection` instance
    private func processNotificationResponse(event: Event, connection: HttpConnection) {
        if connection.responseCode == 200 {
            targetState.clearNotifications()
        }

        guard let data = connection.data, let responseDict = try? JSONDecoder().decode([String: AnyCodable].self, from: data), let dict: [String: Any] = AnyCodable.toAnyDictionary(dictionary: responseDict) else {
            Log.debug(label: Target.LOG_TAG, "Target response parser initialization failed")
            return
        }
        let response = TargetDeliveryResponse(responseJson: dict)

        if connection.responseCode != 200 {
            Log.debug(label: Target.LOG_TAG, "Errors returned in Target response with response code: \(String(describing: connection.responseCode))")
        }

        if let error = response.errorMessage {
            if error.contains(TargetError.ERROR_NOTIFICATION_TAG) {
                targetState.clearNotifications()
            }

            Log.debug(label: Target.LOG_TAG, "Errors returned in Target response: \(error)")
            return
        }

        if let tntId = response.tntId { setTntIdInternal(tntId: tntId) }
        if let edgeHost = response.edgeHost { targetState.updateEdgeHost(edgeHost) }
        createSharedState(data: targetState.generateSharedState(), event: event)
    }

    /// Process the network response after the notification network call.
    /// - Parameters:
    ///     - batchRequests: `[TargetRequest]` representing the desired mboxes to load
    ///     - event: event which triggered this network call
    ///     - connection: `NetworkService.HttpConnection` instance
    private func processTargetRequestResponse(batchRequests: [TargetRequest], event: Event, connection: HttpConnection) {
        if connection.responseCode == 200 {
            targetState.clearNotifications()
        }

        guard let data = connection.data, let responseDict = try? JSONDecoder().decode([String: AnyCodable].self, from: data), let dict = AnyCodable.toAnyDictionary(dictionary: responseDict) else {
            Log.debug(label: Target.LOG_TAG, "Target response parser initialization failed")
            runDefaultCallbacks(event: event, batchRequests: batchRequests)
            return
        }

        let response = TargetDeliveryResponse(responseJson: dict)

        if let error = response.errorMessage {
            if error.contains(TargetError.ERROR_NOTIFICATION_TAG) {
                targetState.clearNotifications()
            }
            Log.debug(label: Target.LOG_TAG, "Errors returned in Target request response: \(error)")
            runDefaultCallbacks(event: event, batchRequests: batchRequests)
            return
        }

        if connection.responseCode != 200 {
            Log.debug(label: Target.LOG_TAG, "Errors returned in Target response with response code: \(String(describing: connection.responseCode))")
            runDefaultCallbacks(event: event, batchRequests: batchRequests)
            return
        }

        if let tntId = response.tntId { targetState.updateTntId(tntId) }
        if let edgeHost = response.edgeHost { targetState.updateEdgeHost(edgeHost) }
        createSharedState(data: targetState.generateSharedState(), event: event)

        var mboxesDictionary = [String: [String: Any]]()
        if let mboxes = response.executeMboxes {
            for mbox in mboxes {
                if let name = mbox[TargetResponseConstants.JSONKeys.MBOX_NAME] as? String { mboxesDictionary[name] = mbox }
            }
            if !mboxesDictionary.isEmpty {
                // save the loaded mboxes from target response to be used later on for notifications
                targetState.saveLoadedMbox(mboxesDictionary: mboxesDictionary)
            }
        } else {
            runDefaultCallbacks(event: event, batchRequests: batchRequests)
            return
        }

        for targetRequest in batchRequests {
            guard let mboxJson = mboxesDictionary[targetRequest.name] else {
                dispatchMboxContent(event: event, content: targetRequest.defaultContent, data: nil, responsePairId: targetRequest.responsePairId)
                continue
            }

            let (content, responseTokens) = extractMboxContentAndResponseTokens(mboxJson: mboxJson)
            let analyticsPayload = getAnalyticsForTargetPayload(json: mboxJson)

            // dispatch internal analytics for target event with analytics payload, if available
            if let payload = analyticsPayload {
                dispatchAnalyticsForTargetRequest(payload: preprocessAnalyticsPayload(payload, sessionId: targetState.sessionId))
            }
            let clickmetric = extractClickMetric(mboxJson: mboxJson)

            // package analytics payload and response tokens to be returned in request callback
            let responsePayload = packageMboxResponsePayload(responseTokens: responseTokens, analyticsPayload: analyticsPayload, metricsAnalyticsPayload: clickmetric.analyticsPayload)

            dispatchMboxContent(event: event, content: content ?? targetRequest.defaultContent, data: responsePayload, responsePairId: targetRequest.responsePairId)
        }
    }

    private func dispatchPrefetchErrorEvent(triggerEvent: Event, errorMessage: String) {
        Log.warning(label: Target.LOG_TAG, "dispatch prefetch error event, error message : \(errorMessage)")
        dispatch(event: triggerEvent.createResponseEvent(name: TargetConstants.EventName.PREFETCH_RESPOND, type: EventType.target, source: EventSource.responseContent, data: [TargetConstants.EventDataKeys.PREFETCH_ERROR: errorMessage, TargetConstants.EventDataKeys.PREFETCH_RESULT: false]))
    }

    private func dispatchRequestIdentityResponse(triggerEvent: Event) {
        var eventData: [String: Any] = [:]
        if let thirdPartyId = targetState.thirdPartyId {
            eventData[TargetConstants.EventDataKeys.THIRD_PARTY_ID] = thirdPartyId
        }
        if let tntId = targetState.tntId {
            eventData[TargetConstants.EventDataKeys.TNT_ID] = tntId
        }
        eventData[TargetConstants.EventDataKeys.TARGET_SESSION_ID] = targetState.sessionId
        dispatch(event: triggerEvent.createResponseEvent(name: TargetConstants.EventName.IDENTITY_RESPONSE, type: EventType.target, source: EventSource.responseIdentity, data: eventData))
    }

    private func getTargetDeliveryURL(targetServer: String?, clientCode: String) -> String {
        if let targetServer = targetServer, !targetServer.isEmpty {
            return String(format: TargetConstants.DELIVERY_API_URL_BASE, targetServer, clientCode, targetState.sessionId)
        }

        if let host = targetState.edgeHost, !host.isEmpty {
            return String(format: TargetConstants.DELIVERY_API_URL_BASE, host, clientCode, targetState.sessionId)
        }

        return String(format: TargetConstants.DELIVERY_API_URL_BASE, String(format: TargetConstants.API_URL_HOST_BASE, clientCode), clientCode, targetState.sessionId)
    }

    /// Prepares for the target requests and checks whether a target request can be sent.
    /// - returns: error indicating why the request can't be sent, nil otherwise
    private func prepareForTargetRequest() -> String? {
        guard let _ = targetState.clientCode else {
            Log.warning(label: Target.LOG_TAG, "Target requests failed because, \(TargetError.ERROR_NO_CLIENT_CODE)")
            return TargetError.ERROR_NO_CLIENT_CODE
        }

        guard targetState.privacyStatusIsOptIn else {
            Log.warning(label: Target.LOG_TAG, "Target requests failed because, \(TargetError.ERROR_NOT_OPTED_IN)")
            return TargetError.ERROR_NOT_OPTED_IN
        }

        return nil
    }

    private func retrieveLatestConfiguration(_ event: Event) -> [String: Any]? {
        return getSharedState(extensionName: TargetConstants.Configuration.EXTENSION_NAME, event: event)?.value
    }

    /// Adds the display notification for the given mbox to the {@link #notifications} list
    /// - Parameters:
    ///     - mboxName: the displayed mbox name
    ///     - mboxJson: the cached `Mbox` object
    ///     - targetParameters: `TargetParameters` object corresponding to the display location
    ///     - lifecycleData: the lifecycle dictionary that should be added as mbox parameters
    ///     - timestamp: timestamp associated with the notification event
    /// - Returns: `Bool` indicating the success of appending the display notification to the notification list
    private func addDisplayNotification(mboxName: String, mboxJson: [String: Any], targetParameters: TargetParameters?, lifecycleData: [String: Any]?, timestamp: Int64) -> Bool {
        let lifecycleContextData = getLifecycleDataForTarget(lifecycleData: lifecycleData)
        guard let displayNotification = TargetDeliveryRequestBuilder.getDisplayNotification(mboxName: mboxName, cachedMboxJson: mboxJson, targetParameters: targetParameters, timestamp: timestamp, lifecycleContextData: lifecycleContextData) else {
            Log.debug(label: Target.LOG_TAG, "addDisplayNotification - \(TargetError.ERROR_DISPLAY_NOTIFICATION_NULL_FOR_MBOX), \(mboxName)")
            return false
        }

        targetState.addNotification(displayNotification)
        return true
    }

    /// Adds the clicked notification for the given mbox to the {@link #notifications} list.
    /// - Parameters:
    ///     - mboxJson: the cached `Mbox` object
    ///     - targetParameters: `TargetParameters` object corresponding to the display location
    ///     - lifecycleData: the lifecycle dictionary that should be added as mbox parameters
    ///     - timestamp: timestamp associated with the notification event
    /// - Returns: `Bool` indicating the success of appending the click notification to the notification list
    private func addClickedNotification(mboxJson: [String: Any?], targetParameters: TargetParameters?, lifecycleData: [String: Any]?, timestamp: Int64) -> Bool {
        let lifecycleContextData = getLifecycleDataForTarget(lifecycleData: lifecycleData)
        guard let clickNotification = TargetDeliveryRequestBuilder.getClickedNotification(cachedMboxJson: mboxJson, targetParameters: targetParameters, timestamp: timestamp, lifecycleContextData: lifecycleContextData) else {
            Log.debug(label: Target.LOG_TAG, "addClickedNotification - \(TargetError.ERROR_CLICK_NOTIFICATION_NOT_SENT)")
            return false
        }
        targetState.addNotification(clickNotification)
        return true
    }

    /// Converts data from a lifecycle event into its form desired by Target.
    private func getLifecycleDataForTarget(lifecycleData: [String: Any]?) -> [String: String]? {
        guard var tempLifecycleContextData = lifecycleData?[TargetConstants.Lifecycle.SharedState.Keys.LIFECYCLE_CONTEXT_DATA] as? [String: String] else {
            return nil
        }

        var lifecycleContextData: [String: String] = [:]

        for (k, v) in TargetConstants.MAP_TO_CONTEXT_DATA_KEYS {
            if let value = tempLifecycleContextData[k], !value.isEmpty {
                lifecycleContextData[v] = value
                tempLifecycleContextData.removeValue(forKey: k)
            }
        }

        for (k1, v1) in tempLifecycleContextData {
            lifecycleContextData.updateValue(v1, forKey: k1)
        }

        return lifecycleContextData
    }

    private func sendTargetRequest(_ event: Event,
                                   batchRequests: [TargetRequest]? = nil,
                                   prefetchRequests: [TargetPrefetch]? = nil,
                                   targetParameters: TargetParameters? = nil,
                                   lifecycleData: [String: Any]? = nil,
                                   identityData: [String: Any]? = nil,
                                   completionHandler: ((HttpConnection) -> Void)?)
    -> String? {
        let tntId = targetState.tntId
        let thirdPartyId = targetState.thirdPartyId
        let environmentId = Int64(targetState.environmentId)
        let lifecycleContextData = getLifecycleDataForTarget(lifecycleData: lifecycleData)

        // Give preference to property token passed in configuration over event data "at_property".
        let propertyToken = !targetState.propertyToken.isEmpty ? targetState.propertyToken : event.propertyToken

        guard let requestJson = TargetDeliveryRequestBuilder.build(tntId: tntId, thirdPartyId: thirdPartyId, identitySharedState: identityData, lifecycleSharedState: lifecycleContextData, targetPrefetchArray: prefetchRequests, targetRequestArray: batchRequests, targetParameters: targetParameters, notifications: targetState.notifications.isEmpty ? nil : targetState.notifications, environmentId: environmentId, propertyToken: propertyToken, qaModeParameters: previewManager.previewParameters)?.toJSON() else {
            return "Failed to generate request parameter(JSON) for target delivery API call"
        }

        let headers = [TargetConstants.HEADER_CONTENT_TYPE: TargetConstants.HEADER_CONTENT_TYPE_JSON]

        guard let clientCode = targetState.clientCode else {
            return "Missing client code"
        }

        guard let url = URL(string: getTargetDeliveryURL(targetServer: targetState.targetServer, clientCode: clientCode)) else {
            return "Failed to generate the url for target API call"
        }

        let timeout = targetState.networkTimeout

        // https://developers.adobetarget.com/api/delivery-api/#tag/Delivery-API
        let request = NetworkRequest(url: url, httpMethod: .post, connectPayload: requestJson, httpHeaders: headers, connectTimeout: timeout, readTimeout: timeout)

        stopEvents()
        Log.debug(label: Target.LOG_TAG, "Sending Target request with url: \(url.absoluteString) and body: \(requestJson).")
        networkService.connectAsync(networkRequest: request) { connection in
            Log.debug(label: Target.LOG_TAG, "Target response is received with code: \(connection.responseCode ?? -1) and data: \(connection.responseString ?? "").")
            self.targetState.updateSessionTimestamp()
            if let completionHandler = completionHandler {
                completionHandler(connection)
            }
            self.startEvents()
        }
        return nil
    }

    /// Clears identities including tntId, thirdPartyId, edgeHost, sessionId
    /// - Parameters:
    ///     - configurationSharedState: `Dictionary` Configuration shared state
    private func resetIdentity() {
        setTntIdInternal(tntId: nil)
        setThirdPartyIdInternal(thirdPartyId: nil)
        targetState.updateEdgeHost(nil)
        resetSession()
    }

    /// Saves the third party Id
    /// - Parameters:
    ///     - event: event which has the third party Id in event data
    private func setThirdPartyId(thirdPartyId: String, event: Event) {
        guard let eventData = event.data as [String: Any]? else {
            Log.error(label: Target.LOG_TAG, "Unable to set third party id, event data is nil.")
            return
        }

        setThirdPartyIdInternal(thirdPartyId: thirdPartyId)
        createSharedState(data: eventData, event: event)
    }

    /// Saves the provided Target session Id in the data store.
    /// If the privacy status is opt out or the provided session Id is empty,  the corresponding key is removed from the data store.
    /// - Parameters:
    ///     - sessionId: new session Id that needs to be set in the SDK
    private func setSessionId(sessionId: String) {
        guard !targetState.privacyStatusIsOptOut else {
            Log.debug(label: Target.LOG_TAG, "setSessionId - Cannot update Target sessionId due to opt out privacy status.")
            return
        }

        guard !sessionId.isEmpty else {
            Log.debug(label: Target.LOG_TAG, "setSessionId - Provided sessionId is empty, resetting the Target session.")
            resetSession()
            return
        }

        if sessionId != targetState.storedSessionId {
            Log.debug(label: Target.LOG_TAG, "setSessionId - Updated Target session Id with the provided value \(sessionId).")
            targetState.updateSessionId(sessionId)
        }
        targetState.updateSessionTimestamp()
    }

    /// Saves the tntId in the SDK and creates a shared state to share the persisted identifier.
    ///
    /// - Parameters:
    ///     - tntId: string containing the new tntId to be set in the SDK.
    ///     - event: incoming event containing the new tntId.
    private func setTntId(tntId: String, event: Event) {
        guard let eventData = event.data as [String: Any]? else {
            Log.error(label: Target.LOG_TAG, "Unable to set tnt Id, event data is nil.")
            return
        }

        setTntIdInternal(tntId: tntId)
        createSharedState(data: eventData, event: event)
    }

    /// Saves the tntId and the edge host value derived from it to the Target data store.
    ///
    /// The tntId has the format UUID.\<profile location hint\>. The edge host value can be derived from the profile location hint.
    /// For example, if the tntId is 10abf6304b2714215b1fd39a870f01afc.28_20, then the edgeHost will be mboxedge28.tt.omtrdc.net.
    ///
    /// If a valid tntId is provided and the privacy status is opted out or the provided tntId is same as the existing value, then the method returns with no further action.
    /// If nil value is provided for the tntId, then both tntId and edge host values are removed from the Target data store.
    ///
    /// - Parameters:
    ///     - tntId: string containing tntId to be set in the SDK.
    private func setTntIdInternal(tntId: String?) {
        // do not set identifier if privacy is opt-out and the id is not being cleared
        if targetState.privacyStatusIsOptOut, let tntId = tntId, !tntId.isEmpty {
            Log.debug(label: Target.LOG_TAG, "setTntIdInternal - Cannot update Target tntId due to opt out privacy status.")
            return
        }

        if tntId == targetState.tntId {
            Log.debug(label: Target.LOG_TAG, "setTntIdInternal - Won't update Target tntId as provided value is same as the existing tntId value \(String(describing: tntId)).")
            return
        }

        if
            let locationHintRange = tntId?.range(of: "(?<=[0-9A-Fa-f-]\\.)([\\d][^\\D]*)(?=_)", options: .regularExpression),
            let locationHint = tntId?[locationHintRange],
            !locationHint.isEmpty
        {
            let edgeHost = String(format: TargetConstants.API_URL_HOST_BASE, String(format: TargetConstants.EDGE_HOST_BASE, String(locationHint)))
            Log.debug(label: Target.LOG_TAG, "setTntIdInternal - The edge host value derived from the given tntId \(String(describing: tntId)) is \(edgeHost).")
            targetState.updateEdgeHost(edgeHost)
        } else {
            Log.debug(label: Target.LOG_TAG, "setTntIdInternal - The edge host value cannot be derived from the given tntId \(String(describing: tntId)) and it is removed from the data store.")
            targetState.updateEdgeHost(nil)
        }

        Log.trace(label: Target.LOG_TAG, "setTntIdInternal - Updating tntId with value \(String(describing: tntId)).")
        targetState.updateTntId(tntId)
    }

    /// Saves the thirdPartyId to the Target DataStore or remove its key in the dataStore if the newThirdPartyId is nil
    /// - Parameters:
    ///     - thirdPartyId: `String` to  be set
    private func setThirdPartyIdInternal(thirdPartyId: String?) {
        if targetState.privacyStatusIsOptOut, let thirdPartyId = thirdPartyId, !thirdPartyId.isEmpty {
            Log.debug(label: Target.LOG_TAG, "setThirdPartyIdInternal - Cannot update Target thirdPartyId due to opt out privacy status.")
            return
        }

        if thirdPartyId == targetState.thirdPartyId {
            Log.debug(label: Target.LOG_TAG, "setThirdPartyIdInternal - New thirdPartyId value is same as the existing thirdPartyId \(String(describing: thirdPartyId))")
            return
        }

        targetState.updateThirdPartyId(thirdPartyId)
    }

    /// Resets current  sessionId and the sessionTimestampInSeconds
    private func resetSession() {
        targetState.updateSessionId("")
        targetState.updateSessionTimestamp(reset: true)
    }

    /// Runs the default callback for each of the request in the list.
    /// - Parameters:
    ///     - batchRequests: `[TargetRequests]` to return the default content
    private func runDefaultCallbacks(event: Event, batchRequests: [TargetRequest]) {
        for request in batchRequests {
            dispatchMboxContent(event: event, content: request.defaultContent, data: nil, responsePairId: request.responsePairId)
        }
    }

    /// Executes a raw Target prefetch or execute request for the provided request event data.
    /// .
    /// - Parameter event: a Target request content event containing request data.
    private func handleRawRequest(_ event: Event) {
        let execute: Mboxes? = event.getTypedData(for: TargetConstants.EventDataKeys.EXECUTE)
        let prefetch: Mboxes? = event.getTypedData(for: TargetConstants.EventDataKeys.PREFETCH)
        let notifications: [Notification]? = event.getTypedData(for: TargetConstants.EventDataKeys.NOTIFICATIONS)
        let isContentRequest: Bool = prefetch != nil || execute != nil
        var error: String?

        defer {
            if error != nil, isContentRequest {
                dispatchTargetRawResponse(event: event, error: error, data: nil)
            }
        }

        var environmentId = Int64(targetState.environmentId)
        if environmentId == 0 {
            environmentId = event.environmentId
        }

        let identitySharedState = getSharedState(extensionName: TargetConstants.Identity.EXTENSION_NAME, event: event)?.value

        var id: TargetIDs? = event.getTypedData(for: TargetConstants.EventDataKeys.ID)
        if id == nil {
            id = TargetDeliveryRequestBuilder.getTargetIDs(tntid: targetState.tntId, thirdPartyId: targetState.thirdPartyId, identitySharedState: identitySharedState)
        }

        var experienceCloud: ExperienceCloudInfo? = event.getTypedData(for: TargetConstants.EventDataKeys.EXPERIENCE_CLOUD)
        if experienceCloud == nil {
            experienceCloud = TargetDeliveryRequestBuilder.getExperienceCloudInfo(identitySharedState: identitySharedState)
        }

        var context: TargetContext? = event.getTypedData(for: TargetConstants.EventDataKeys.CONTEXT)
        if context == nil {
            context = TargetDeliveryRequestBuilder.getTargetContext()
        }

        // Give preference to property token passed in configuration over event data.
        var property: Property?
        if !targetState.propertyToken.isEmpty {
            property = Property(token: targetState.propertyToken)
        } else {
            property = event.getTypedData(for: TargetConstants.EventDataKeys.PROPERTY)
        }

        var qaMode: [String: AnyCodable]?
        if let qaModeParameters = previewManager.previewParameters, !qaModeParameters.isEmpty, let qaModeData = qaModeParameters.data(using: .utf8) {
            let qaModeDict = try? JSONSerialization.jsonObject(with: qaModeData, options: []) as? [String: Any]
            qaMode = AnyCodable.from(dictionary: qaModeDict?[TargetConstants.TargetJson.QA_MODE] as? [String: Any])
        }

        guard let requestJson = TargetDeliveryRequest(id: id!, context: context!, experienceCloud: experienceCloud!, prefetch: prefetch, execute: execute, notifications: notifications, environmentId: environmentId, property: property, qaMode: qaMode).toJSON() else {
            error = TargetError.ERROR_INVALID_REQUEST
            Log.debug(label: Target.LOG_TAG, "handleRawRequest - Cannot process raw Target request, failed to generate request JSON for delivery API call.")
            return
        }

        // Check whether request can be sent
        if let requestError = prepareForTargetRequest() {
            error = requestError
            Log.debug(label: Target.LOG_TAG, "handleRawRequest - Cannot process the raw Target request: \(requestError)")
            return
        }

        guard let clientCode = targetState.clientCode else {
            error = TargetError.ERROR_NO_CLIENT_CODE
            Log.debug(label: Target.LOG_TAG, "handleRawRequest - Cannot process raw Target request, client code configuration is missing.")
            return
        }

        guard let url = URL(string: getTargetDeliveryURL(targetServer: targetState.targetServer, clientCode: clientCode)) else {
            Log.debug(label: Target.LOG_TAG, "handleRawRequest - Cannot process raw Target request, failed to generate the URL for Target delivery API call.")
            return
        }

        let timeout = targetState.networkTimeout
        let headers = [TargetConstants.HEADER_CONTENT_TYPE: TargetConstants.HEADER_CONTENT_TYPE_JSON]

        // https://developers.adobetarget.com/api/delivery-api/#tag/Delivery-API
        let request = NetworkRequest(url: url, httpMethod: .post, connectPayload: requestJson, httpHeaders: headers, connectTimeout: timeout, readTimeout: timeout)

        stopEvents()
        Log.debug(label: Target.LOG_TAG, "handleRawRequest - Sending Target request with url: \(url.absoluteString) and body: \(requestJson).")

        networkService.connectAsync(networkRequest: request) { connection in
            Log.debug(label: Target.LOG_TAG, "handleRawRequest - Target response is received with code: \(connection.responseCode ?? -1) and data: \(connection.responseString ?? "").")
            self.targetState.updateSessionTimestamp()
            self.processTargetRawResponse(event: event, isContentRequest: isContentRequest, connection: connection)
        }
        startEvents()
    }

    /// Processes the network response after the Target delivery API call for raw request.
    ///
    /// - Parameters:
    ///     - event: The Target request event which triggered this network call.
    ///     - connection: `NetworkService.HttpConnection` instance.
    private func processTargetRawResponse(event: Event, isContentRequest: Bool, connection: HttpConnection) {
        var error: String? = connection.error?.localizedDescription
        var responseData: [String: Any]?

        defer {
            if isContentRequest {
                dispatchTargetRawResponse(event: event, error: error, data: responseData)
            }
        }

        guard
            let data = connection.data,
            let responseDictAnyCodable = try? JSONDecoder().decode([String: AnyCodable].self, from: data),
            let responseDict = AnyCodable.toAnyDictionary(dictionary: responseDictAnyCodable)
        else {
            error = TargetError.ERROR_RESPONSE_PARSING_FAILED
            Log.debug(label: Target.LOG_TAG, "processTargetRawResponse - Target response parser initialization failed.")
            return
        }

        let response = TargetDeliveryResponse(responseJson: responseDict)

        if let connectionResponseCode = connection.responseCode, connectionResponseCode != 200 {
            error = response.errorMessage ?? connection.responseMessage ?? error
            Log.debug(label: Target.LOG_TAG, "processTargetRawResponse - Target raw execute request failed with response code: \(connectionResponseCode) and error: \(error ?? ""))")
            return
        }

        if let tntId = response.tntId { targetState.updateTntId(tntId) }
        if let edgeHost = response.edgeHost { targetState.updateEdgeHost(edgeHost) }
        createSharedState(data: targetState.generateSharedState(), event: event)

        responseData = response.responseJson
    }

    /// Dispatches the Target response content event for raw request.
    ///
    /// - Parameters:
    ///     - event: the Target raw request event.
    ///     - error: (optional) string indicating error when requesting content from Target.
    ///     - data: (optional) dictionary containing the response payload from Target for the raw execute or prefetch request.
    private func dispatchTargetRawResponse(event: Event, error: String?, data: [String: Any]?) {
        Log.trace(label: Target.LOG_TAG, "dispatchTargetRawResponse - Dispatching response event for Target raw request.")

        var eventData: [String: Any] = [:]
        if let data = data {
            eventData[TargetConstants.EventDataKeys.RESPONSE_DATA] = data
        } else {
            eventData[TargetConstants.EventDataKeys.RESPONSE_ERROR] = error ?? ""
        }

        let responseEvent = event.createResponseEvent(name: TargetConstants.EventName.TARGET_RAW_RESPONSE,
                                                      type: EventType.target,
                                                      source: EventSource.responseContent,
                                                      data: eventData)
        dispatch(event: responseEvent)
    }

    /// Dispatches the Target Response Content Event.
    /// - Parameters:
    ///     - content: the target content.
    ///     - data: the target data payload containing one or more of response tokens, analytics payload and click tracking analytics payload.
    ///     - pairId: the pairId of the associated target request content event.
    private func dispatchMboxContent(event: Event, content: String, data: [String: Any]?, responsePairId: String) {
        Log.trace(label: Target.LOG_TAG, "dispatchMboxContent - " + TargetError.ERROR_TARGET_EVENT_DISPATCH_MESSAGE)

        let responseEvent = Event(name: TargetConstants.EventName.TARGET_REQUEST_RESPONSE,
                                  type: EventType.target,
                                  source: EventSource.responseContent,
                                  data: [
                                      TargetConstants.EventDataKeys.TARGET_CONTENT: content,
                                      TargetConstants.EventDataKeys.TARGET_DATA_PAYLOAD: data as Any,
                                      TargetConstants.EventDataKeys.TARGET_RESPONSE_PAIR_ID: responsePairId,
                                      TargetConstants.EventDataKeys.TARGET_RESPONSE_EVENT_ID: event.id.uuidString,
                                  ])
        dispatch(event: responseEvent)
    }

    /// Checks if the cached mboxs contain the data for each of the `TargetRequest` in the input List.
    /// If a cached mbox exists, then dispatch the mbox content.
    ///
    private func processCachedTargetRequest(event: Event, batchRequests: [TargetRequest], timeStamp _: Int64) -> [TargetRequest] {
        var requestsToSend: [TargetRequest] = []
        for request in batchRequests {
            guard let cachedMbox = targetState.prefetchedMboxJsonDicts[request.name] else {
                Log.debug(label: Target.LOG_TAG, "processCachedTargetRequest - \(TargetError.ERROR_NO_CACHED_MBOX_FOUND) \(request.name)")
                requestsToSend.append(request)
                continue
            }
            Log.debug(label: Target.LOG_TAG, "processCachedTargetRequest - Cached mbox found for \(request.name) with data \(cachedMbox.description)")

            let (content, responseTokens) = extractMboxContentAndResponseTokens(mboxJson: cachedMbox)
            let analyticsPayload = getAnalyticsForTargetPayload(json: cachedMbox)
            let metrics = extractClickMetric(mboxJson: cachedMbox)

            // package analytics payload and response tokens to be returned in request callback
            let responsePayload = packageMboxResponsePayload(responseTokens: responseTokens, analyticsPayload: analyticsPayload, metricsAnalyticsPayload: metrics.analyticsPayload)

            dispatchMboxContent(event: event, content: content ?? request.defaultContent, data: responsePayload, responsePairId: request.responsePairId)
        }

        return requestsToSend
    }

    /// Return Mbox content and response tokens from mboxJson, if any.
    /// - Parameters:
    ///     - mboxJson: `[String: Any]` target response dictionary
    /// - Returns: tuple containg `String` mbox content and `Dictionary` containing response tokens, if any.
    private func extractMboxContentAndResponseTokens(mboxJson: [String: Any]) -> (content: String?, responseTokens: [String: String]?) {
        guard let optionsArray = mboxJson[TargetConstants.TargetJson.OPTIONS] as? [[String: Any?]?] else {
            Log.debug(label: Target.LOG_TAG, "extractMboxContent - unable to extract mbox contents, options array is nil")
            return (nil, nil)
        }

        var contentBuilder = ""
        var responseTokens: [String: String]?

        for option in optionsArray {
            responseTokens = option?[TargetConstants.TargetJson.Option.RESPONSE_TOKENS] as? [String: String]

            guard let content = option?[TargetConstants.TargetJson.Option.CONTENT] else {
                continue
            }

            guard let type = option?[TargetConstants.TargetJson.Option.TYPE] as? String, !type.isEmpty else {
                continue
            }

            if TargetConstants.TargetJson.HTML == type, let contentString = content as? String {
                contentBuilder.append(contentString)
            } else if TargetConstants.TargetJson.JSON == type, let contentDict = content as? [String: Any?] {
                guard let jsonData = try? JSONSerialization.data(withJSONObject: contentDict, options: .prettyPrinted) else {
                    continue
                }
                guard let jsonString = String(data: jsonData, encoding: .utf8) else { continue }
                contentBuilder.append(jsonString)
            }
        }

        return (contentBuilder, responseTokens)
    }

    /// Dispatches an Analytics Event containing the Analytics for Target (A4T) payload
    /// - Parameters:
    ///     - payload: analytics for target (a4t) payload
    private func dispatchAnalyticsForTargetRequest(payload: [String: String]?) {
        guard let payloadJson = payload, !payloadJson.isEmpty else {
            Log.debug(label: Target.LOG_TAG, "dispatchAnalyticsForTargetRequest - Failed to dispatch analytics. Payload is either null or empty")
            return
        }

        let eventData = [TargetConstants.EventDataKeys.Analytics.CONTEXT_DATA: payloadJson,
                         TargetConstants.EventDataKeys.Analytics.TRACK_ACTION: TargetConstants.A4T_ACTION_NAME,
                         TargetConstants.EventDataKeys.Analytics.TRACK_INTERNAL: true] as [String: Any]
        let event = Event(name: TargetConstants.EventName.ANALYTICS_FOR_TARGET_REQUEST_EVENT_NAME, type: EventType.analytics, source: EventSource.requestContent, data: eventData)
        MobileCore.dispatch(event: event)
    }

    /// Preprocesses the analytics for target (a4t) payload received in the Target response for Analytics consumption.
    /// - Returns: `Dictionary` containing a4t payload with keys in internal format.
    private func preprocessAnalyticsPayload(_ payload: [String: String], sessionId: String) -> [String: String] {
        var result: [String: String] = [:]

        for (k, v) in payload {
            result["&&\(k)"] = v
        }

        if !sessionId.isEmpty {
            result[TargetConstants.TargetJson.SESSION_ID] = sessionId
        }

        return result
    }

    /// Grabs the analytics for target (a4t) payload from the target response if available.
    /// - Parameters:
    ///     - json: dictionary containing a4t payload.
    /// - Returns: `Dictionary` containing a4t payload or nil.
    private func getAnalyticsForTargetPayload(json: [String: Any]) -> [String: String]? {
        guard let analyticsJson = json[TargetConstants.TargetJson.ANALYTICS] as? [String: Any] else {
            return nil
        }

        guard let payloadJson = analyticsJson[TargetConstants.TargetJson.ANALYTICS_PAYLOAD] as? [String: String] else {
            return nil
        }

        return payloadJson
    }

    /// Extracts click metric info from the Target response if available.
    /// - Parameters:
    ///     - mboxJson: Mbox dictionary.
    /// - Returns: tuple containing `String` click token and `Dictionary` containing click tracking analytics payload.
    private func extractClickMetric(mboxJson: [String: Any]) -> (token: String?, analyticsPayload: [String: String]?) {
        guard let metrics = mboxJson[TargetConstants.TargetJson.METRICS] as? [[String: Any]?] else {
            return (nil, nil)
        }

        for metricItem in metrics {
            guard
                let metric = metricItem,
                TargetConstants.TargetJson.MetricType.CLICK == metric[TargetConstants.TargetJson.Metric.TYPE] as? String,
                let token = metric[TargetConstants.TargetJson.Metric.EVENT_TOKEN] as? String,
                !token.isEmpty
            else {
                continue
            }

            let analyticsPayload = getAnalyticsForTargetPayload(json: metric)
            return (token, analyticsPayload)
        }

        return (nil, nil)
    }

    /// Packages response tokens and analytics payload returned in Target response.
    ///
    /// If click tracking is enabled for the mbox, analytics payload returned inside metrics for click is also added.
    /// - Parameters:
    ///     - responseTokens: dictionary containing response tokens.
    ///     - analyticsPayload: dictionary containing analytics for target (a4t) payload.
    ///     - metricsAnalyticsPayload: dictionary containing a4t payload for click metric.
    /// - Returns: `Dictionary` containing Target payload or nil.
    private func packageMboxResponsePayload(responseTokens: [String: String]?,
                                            analyticsPayload: [String: String]?,
                                            metricsAnalyticsPayload: [String: String]?)
    -> [String: Any]? {
        var responsePayload: [String: Any] = [:]

        if let responseTokens = responseTokens {
            responsePayload[TargetConstants.TargetResponse.RESPONSE_TOKENS] = responseTokens
        }

        if let analyticsPayload = analyticsPayload {
            responsePayload[TargetConstants.TargetResponse.ANALYTICS_PAYLOAD] = analyticsPayload
        }

        if let metricsAnalyticsPayload = metricsAnalyticsPayload {
            responsePayload[TargetConstants.TargetResponse.CLICK_METRIC_ANALYTICS_PAYLOAD] = metricsAnalyticsPayload
        }

        return responsePayload.isEmpty ? nil : responsePayload
    }
}
#endif
