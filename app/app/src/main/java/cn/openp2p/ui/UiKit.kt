package cn.openp2p.ui

import android.content.Context
import android.content.res.ColorStateList
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.text.InputType
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import androidx.annotation.ColorRes
import androidx.annotation.StringRes
import androidx.appcompat.app.AlertDialog
import androidx.core.content.ContextCompat
import cn.openp2p.R
import com.google.android.material.bottomsheet.BottomSheetBehavior
import com.google.android.material.bottomsheet.BottomSheetDialog
import com.google.android.material.button.MaterialButton
import com.google.android.material.card.MaterialCardView
import com.google.android.material.snackbar.Snackbar
import com.google.android.material.textfield.TextInputEditText
import com.google.android.material.textfield.TextInputLayout

fun Context.punchPriorityOptions() = listOf(
    getString(R.string.priority_default), getString(R.string.priority_tcp_first),
    getString(R.string.priority_tcp_only), getString(R.string.priority_udp_only)
)

enum class AppStatus(@ColorRes val color: Int) {
    INFO(R.color.state_info), SUCCESS(R.color.state_success), WARNING(R.color.state_warning),
    ERROR(R.color.state_error), NEUTRAL(R.color.text_secondary)
}

fun Context.dp(value: Int) = (value * resources.displayMetrics.density).toInt()
fun Context.color(@ColorRes value: Int) = ContextCompat.getColor(this, value)

fun Context.page(title: String): Pair<LinearLayout, LinearLayout> {
    val root = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        setBackgroundColor(color(R.color.surface_page))
    }
    root.addView(TextView(this).apply {
        text = title
        textSize = 28f
        setTextColor(color(R.color.text_primary))
        setTypeface(typeface, Typeface.BOLD)
        setPadding(
            resources.getDimensionPixelSize(R.dimen.page_horizontal_margin),
            resources.getDimensionPixelSize(R.dimen.page_vertical_margin),
            resources.getDimensionPixelSize(R.dimen.page_horizontal_margin),
            dp(12)
        )
    })
    val body = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(
            resources.getDimensionPixelSize(R.dimen.page_horizontal_margin), dp(4),
            resources.getDimensionPixelSize(R.dimen.page_horizontal_margin), dp(32)
        )
    }
    val centered = FrameLayout(this).apply {
        addView(body, FrameLayout.LayoutParams(-1, -2, Gravity.TOP or Gravity.CENTER_HORIZONTAL).apply {
            val max = resources.getDimensionPixelSize(R.dimen.content_max_width)
            if (resources.displayMetrics.widthPixels > max) width = max
        })
    }
    root.addView(ScrollView(this).apply {
        isFillViewport = true
        clipToPadding = false
        addView(centered)
    }, LinearLayout.LayoutParams(-1, 0, 1f))
    return root to body
}

fun Context.card(content: LinearLayout.() -> Unit): MaterialCardView = MaterialCardView(this).apply {
    radius = resources.getDimension(R.dimen.card_radius)
    cardElevation = 0f
    strokeWidth = dp(1)
    strokeColor = color(R.color.border_default)
    setCardBackgroundColor(color(R.color.surface_card))
    isFocusable = true
    addView(LinearLayout(context).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(dp(16), dp(16), dp(16), dp(16))
        content()
    })
}

fun LinearLayout.sectionHeader(textValue: String, trailing: String? = null): TextView {
    val row = LinearLayout(context).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        setPadding(0, context.dp(20), 0, context.dp(10))
    }
    val title = TextView(context).apply {
        text = textValue
        textSize = 18f
        setTypeface(typeface, Typeface.BOLD)
        setTextColor(context.color(R.color.text_primary))
    }
    row.addView(title, LinearLayout.LayoutParams(0, -2, 1f))
    if (!trailing.isNullOrBlank()) row.addView(TextView(context).apply {
        text = trailing
        textSize = 13f
        setTextColor(context.color(R.color.text_secondary))
    })
    addView(row)
    return title
}

