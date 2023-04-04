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

@objc public extension Target {
    /// true if the response content event listener is already registered, false otherwise
    #if DEBUG
        static var isResponseListenerRegister: Bool = false
    #else
        private static var isResponseListenerRegister: Bool = false
    #endif

    /// `Dictionary` to keep track of pending target request
    @nonobjc
    private static var pendingTargetRequest: ThreadSafeDictionary<String, TargetRequest> = ThreadSafeDictionary()

    /// Prefetch multiple Target mboxes simultaneously.
    ///
    /// Executes a prefetch request to your configured Target server with the TargetPrefetchObject list provided
    /// in the prefetchObjectArray parameter. This prefetch request will use the provided parameters for all of
    /// the prefetches made in this request. The callback will be executed when the prefetch has been completed, returning
    /// an error object, nil if the prefetch was successful or error description if the prefetch was unsuccessful.
    /// The prefetched mboxes are cached in memory for the current application session and returned when requested.
    /// - Parameters:
    ///   - prefetchArray: an array of AEPTargetPrefetch objects representing the desired mboxes to prefetch
    ///   - targetParameters: a TargetParameters object containing parameters for all the mboxes in the request array
    ///   - completion: the callback `closure` which will be called after the prefetch is complete.  The parameter in the callback will be nil if the prefetch completed successfully, or will contain error message otherwise
    @objc(prefetchContent:withParameters:callback:)
    static func prefetchContent(_ prefetchArray: [TargetPrefetch], with targetParameters: TargetParameters? = nil, _ completion: ((Error?) -> Void)?) {
        let completion = completion ?? { _ in }

        guard !prefetchArray.isEmpty else {
            Log.error(label: Target.LOG_TAG, "Failed to prefetch Target request (the provided request list for mboxes is empty or nil)")
            completion(TargetError(message: TargetError.ERROR_EMPTY_PREFETCH_LIST))
            return
        }
        var prefetchDataArray = [[String: Any]]()
        for prefetch in prefetchArray {
            if let dict = prefetch.asDictionary() {
                prefetchDataArray.append(dict)

            } else {
                Log.error(label: Target.LOG_TAG, "Failed to prefetch Target request (the provided prefetch object can't be converted to [String: Any] dictionary), prefetch => \(prefetch)")
                completion(TargetError(message: TargetError.ERROR_INVALID_REQUEST))
                return
            }
        }

        var eventData: [String: Any] = [TargetConstants.EventDataKeys.PREFETCH: prefetchDataArray]
        if let targetParametersDict = targetParameters?.asDictionary() {
            eventData[TargetConstants.EventDataKeys.TARGET_PARAMETERS] = targetParametersDict
        }

        let event = Event(name: TargetConstants.EventName.PREFETCH_REQUESTS, type: EventType.target, source: EventSource.requestContent, data: eventData)

        MobileCore.dispatch(event: event) { responseEvent in
            guard let responseEvent = responseEvent else {
                completion(TargetError(message: TargetError.ERROR_TIMEOUT))
                return
            }
            if let errorMessage = responseEvent.data?[TargetConstants.EventDataKeys.PREFETCH_ERROR] as? String {
                completion(TargetError(message: errorMessage))
                return
            }
            completion(.none)
        }
    }

