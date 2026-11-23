// Ported from KaleidoPaintContentView.swift (KaleidoPaint, © 2026 Jeff Weeks, GPLv2+).
// Android port © 2026 Cinderblock Software, GPLv3+. See LICENSE.
package com.cinderblocksoftware.kaleidopaint

import android.content.SharedPreferences
import androidx.annotation.StringRes
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.cinderblocksoftware.kaleidopaint.geometry.WallpaperGroup

/** Which name, if any, the symmetry panel shows under each group's picture. */
enum class WallpaperGroupNotation(private val storedName: String, @StringRes val label: Int) {
    NONE("noNotation", R.string.notation_none),
    ORBIFOLD("orbifold", R.string.notation_orbifold),
    CRYSTALLOGRAPHIC("crystallographic", R.string.notation_crystallographic);

    fun nameOf(group: WallpaperGroup): String? =
        when (this) {
            NONE -> null
            ORBIFOLD -> group.orbifoldName
            CRYSTALLOGRAPHIC -> group.IUCName
        }

    fun save(preferences: SharedPreferences) =
        preferences.edit().putString(PREFERENCE_KEY, storedName).apply()

    companion object {
        // The original's UserDefaults key and default.
        private const val PREFERENCE_KEY = "wallpaper group notation"

        fun load(preferences: SharedPreferences): WallpaperGroupNotation =
            entries.firstOrNull { it.storedName == preferences.getString(PREFERENCE_KEY, null) }
                ?: ORBIFOLD
    }
}

/** The original NotationButton: a "Notation" label with a menu of the three choices. */
@Composable
internal fun NotationPicker(
    notation: WallpaperGroupNotation,
    onChange: (WallpaperGroupNotation) -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }
    Row(
        Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(stringResource(R.string.notation), style = MaterialTheme.typography.bodyMedium)
        Box {
            Text(
                stringResource(notation.label),
                color = EditorBlue,
                modifier = Modifier.clickable { expanded = true }.padding(vertical = 6.dp),
            )
            DropdownMenu(
                expanded = expanded,
                onDismissRequest = { expanded = false },
                containerColor = Color.White,
            ) {
                WallpaperGroupNotation.entries.forEach { choice ->
                    DropdownMenuItem(
                        text = { Text(stringResource(choice.label), color = EditorBlue) },
                        onClick = {
                            expanded = false
                            onChange(choice)
                        },
                    )
                }
            }
        }
    }
}