fun LinearLayout.label(textValue: String, secondary: Boolean = false): TextView = TextView(context).also {
    it.text = textValue
    it.textSize = if (secondary) 13f else 16f
    it.setTextColor(context.color(if (secondary) R.color.text_secondary else R.color.text_primary))
    addView(it, LinearLayout.LayoutParams(-1, -2).apply { bottomMargin = context.dp(if (secondary) 4 else 8) })
}

fun LinearLayout.keyValue(labelValue: String, value: String, mono: Boolean = false): LinearLayout {
    val row = LinearLayout(context).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        setPadding(0, context.dp(8), 0, context.dp(8))
    }
    row.addView(TextView(context).apply {
        text = labelValue
        textSize = 13f
        setTextColor(context.color(R.color.text_secondary))
    }, LinearLayout.LayoutParams(0, -2, 1f))
    row.addView(TextView(context).apply {
        text = value
        textSize = 14f
        gravity = Gravity.END
        setTextColor(context.color(R.color.text_primary))
        if (mono) typeface = Typeface.MONOSPACE
    }, LinearLayout.LayoutParams(0, -2, 2f))
    addView(row)
    return row
}

fun Context.statusChip(textValue: String, status: AppStatus): TextView = TextView(this).apply {
    text = textValue
    textSize = 12f
    gravity = Gravity.CENTER
    setTypeface(typeface, Typeface.BOLD)
    setTextColor(color(status.color))
    setPadding(dp(10), dp(5), dp(10), dp(5))
    minHeight = dp(32)
    background = GradientDrawable().apply {
        cornerRadius = dp(999).toFloat()
        setColor(color(R.color.surface_subtle))
        setStroke(dp(1), color(status.color))
    }
}

fun LinearLayout.field(
    label: String,
    value: String = "",
    numeric: Boolean = false,
    password: Boolean = false,
    helper: String? = null
): TextInputEditText {
    val layout = TextInputLayout(context).apply {
        hint = label
        boxBackgroundMode = TextInputLayout.BOX_BACKGROUND_OUTLINE
        helperText = helper
        isHintAnimationEnabled = true
        if (password) endIconMode = TextInputLayout.END_ICON_PASSWORD_TOGGLE
    }
    val edit = TextInputEditText(layout.context).apply {
        setText(value)
        inputType = when {
            password && numeric -> InputType.TYPE_CLASS_NUMBER or InputType.TYPE_NUMBER_VARIATION_PASSWORD
            password -> InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD
            numeric -> InputType.TYPE_CLASS_NUMBER
            else -> InputType.TYPE_CLASS_TEXT
        }
        minHeight = context.dp(48)
    }
    layout.addView(edit)
    addView(layout, LinearLayout.LayoutParams(-1, -2).apply { bottomMargin = context.dp(12) })
    return edit
}

fun TextInputEditText.showError(message: String?) {
    (parent?.parent as? TextInputLayout)?.error = message
}

fun LinearLayout.action(textValue: String, onClick: () -> Unit): MaterialButton = button(textValue, AppStatus.INFO, onClick)

fun LinearLayout.secondaryAction(textValue: String, onClick: () -> Unit): MaterialButton = button(textValue, AppStatus.NEUTRAL, onClick)

fun LinearLayout.destructiveAction(textValue: String, onClick: () -> Unit): MaterialButton = button(textValue, AppStatus.ERROR, onClick)

private fun LinearLayout.button(textValue: String, status: AppStatus, onClick: () -> Unit): MaterialButton = MaterialButton(context).also {
    it.text = textValue
    it.cornerRadius = context.dp(12)
    it.minHeight = context.dp(48)
    if (status == AppStatus.INFO) {
        it.setTextColor(context.color(R.color.brand_on_primary))
        it.backgroundTintList = ColorStateList.valueOf(context.color(R.color.brand_primary))
    } else {
        it.setTextColor(context.color(status.color))
        it.backgroundTintList = ColorStateList.valueOf(context.color(R.color.surface_subtle))
        it.strokeColor = ColorStateList.valueOf(context.color(status.color))
        it.strokeWidth = context.dp(1)
    }
    it.setOnClickListener { onClick() }
    addView(it, LinearLayout.LayoutParams(-1, context.dp(52)).apply { topMargin = context.dp(8) })
}