    /// Retrieves content for multiple Target mbox locations at once.
    /// Executes a batch request to your configured Target server for multiple mbox locations. Any prefetched content
    /// which matches a given mbox location is returned and not included in the batch request to the Target server.
    /// Each object in the array contains a callback function, which will be invoked when content is available for
    /// its given mbox location.
    /// - Parameters:
    ///   - requestArray:  An array of AEPTargetRequestObject objects to retrieve content
    ///   - targetParameters: a TargetParameters object containing parameters for all locations in the requests array
    @objc(retrieveLocationContent:withParameters:)
    static func retrieveLocationContent(_ requestArray: [TargetRequest], with targetParameters: TargetParameters? = nil) {
        if requestArray.isEmpty {
            Log.error(label: Target.LOG_TAG, "Failed to retrieve location content target request \(TargetError.ERROR_NULL_EMPTY_REQUEST_MESSAGE)")
            return
        }

        var targetRequestsArray = [[String: Any]]()
        var tempIdToRequest: [String: TargetRequest] = [:]

        for request in requestArray {
            if request.name.isEmpty {
                // If the callback is present call with default content
                if let callback = request.contentCallback {
                    callback(request.defaultContent)
                } else if let callback = request.contentWithDataCallback {
                    callback(request.defaultContent, nil)
                }
                Log.debug(label: Target.LOG_TAG, "TargetRequest removed because mboxName is empty.")
                continue
            }

            guard let requestDictionary = request.asDictionary() else {
                Log.error(label: Target.LOG_TAG, "Failed to convert Target request to [String: Any] dictionary), prefetch => \(String(describing: request))")
                continue
            }

            tempIdToRequest[request.responsePairId] = request

            targetRequestsArray.append(requestDictionary)
        }

        if targetRequestsArray.isEmpty {
            Log.error(label: Target.LOG_TAG, "Failed to retrieve location content target request is empty")
            return
        }

        // Register the response content event listener
        registerResponseContentEventListener()

        var eventData = [TargetConstants.EventDataKeys.LOAD_REQUESTS: targetRequestsArray] as [String: Any]
        if let targetParametersDict = targetParameters?.asDictionary() {
            eventData[TargetConstants.EventDataKeys.TARGET_PARAMETERS] = targetParametersDict
        }
        let event = Event(name: TargetConstants.EventName.LOAD_REQUEST, type: EventType.target, source: EventSource.requestContent, data: eventData)

        // Update the pending target request dictionary with
        // key = `event.id-request.responsePairId`, value = `TargetRequest` object
        for (responsePairId, targetRequest) in tempIdToRequest {
            pendingTargetRequest["\(event.id)-\(responsePairId)"] = targetRequest
        }

        Log.trace(label: Target.LOG_TAG, "retrieveLocationContent - Event dispatched \(event.name), \(event.id.uuidString)")

        MobileCore.dispatch(event: event)
    }

    /// Sets the custom visitor ID for Target.
    /// Sets a custom ID to identify visitors (profiles). This ID is preserved between app upgrades,
    /// is saved and restored during the standard application backup process, and is removed at uninstall or
    /// when AEPTarget.resetExperience is called.
    /// - Parameter id: a string pointer containing the value of the third party id (custom visitor id)
    static func setThirdPartyId(_ id: String?) {
        let eventData = [TargetConstants.EventDataKeys.THIRD_PARTY_ID: id ?? ""]
        let event = Event(name: TargetConstants.EventName.SET_THIRD_PARTY_ID, type: EventType.target, source: EventSource.requestIdentity, data: eventData)
        MobileCore.dispatch(event: event)
    }

    /// Gets the custom visitor ID for Target
    /// This ID will be reset  when the `resetExperience()` API is called.
    /// - Parameter completion:  the callback `closure` will be invoked to return the thirdPartyId value or `nil` if no third-party ID is set
    static func getThirdPartyId(_ completion: @escaping (String?, Error?) -> Void) {
        let event = Event(name: TargetConstants.EventName.GET_THIRD_PARTY_ID, type: EventType.target, source: EventSource.requestIdentity, data: nil)
        MobileCore.dispatch(event: event) { responseEvent in
            guard let responseEvent = responseEvent else {
                let error = "Request to get third party id failed, \(TargetError.ERROR_TIMEOUT)"
                completion(nil, TargetError(message: error))
                Log.warning(label: Target.LOG_TAG, error)
                return
            }
            guard let eventData = responseEvent.data else {
                let error = "Unable to handle response, event data is nil."
                completion(nil, TargetError(message: error))
                Log.warning(label: Target.LOG_TAG, error)
                return
            }
            guard let thirdPartyId = eventData[TargetConstants.EventDataKeys.THIRD_PARTY_ID] as? String else {
                let error = "Unable to handle response, No third party id available."
                completion(nil, TargetError(message: error))
                Log.warning(label: Target.LOG_TAG, error)
                return
            }
            completion(thirdPartyId, nil)
        }
    }

    /// Sets the Target session identifier.
    ///
    /// The provided session ID is persisted in the SDK for a period defined by `target.sessionTimeout` configuration setting.
    /// If the provided session ID is nil or empty or if the privacy status is opted out, the SDK will remove the session ID value from the persistence.
    ///
    /// This ID is preserved between app upgrades, is saved and restored during the standard application backup process,
    /// and is removed at uninstall, upon privacy status update to opted out or when the AEPTarget.resetExperience API is called.
    ///
    /// - Parameter id: a string containing the value of the Target session ID to be set in the SDK.
    static func setSessionId(_ id: String?) {
        let eventData = [TargetConstants.EventDataKeys.TARGET_SESSION_ID: id ?? ""]
        let event = Event(name: TargetConstants.EventName.SET_SESSION_ID, type: EventType.target, source: EventSource.requestIdentity, data: eventData)
        MobileCore.dispatch(event: event)
    }

