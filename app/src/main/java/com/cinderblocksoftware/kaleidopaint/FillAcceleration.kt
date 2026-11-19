// Android port © 2026 Cinderblock Software, GPLv3+. See LICENSE.
package com.cinderblocksoftware.kaleidopaint

import android.content.Context
import androidx.compose.runtime.*

/** User override for comparisons; capability/failure fallback is per GL renderer. */
internal object FillAcceleration {
    var enabled by mutableStateOf(true)
        private set

    fun initialize(context: Context) {
        enabled =
            context
                .getSharedPreferences("rendering", Context.MODE_PRIVATE)
                .getBoolean("gpu-fill", true)
    }

    fun set(context: Context, value: Boolean) {
        enabled = value
        context
            .getSharedPreferences("rendering", Context.MODE_PRIVATE)
            .edit()
            .putBoolean("gpu-fill", value)
            .apply()
    }
}
