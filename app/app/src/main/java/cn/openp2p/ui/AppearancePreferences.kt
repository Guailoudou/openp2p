package cn.openp2p.ui

import android.content.Context
import android.content.res.ColorStateList
import android.graphics.Color
import android.os.Build
import android.widget.CompoundButton
import android.widget.Switch
import androidx.annotation.ColorRes
import androidx.appcompat.app.AppCompatDelegate
import androidx.appcompat.widget.SwitchCompat
import androidx.core.content.ContextCompat
import androidx.core.widget.CompoundButtonCompat
import cn.openp2p.R

object AppearancePreferences {
    const val MODE_SYSTEM = "system"
    const val MODE_DARK = "dark"
    const val MODE_LIGHT = "light"
    const val DEFAULT_COLOR = "#0A59F7"

    val colors = listOf("#0A59F7", "#7C3AED", "#009A9A", "#22A447", "#E76F00", "#D9485F")

    private const val PREFERENCES = "appearance"
    private const val KEY_COLOR = "theme_color"
    private const val KEY_MODE = "color_mode"

    fun color(context: Context): Int = Color.parseColor(
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .getString(KEY_COLOR, DEFAULT_COLOR) ?: DEFAULT_COLOR
    )

    fun colorHex(context: Context): String = String.format("#%06X", 0xFFFFFF and color(context))

    fun softColor(context: Context): Int = (color(context) and 0x00FFFFFF) or 0x1A000000

    fun mode(context: Context): String = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
        .getString(KEY_MODE, MODE_SYSTEM) ?: MODE_SYSTEM

    fun setColor(context: Context, value: String) {
        val normalized = if (colors.contains(value.uppercase())) value.uppercase() else DEFAULT_COLOR
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE).edit().putString(KEY_COLOR, normalized).apply()
    }

    fun setMode(context: Context, value: String) {
        val normalized = if (value in listOf(MODE_SYSTEM, MODE_DARK, MODE_LIGHT)) value else MODE_SYSTEM
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE).edit().putString(KEY_MODE, normalized).apply()
        applyMode(context)
    }

    fun applyMode(context: Context) {
        AppCompatDelegate.setDefaultNightMode(when (mode(context)) {
            MODE_DARK -> AppCompatDelegate.MODE_NIGHT_YES
            MODE_LIGHT -> AppCompatDelegate.MODE_NIGHT_NO
            else -> AppCompatDelegate.MODE_NIGHT_FOLLOW_SYSTEM
        })
    }

    fun resolve(context: Context, @ColorRes resource: Int): Int = when (resource) {
        R.color.brand_primary, R.color.state_info, R.color.harmony_blue -> color(context)
        R.color.brand_primary_dark -> darken(color(context))
        else -> ContextCompat.getColor(context, resource)
    }

    fun navigationTint(context: Context): ColorStateList = ColorStateList(
        arrayOf(intArrayOf(android.R.attr.state_checked), intArrayOf()),
        intArrayOf(color(context), ContextCompat.getColor(context, R.color.text_secondary))
    )

    fun tint(button: CompoundButton) {
        val context = button.context
        val tint = ColorStateList(
            arrayOf(intArrayOf(android.R.attr.state_checked), intArrayOf()),
            intArrayOf(color(context), ContextCompat.getColor(context, R.color.text_secondary))
        )
        CompoundButtonCompat.setButtonTintList(button, tint)
        if (button is Switch && Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            button.thumbTintList = tint
            button.trackTintList = ColorStateList.valueOf(softColor(context))
        }
        if (button is SwitchCompat) {
            button.thumbTintList = tint
            button.trackTintList = ColorStateList.valueOf(softColor(context))
        }
    }

    private fun darken(value: Int): Int = Color.rgb(
        (Color.red(value) * 0.8f).toInt(),
        (Color.green(value) * 0.8f).toInt(),
        (Color.blue(value) * 0.8f).toInt()
    )
}
