// Android port © 2026 Cinderblock Software, GPLv3+. See LICENSE.
package com.cinderblocksoftware.kaleidopaint

import android.app.Activity
import android.app.Instrumentation
import android.os.Bundle

/** Explicit suites via -e checks; connectedAndroidTest defaults to navigation smoke checks. */
class KaleidoPaintTestRunner : Instrumentation() {
    private var suite = "navigation"

    override fun onCreate(arguments: Bundle?) {
        suite = arguments?.getString("checks") ?: "navigation"
        super.onCreate(arguments)
        start()
    }

    override fun onStart() {
        try {
            val result =
                when (suite) {
                    "navigation" -> NavigationChecks(this).run()
                    "session" -> SessionChecks.run(this)
                    "review" -> ReviewChecks.run(this)
                    "gpu-fill" -> GpuFillChecks.run()
                    "gpu-render" -> GpuRenderChecks.run(this)
                    "export" -> {
                        ExportChecks.run(this)
                        "GLES preview, transparency, 4096 output and document preservation: PASS"
                    }
                    else -> error("Unknown test suite: $suite")
                }
            finish(Activity.RESULT_OK, Bundle().apply { putString("checks", result) })
        } catch (failure: Throwable) {
            finish(
                Activity.RESULT_CANCELED,
                Bundle().apply { putString("error", failure.stackTraceToString()) },
            )
        }
    }
}