    /// Gets the Target session identifier.
    ///
    /// The session ID is generated locally in the SDK upon initial Target request and persisted for a period defined by `target.sessionTimeout` configuration setting.
    /// If the session timeout happens upon a subsequent Target request, a new session ID will be generated for use in the request and persisted in the SDK.
    ///
    /// - Parameter completion: the callback `closure` invoked with the current session ID, or `nil` if there was an error retrieving it.
    static func getSessionId(_ completion: @escaping (String?, Error?) -> Void) {
        let event = Event(name: TargetConstants.EventName.GET_SESSION_ID, type: EventType.target, source: EventSource.requestIdentity, data: nil)
        MobileCore.dispatch(event: event) { responseEvent in
            guard let responseEvent = responseEvent else {
                let error = "Request to get Target session ID failed with error, \(TargetError.ERROR_TIMEOUT)"
                completion(nil, TargetError(message: error))
                Log.warning(label: Target.LOG_TAG, error)
                return
            }
            guard let eventData = responseEvent.data else {
                let error = "Unable to handle response, event data is nil."
                completion(nil, TargetError(message: error))
                Log.warning(label: Target.LOG_TAG, error)
                return
            }
            guard let sessionId = eventData[TargetConstants.EventDataKeys.TARGET_SESSION_ID] as? String else {
                let error = "Unable to handle response, session ID is not available."
                completion(nil, TargetError(message: error))
                Log.warning(label: Target.LOG_TAG, error)
                return
            }
            completion(sessionId, nil)
        }
    }

    /// Sets the Target user identifier.
    ///
    /// The provided tnt ID is persisted in the SDK and attached to subsequent Target requests. It is used to
    /// derive the edge host value in the SDK, which is also persisted and used in future Target requests.
    ///
    /// If the provided tnt ID is nil or empty or if the privacy status is opted out, the SDK will remove the tnt ID and edge host values from the persistence.
    ///
    /// This ID is preserved between app upgrades, is saved and restored during the standard application backup process,
    /// and is removed at uninstall, upon privacy status update to opted out or when the AEPTarget.resetExperience API is called.
    ///
    /// - Parameter id: a string containing the value of the tnt ID to be set in the SDK.
    static func setTntId(_ id: String?) {
        let eventData = [TargetConstants.EventDataKeys.TNT_ID: id ?? ""]
        let event = Event(name: TargetConstants.EventName.SET_TNT_ID, type: EventType.target, source: EventSource.requestIdentity, data: eventData)
        MobileCore.dispatch(event: event)
    }

    /// Gets the Target user identifier.
    ///
    /// The tnt ID is returned in the network response from Target after a successful call to `prefetchContent` API or `retrieveLocationContent` API, which is then persisted in the SDK.
    /// The persisted tnt ID is used in subsequent Target requests until a different tnt ID is returned from Target, or a new tnt ID is set using `setTntId` API.
    ///
    /// - Parameter completion:  the callback `closure` invoked with the current tnt ID, or `nil` if there was an error retrieving it.
    static func getTntId(_ completion: @escaping (String?, Error?) -> Void) {
        let event = Event(name: TargetConstants.EventName.GET_TNT_ID, type: EventType.target, source: EventSource.requestIdentity, data: nil)
        MobileCore.dispatch(event: event) { responseEvent in
            guard let responseEvent = responseEvent else {
                let error = "Request to get tnt ID failed, \(TargetError.ERROR_TIMEOUT)"
                completion(nil, TargetError(message: error))
                Log.warning(label: Target.LOG_TAG, error)
                return
            }
            guard let eventData = responseEvent.data else {
                let error = "Unable to handle response, event data is nil."
                completion(nil, TargetError(message: error))
                Log.warning(label: Target.LOG_TAG, error)
                return
            }
            guard let tntId = eventData[TargetConstants.EventDataKeys.TNT_ID] as? String else {
                let error = "Unable to handle response, tnt ID is not available."
                completion(nil, TargetError(message: error))
                Log.warning(label: Target.LOG_TAG, error)
                return
            }
            completion(tntId, nil)
        }
    }

