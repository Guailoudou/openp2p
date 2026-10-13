package cn.openp2p.ui

import android.content.Context
import android.content.res.ColorStateList
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.text.InputType
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.core.widget.NestedScrollView
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.RadioButton
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
import kotlin.math.abs

fun Context.punchPriorityOptions() = listOf(
    getString(R.string.priority_default), getString(R.string.priority_tcp_first),
    getString(R.string.priority_tcp_only), getString(R.string.priority_udp_only)
)

enum class AppStatus(@ColorRes val color: Int) {
    INFO(R.color.state_info), SUCCESS(R.color.state_success), WARNING(R.color.state_warning),
    ERROR(R.color.state_error), NEUTRAL(R.color.text_secondary)
}

fun Context.dp(value: Int) = (value * resources.displayMetrics.density).toInt()
fun Context.color(@ColorRes value: Int) = AppearancePreferences.resolve(this, value)

fun Context.centered(view: View, maxWidthDp: Int = 1240, fillHeight: Boolean = false): FrameLayout = FrameLayout(this).apply {
    val screenWidth = resources.configuration.screenWidthDp
    val contentWidth = if (maxWidthDp == 1240) when {
        screenWidth >= 1600 -> screenWidth * 2 / 3
        screenWidth >= 840 -> screenWidth * 5 / 6
        else -> screenWidth
    } else minOf(screenWidth, maxWidthDp)
    val childWidth = dp(contentWidth)
    addView(view, FrameLayout.LayoutParams(
        childWidth,
        if (fillHeight) ViewGroup.LayoutParams.MATCH_PARENT else ViewGroup.LayoutParams.WRAP_CONTENT,
        Gravity.TOP or Gravity.CENTER_HORIZONTAL
    ))
}

fun Context.page(
    title: String,
    actionIcon: Int? = null,
    actionDescription: String? = null,
    subtitle: String = "",
    scrollHeader: Boolean = true,
    onAction: (() -> Unit)? = null
): Pair<LinearLayout, LinearLayout> {
    val root = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        setBackgroundColor(color(R.color.surface_page))
    }
    val header = LinearLayout(this).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        setPadding(
            resources.getDimensionPixelSize(R.dimen.page_horizontal_margin),
            resources.getDimensionPixelSize(R.dimen.page_vertical_margin),
            resources.getDimensionPixelSize(R.dimen.page_horizontal_margin),
            dp(12)
        )
        val heading = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL }
        heading.addView(TextView(context).apply {
            text = title
            textSize = 30f
            setTextColor(color(R.color.text_primary))
            setTypeface(typeface, Typeface.BOLD)
        })
        if (subtitle.isNotEmpty()) heading.addView(TextView(context).apply {
            text = subtitle
            textSize = 14f
            setTextColor(color(R.color.text_secondary))
            setPadding(0, dp(6), 0, dp(4))
        })
        addView(heading, LinearLayout.LayoutParams(0, -2, 1f))
        if (actionIcon != null && onAction != null) addView(MaterialButton(context).apply {
            minWidth = dp(48)
            minimumWidth = dp(48)
            minHeight = dp(48)
            icon = ContextCompat.getDrawable(context, actionIcon)
            iconSize = dp(22)
            iconPadding = 0
            iconGravity = MaterialButton.ICON_GRAVITY_TEXT_START
            setPadding(0, 0, 0, 0)
            iconTint = ColorStateList.valueOf(color(R.color.text_primary))
            contentDescription = actionDescription
            cornerRadius = dp(24)
            backgroundTintList = ColorStateList.valueOf(color(R.color.surface_card))
            setOnClickListener { onAction() }
        }, LinearLayout.LayoutParams(dp(48), dp(48)))
    }
    if (!scrollHeader) root.addView(centered(header))
    val body = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(
            resources.getDimensionPixelSize(R.dimen.page_horizontal_margin), dp(4),
            resources.getDimensionPixelSize(R.dimen.page_horizontal_margin), dp(128)
        )
    }
    val scrollContent = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        if (scrollHeader) addView(header)
        addView(body)
    }
    val centered = centered(scrollContent)
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
    maxCardElevation = 0f
    strokeWidth = 0
    setCardBackgroundColor(color(R.color.surface_card))
    isFocusable = true
    addView(LinearLayout(context).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(dp(20), dp(20), dp(20), dp(20))
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
    textSize = 13f
    gravity = Gravity.CENTER
    setTextColor(color(status.color))
    setPadding(dp(4), dp(4), dp(4), dp(4))
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
        boxBackgroundMode = TextInputLayout.BOX_BACKGROUND_FILLED
        boxBackgroundColor = context.color(R.color.surface_subtle)
        setBoxCornerRadii(context.dp(14).toFloat(), context.dp(14).toFloat(), context.dp(14).toFloat(), context.dp(14).toFloat())
        helperText = helper
        isHintAnimationEnabled = true
        boxStrokeColor = context.color(R.color.brand_primary)
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
    edit.addTextChangedListener(object : android.text.TextWatcher {
        override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) = Unit
        override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) { layout.error = null }
        override fun afterTextChanged(s: android.text.Editable?) = Unit
    })
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
    it.cornerRadius = context.dp(14)
    it.minHeight = context.dp(48)
    if (status == AppStatus.INFO) {
        it.setTextColor(context.color(R.color.brand_on_primary))
        it.backgroundTintList = ColorStateList.valueOf(context.color(R.color.brand_primary))
    } else {
        it.setTextColor(context.color(if (status == AppStatus.NEUTRAL) R.color.brand_primary else status.color))
        it.backgroundTintList = ColorStateList.valueOf(
            if (status == AppStatus.ERROR) android.graphics.Color.TRANSPARENT else AppearancePreferences.softColor(context)
        )
        it.strokeWidth = 0
    }
    it.setOnClickListener { onClick() }
    addView(it, LinearLayout.LayoutParams(-1, context.dp(48)).apply { topMargin = context.dp(8) })
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

