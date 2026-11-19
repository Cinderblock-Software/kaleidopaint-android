// Android port © 2026 Cinderblock Software, GPLv3+. See LICENSE.
package com.cinderblocksoftware.kaleidopaint

import android.app.Instrumentation
import java.io.File

internal object PerformanceChecks {
    fun run(test: Instrumentation): String {
        FillAcceleration.initialize(test.targetContext)
        val result = PerformanceBenchmark.run(test.targetContext)
        File(test.targetContext.filesDir, "performance.json").writeText(result.toString(2))
        return result.toString()
    }
}