    /// Sets the Target preview restart deep link.
    /// Set the Target preview URL to be displayed when the preview mode is restarted.
    static func resetExperience() {
        let eventData = [TargetConstants.EventDataKeys.RESET_EXPERIENCE: true]
        let event = Event(name: TargetConstants.EventName.REQUEST_RESET, type: EventType.target, source: EventSource.requestReset, data: eventData)
        MobileCore.dispatch(event: event)
    }

    /// Clears prefetched mboxes.
    /// Clears the cached prefetched AEPTargetPrefetchObject array.
    static func clearPrefetchCache() {
        let eventData = [TargetConstants.EventDataKeys.CLEAR_PREFETCH_CACHE: true]
        let event = Event(name: TargetConstants.EventName.CLEAR_PREFETCH_CACHE, type: EventType.target, source: EventSource.requestReset, data: eventData)
        MobileCore.dispatch(event: event)
    }

    /// Sets the Target preview restart deep link.
    /// Set the Target preview URL to be displayed when the preview mode is restarted.
    /// - Parameter deeplink:  the URL which will be set for preview restart
    @objc(setPreviewRestartDeepLink:)
    static func setPreviewRestartDeepLink(_ deeplink: URL) {
        let eventData = [TargetConstants.EventDataKeys.PREVIEW_RESTART_DEEP_LINK: deeplink.absoluteString]
        let event = Event(name: TargetConstants.EventName.SET_PREVIEW_DEEPLINK, type: EventType.target, source: EventSource.requestContent, data: eventData)
        MobileCore.dispatch(event: event)
    }

    /// Sends a display notification to Target for given prefetched mboxes. This helps Target record location display events.
    /// - Parameters:
    ///   - names:  (required) an array of displayed location names
    ///   - targetParameters: for the displayed location
    @objc(displayedLocations:withTargetParameters:)
    static func displayedLocations(_ names: [String], targetParameters: TargetParameters? = nil) {
        if names.isEmpty {
            Log.error(label: LOG_TAG, "Failed to send display notification, List of Mbox names must not be empty.")
            return
        }

        var eventData = [TargetConstants.EventDataKeys.MBOX_NAMES: names, TargetConstants.EventDataKeys.IS_LOCATION_DISPLAYED: true] as [String: Any]

        if let targetParametersDict = targetParameters?.asDictionary() {
            eventData[TargetConstants.EventDataKeys.TARGET_PARAMETERS] = targetParametersDict
        }

        let event = Event(name: TargetConstants.EventName.LOCATIONS_DISPLAYED, type: EventType.target, source: EventSource.requestContent, data: eventData)
        MobileCore.dispatch(event: event)
    }

    /// Sends a click notification to Target if a click metric is defined for the provided location name.
    /// Click notification can be sent for a location provided a load request has been executed for that prefetched or regular mbox
    /// location before, indicating that the mbox was viewed. This request helps Target record the clicked event for the given location or mbox.
    ///
    /// - Parameters:
    ///   - name:  String value representing the name for location/mbox
    ///   - targetParameters:  a TargetParameters object containing parameters for the location clicked
    @objc(clickedLocation:withTargetParameters:)
    static func clickedLocation(_ name: String, targetParameters: TargetParameters? = nil) {
        if name.isEmpty {
            Log.error(label: LOG_TAG, "Failed to send click notification, Mbox name must not be empty or nil.")
            return
        }

        var eventData = [TargetConstants.EventDataKeys.MBOX_NAME: name, TargetConstants.EventDataKeys.IS_LOCATION_CLICKED: true] as [String: Any]

        if let targetParametersDict = targetParameters?.asDictionary() {
            eventData[TargetConstants.EventDataKeys.TARGET_PARAMETERS] = targetParametersDict
        }

        let event = Event(name: TargetConstants.EventName.LOCATION_CLICKED, type: EventType.target, source: EventSource.requestContent, data: eventData)
        MobileCore.dispatch(event: event)
    }

    /// Registers the response content event listener
    private static func registerResponseContentEventListener() {
        // Only register the listener once
        if !isResponseListenerRegister {
            MobileCore.registerEventListener(type: EventType.target, source: EventSource.responseContent, listener: handleResponseEvent(_:))
            isResponseListenerRegister = true
        }
    }