fun Context.bottomSheet(title: String, large: Boolean = false, content: LinearLayout.(BottomSheetDialog) -> Unit): BottomSheetDialog {
    val dialog = BottomSheetDialog(this)
    dialog.window?.setSoftInputMode(android.view.WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
    val scroll = NestedScrollView(this).apply {
        isFillViewport = true
    }
    val body = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        setBackgroundColor(color(R.color.surface_card))
        setPadding(dp(20), dp(16), dp(20), dp(32))
        addView(View(context).apply {
            background = GradientDrawable().apply {
                setColor(color(R.color.border_default)); cornerRadius = dp(2).toFloat()
            }
        }, LinearLayout.LayoutParams(dp(36), dp(4)).apply { gravity = Gravity.CENTER_HORIZONTAL; bottomMargin = dp(16) })
        label(title).apply { textSize = 22f; setTypeface(typeface, Typeface.BOLD) }
        content(dialog)
    }
    scroll.addView(centered(body, 760))
    dialog.setContentView(scroll)
    dialog.setOnShowListener {
        dialog.findViewById<View>(com.google.android.material.R.id.design_bottom_sheet)?.let { sheet ->
            sheet.setBackgroundColor(color(R.color.surface_card))
            androidx.core.view.ViewCompat.setElevation(sheet, 0f)
            sheet.layoutParams.height = (resources.displayMetrics.heightPixels * if (large) 0.9f else 0.6f).toInt()
            BottomSheetBehavior.from(sheet).apply {
                state = BottomSheetBehavior.STATE_EXPANDED
                skipCollapsed = true
            }
            sheet.requestLayout()
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
    val picker = android.widget.NumberPicker(this).apply {
        minValue = 0
        maxValue = values.lastIndex
        displayedValues = values.toTypedArray()
        value = selected.coerceIn(0, values.lastIndex)
        wrapSelectorWheel = false
        descendantFocusability = ViewGroup.FOCUS_BLOCK_DESCENDANTS
        contentDescription = title
    }
    val dialog = AlertDialog.Builder(this).setTitle(title).setView(picker)
        .setNegativeButton(R.string.cancel, null).setPositiveButton(R.string.confirm) { _, _ -> chosen(picker.value) }.create()
    dialog.setOnShowListener {
        dialog.getButton(AlertDialog.BUTTON_POSITIVE).setTextColor(AppearancePreferences.color(this))
        dialog.getButton(AlertDialog.BUTTON_NEGATIVE).setTextColor(AppearancePreferences.color(this))
    }
    dialog.show()
}

fun LinearLayout.selector(title: String, values: List<String>, selected: Int, chosen: (Int) -> Unit) {
    label(title, true)
    addView(android.widget.Spinner(context).apply {
        contentDescription = title
        minimumHeight = context.dp(48)
        adapter = android.widget.ArrayAdapter(context, android.R.layout.simple_spinner_dropdown_item, values)
        setSelection(selected.coerceIn(0, values.lastIndex))
        onItemSelectedListener = object : android.widget.AdapterView.OnItemSelectedListener {
            override fun onNothingSelected(parent: android.widget.AdapterView<*>?) = Unit
            override fun onItemSelected(parent: android.widget.AdapterView<*>?, view: View?, position: Int, id: Long) = chosen(position)
        }
    }, LinearLayout.LayoutParams(-1, -2))
}

fun View.snack(message: String, duration: Int = Snackbar.LENGTH_SHORT) = Snackbar.make(this, message, duration).show()
fun View.toast(message: String) = Toast.makeText(context, message, Toast.LENGTH_SHORT).show()

class SwipeActionLayout(context: Context) : FrameLayout(context) {
    private val touchSlop = ViewConfiguration.get(context).scaledTouchSlop
    private lateinit var foreground: View
    private lateinit var actions: View
    private var startActions: View? = null
    private var downX = 0f
    private var downY = 0f
    private var startTranslation = 0f
    private var dragging = false
    private var horizontalSwipeStateChanged: ((Boolean) -> Unit)? = null

    fun setOnHorizontalSwipeStateChanged(listener: (Boolean) -> Unit) {
        horizontalSwipeStateChanged = listener
    }

    private fun setDragging(value: Boolean) {
        if (dragging == value) return
        dragging = value
        horizontalSwipeStateChanged?.invoke(value)
    }

    fun setViews(content: View, actionView: View, startActionView: View? = null) {
        removeAllViews()
        foreground = content
        actions = actionView
        startActions = startActionView
        addView(actionView, LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.MATCH_PARENT, Gravity.END))
        startActionView?.let { addView(it, LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.MATCH_PARENT, Gravity.START)) }
        addView(content, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT))
    }

    override fun onInterceptTouchEvent(event: MotionEvent): Boolean {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                downX = event.x
                downY = event.y
                startTranslation = if (::foreground.isInitialized) foreground.translationX else 0f
                setDragging(false)
                parent?.requestDisallowInterceptTouchEvent(true)
            }
            MotionEvent.ACTION_MOVE -> {
                val dx = event.x - downX
                val dy = event.y - downY
                if (abs(dy) > touchSlop && abs(dy) >= abs(dx)) parent?.requestDisallowInterceptTouchEvent(false)
                if (abs(dx) > touchSlop && abs(dx) > abs(dy)) {
                    setDragging(true)
                    parent?.requestDisallowInterceptTouchEvent(true)
                    return true
                }
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> parent?.requestDisallowInterceptTouchEvent(false)
        }
        return super.onInterceptTouchEvent(event)
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (!::foreground.isInitialized || !::actions.isInitialized) return false
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                downX = event.x
                downY = event.y
                startTranslation = foreground.translationX
                return true
            }
            MotionEvent.ACTION_MOVE -> {
                val dx = event.x - downX
                val dy = event.y - downY
                if (!dragging && abs(dx) > touchSlop && abs(dx) > abs(dy)) setDragging(true)
                if (dragging) {
                    val width = actions.width.toFloat().coerceAtLeast(0f)
                    foreground.translationX = (startTranslation + dx).coerceIn(-width, startActions?.width?.toFloat() ?: 0f)
                    return true
                }
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                if (dragging) {
                    val width = actions.width.toFloat().coerceAtLeast(0f)
                    val startWidth = startActions?.width?.toFloat() ?: 0f
                    val target = when {
                        event.actionMasked == MotionEvent.ACTION_CANCEL -> 0f
                        foreground.translationX <= -width / 3f -> -width
                        startWidth > 0 && foreground.translationX >= startWidth / 3f -> startWidth
                        else -> 0f
                    }
                    foreground.animate().translationX(target).setDuration(160).start()
                    setDragging(false)
                    parent?.requestDisallowInterceptTouchEvent(false)
                    return true
                }
            }
        }
        return super.onTouchEvent(event)
    }
}

fun Context.swipeActions(
    content: View,
    actions: View,
    startActions: View? = null,
    onHorizontalSwipeStateChanged: (Boolean) -> Unit = {}
): SwipeActionLayout = SwipeActionLayout(this).apply {
    setViews(content, actions, startActions)
    setOnHorizontalSwipeStateChanged(onHorizontalSwipeStateChanged)
}
