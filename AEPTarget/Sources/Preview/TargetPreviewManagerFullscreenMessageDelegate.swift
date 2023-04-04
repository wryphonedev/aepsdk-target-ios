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

///
/// TargetPreviewManager FullscreenMessageDelegate meant to handle FullscreenMessage delegate calls
///
extension TargetPreviewManager: FullscreenMessageDelegate {
    func onShow(message _: FullscreenMessage) {
        Log.debug(label: LOG_TAG, "onShow - Target preview message was displayed")
    }

    func onDismiss(message _: FullscreenMessage) {
        Log.debug(label: LOG_TAG, "onDismiss - Target preview message was dismissed")
    }

    func onShowFailure() {
        Log.debug(label: LOG_TAG, "onShowFailure - Target preview message failed to be displayed")
    }

    func overrideUrlLoad(message: FullscreenMessage, url: String?) -> Bool {
        guard let url = URL(string: url ?? "") else {
            Log.warning(label: LOG_TAG, "overrideUrlLoad - URL string was invalid")
            return false
        }

        Log.debug(label: LOG_TAG, "overrideUrlLoad - Target preview override url received: \(url)")

        previewConfirmedWithUrl(url, message: message, previewLifecycleEventDispatcher: { event in
            MobileCore.dispatch(event: event)
        })

        return true
    }
}
#endif