    /// Handles the response event with event name as `TargetConstants.EventName.TARGET_REQUEST_RESPONSE`
    /// - Parameters:
    ///     - event: Response content event with content and optional data payload
    private static func handleResponseEvent(_ event: Event) {
        if event.name != TargetConstants.EventName.TARGET_REQUEST_RESPONSE {
            return
        }

        guard let id = event.data?[TargetConstants.EventDataKeys.TARGET_RESPONSE_EVENT_ID] as? String,
              let responsePairId = event.data?[TargetConstants.EventDataKeys.TARGET_RESPONSE_PAIR_ID] as? String
        else {
            Log.error(label: LOG_TAG, "Missing response pair id for the target request in the response event")
            return
        }

        let searchId = "\(id)-\(responsePairId)"

        // Remove and use the target request from the map
        guard let targetRequest = pendingTargetRequest.removeValue(forKey: searchId) else {
            Log.error(label: LOG_TAG, "Missing target request for the \(searchId)")
            return
        }

        if let callback = targetRequest.contentCallback {
            let content = event.data?[TargetConstants.EventDataKeys.TARGET_CONTENT] as? String ?? targetRequest.defaultContent
            callback(content)
        } else if let callback = targetRequest.contentWithDataCallback {
            let content = event.data?[TargetConstants.EventDataKeys.TARGET_CONTENT] as? String ?? targetRequest.defaultContent
            let responsePayload = event.data?[TargetConstants.EventDataKeys.TARGET_DATA_PAYLOAD] as? [String: Any]

            callback(content, responsePayload)
        } else {
            Log.warning(label: LOG_TAG, "Missing callback for target request with pair id the \(responsePairId)")
            return
        }
    }

    /// Retrieves Target prefetch or execute response for mbox locations from the configured Target server.
    ///
    /// - Parameters:
    ///   - request: a dictionary containing prefetch or execute request data in the Target v1 delivery API request format.
    ///   - completion: the callback which will be invoked with the Target response data or error message after the request is completed.
    @objc(executeRawRequest:completion:)
    static func executeRawRequest(_ request: [String: Any], _ completion: @escaping ([String: Any]?, Error?) -> Void) {
        guard !request.isEmpty else {
            Log.warning(label: LOG_TAG, "Failed to execute raw Target request, the provided request dictionary is empty.")
            completion(nil, AEPError.invalidRequest)
            return
        }

        guard request.contains(where: { TargetConstants.EventDataKeys.EXECUTE == $0.key || TargetConstants.EventDataKeys.PREFETCH == $0.key }) else {
            Log.warning(label: LOG_TAG, "Failed to execute raw Target request, the provided request dictionary doesn't contain prefetch or execute data.")
            completion(nil, AEPError.invalidRequest)
            return
        }

        var eventData = request
        eventData[TargetConstants.EventDataKeys.IS_RAW_EVENT] = true

        let event = Event(name: TargetConstants.EventName.TARGET_RAW_REQUEST, type: EventType.target, source: EventSource.requestContent, data: eventData)

        MobileCore.dispatch(event: event) { responseEvent in
            guard let responseEvent = responseEvent else {
                completion(nil, TargetError(message: TargetError.ERROR_TIMEOUT))
                return
            }

            if let responseError = responseEvent.error {
                completion(nil, TargetError(message: responseError))
                return
            }

            guard let executeResponse = responseEvent.data?[TargetConstants.EventDataKeys.RESPONSE_DATA] as? [String: Any] else {
                let error = "Unable to handle response, raw response data is not available."
                completion(nil, TargetError(message: error))
                return
            }

            completion(executeResponse, nil)
        }
    }

    /// Sends notification request(s) to Target using the provided notification data in the request.
    ///
    /// The display or click event tokens, required for the Target notifications, can be retrieved from the response of a prior `executeRawRequest` API call.
    ///
    /// - Parameters:
    ///   - request: A dictionary containing notifications data in the Target v1 delivery API request format.
    @objc(sendRawNotifications:)
    static func sendRawNotifications(_ request: [String: Any]) {
        if request.isEmpty {
            Log.warning(label: LOG_TAG, "Failed to send raw Target notification, provided request dictionary is empty.")
            return
        }

        guard request.contains(where: { TargetConstants.EventDataKeys.NOTIFICATIONS == $0.key }) else {
            Log.warning(label: LOG_TAG, "Failed to execute raw Target request, the provided request dictionary doesn't contain notifications data.")
            return
        }

        var eventData = request
        eventData[TargetConstants.EventDataKeys.IS_RAW_EVENT] = true

        let event = Event(name: TargetConstants.EventName.TARGET_RAW_NOTIFICATIONS, type: EventType.target, source: EventSource.requestContent, data: eventData)
        MobileCore.dispatch(event: event)
    }
}
#endif