fun MaterialButton.setLoading(loading: Boolean, normalText: CharSequence, loadingText: CharSequence) {
    isEnabled = !loading
    text = if (loading) loadingText else normalText
}

fun LinearLayout.loadingState(message: String = context.getString(R.string.first_load)): LinearLayout {
    val state = LinearLayout(context).apply {
        orientation = LinearLayout.VERTICAL
        gravity = Gravity.CENTER
        setPadding(context.dp(24), context.dp(48), context.dp(24), context.dp(48))
        addView(ProgressBar(context))
        addView(TextView(context).apply {
            text = message
            textSize = 14f
            gravity = Gravity.CENTER
            setTextColor(context.color(R.color.text_secondary))
        }, LinearLayout.LayoutParams(-1, -2).apply { topMargin = context.dp(12) })
    }
    addView(state, LinearLayout.LayoutParams(-1, -2))
    return state
}

fun LinearLayout.emptyState(title: String, message: String, actionText: String? = null, action: (() -> Unit)? = null) {
    addView(context.card {
        label(title).apply { gravity = Gravity.CENTER; textSize = 18f }
        label(message, true).apply { gravity = Gravity.CENTER }
        if (actionText != null && action != null) secondaryAction(actionText, action)
    })
}

fun LinearLayout.errorState(message: String, retry: () -> Unit) {
    addView(context.card {
        label(context.getString(R.string.load_failed)).apply { setTextColor(context.color(R.color.state_error)) }
        label(message, true)
        secondaryAction(context.getString(R.string.retry), retry)
    })
}

fun Context.bottomSheet(title: String, content: LinearLayout.(BottomSheetDialog) -> Unit): BottomSheetDialog {
    val dialog = BottomSheetDialog(this)
    val scroll = ScrollView(this).apply { isFillViewport = true }
    val body = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        setBackgroundColor(color(R.color.surface_card))
        setPadding(dp(20), dp(16), dp(20), dp(32))
        label(title).apply { textSize = 22f; setTypeface(typeface, Typeface.BOLD) }
        content(dialog)
    }
    scroll.addView(body)
    dialog.setContentView(scroll)
    dialog.setOnShowListener {
        dialog.findViewById<View>(com.google.android.material.R.id.design_bottom_sheet)?.let { sheet ->
            sheet.setBackgroundColor(color(R.color.surface_card))
            BottomSheetBehavior.from(sheet).state = BottomSheetBehavior.STATE_EXPANDED
            sheet.layoutParams.height = ViewGroup.LayoutParams.MATCH_PARENT
        }
    }
    dialog.show()
    return dialog
}

fun Context.confirm(title: String, message: String, positive: String = getString(R.string.confirm), destructive: Boolean = false, action: () -> Unit) {
    val dialog = AlertDialog.Builder(this).setTitle(title).setMessage(message)
        .setNegativeButton(R.string.cancel, null).setPositiveButton(positive) { _, _ -> action() }.create()
    dialog.setOnShowListener {
        if (destructive) dialog.getButton(AlertDialog.BUTTON_POSITIVE).setTextColor(color(R.color.state_error))
    }
    dialog.show()
}

fun Context.wheelPicker(title: String, values: List<String>, selected: Int = 0, chosen: (Int) -> Unit) {
    if (values.isEmpty()) {
        Toast.makeText(this, R.string.no_options, Toast.LENGTH_SHORT).show()
        return
    }
    var choice = selected.coerceIn(0, values.lastIndex)
    AlertDialog.Builder(this).setTitle(title).setSingleChoiceItems(values.toTypedArray(), choice) { _, which -> choice = which }
        .setNegativeButton(R.string.cancel, null).setPositiveButton(R.string.confirm) { _, _ -> chosen(choice) }.show()
}

fun View.snack(message: String, duration: Int = Snackbar.LENGTH_SHORT) = Snackbar.make(this, message, duration).show()
fun View.toast(message: String) = Toast.makeText(context, message, Toast.LENGTH_SHORT).show()

fun String.maskSensitive(): String = replace(Regex("(?i)(token|password|authorization)([\\s:=]+)([^\\s,;]+)")) {
    "${it.groupValues[1]}${it.groupValues[2]}••••••••"
}
