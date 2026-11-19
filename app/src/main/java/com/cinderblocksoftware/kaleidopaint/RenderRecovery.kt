// Android port © 2026 Cinderblock Software, GPLv3+. See LICENSE.
package com.cinderblocksoftware.kaleidopaint

/** Retry once per failure episode; only a successfully drawn frame ends the episode. */
internal class RenderRecovery {
    private var attempted = false

    fun requestRetry(): Boolean {
        if (attempted) return false
        attempted = true
        return true
    }

    fun healthyFrame() {
        attempted = false
    }
}
