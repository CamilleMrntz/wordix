package com.example.wordix

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.graphics.Typeface
import android.text.SpannableString
import android.text.Spanned
import android.text.style.StyleSpan
import android.util.TypedValue
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import androidx.core.content.ContextCompat

class WordOfDayRemoteViewsFactory(
    private val context: Context,
    intent: Intent,
) : RemoteViewsService.RemoteViewsFactory {

    private val appWidgetId = intent.getIntExtra(
        AppWidgetManager.EXTRA_APPWIDGET_ID,
        AppWidgetManager.INVALID_APPWIDGET_ID,
    )

    private val slot = intent.getStringExtra("slot") ?: WordWidgetUpdates.SLOT_EN

    private var rows: List<Row> = emptyList()

    override fun onCreate() {}

    override fun onDataSetChanged() {
        if (appWidgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
            rows = listOf(Row(KIND_DEF, a = ""))
            return
        }
        val prefs = context.getSharedPreferences("WordixWidgetPrefs", Context.MODE_PRIVATE)
        val word = WordWidgetUpdates.readWord(prefs, slot)
        val pos = WordWidgetUpdates.readPartOfSpeech(prefs, slot)
        val defKey = WordWidgetUpdates.prefsDefKey(slot)
        var definition = prefs.getString(defKey, null)
        if (definition == null && slot == WordWidgetUpdates.SLOT_EN) {
            definition = prefs.getString("definition", null)
        }
        definition = definition ?: ""
        val flag = context.getString(
            if (slot == WordWidgetUpdates.SLOT_ES) R.string.widget_flag_es else R.string.widget_flag_en,
        )
        val defLines = splitDefinitionIntoLines(definition, maxLineLen = 96, maxItems = 500)

        rows = buildList {
            add(Row(KIND_WORD, flag, word))
            if (pos.isNotBlank()) {
                add(Row(KIND_POS, a = pos))
            }
            if (defLines.isEmpty() || (defLines.size == 1 && defLines[0].isEmpty())) {
                add(Row(KIND_DEF, a = ""))
            } else {
                for (line in defLines) {
                    add(Row(KIND_DEF, a = line))
                }
            }
        }
    }

    override fun onDestroy() {}

    override fun getCount(): Int = rows.size.coerceAtLeast(1)

    override fun getViewAt(position: Int): RemoteViews {
        val fillIn = Intent()
        val row = rows.getOrNull(position) ?: Row(KIND_DEF, a = "")
        val views = RemoteViews(context.packageName, R.layout.word_of_day_widget_item)
        when (row.kind) {
            KIND_WORD -> {
                val line = "${row.a}\u00A0${row.b}"
                val s = SpannableString(line)
                s.setSpan(StyleSpan(Typeface.BOLD), 0, s.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                views.setTextViewText(R.id.widget_item_text, s)
                views.setTextViewTextSize(R.id.widget_item_text, TypedValue.COMPLEX_UNIT_SP, 18f)
                views.setTextColor(
                    R.id.widget_item_text,
                    ContextCompat.getColor(context, R.color.widget_text_primary),
                )
            }
            KIND_POS -> {
                val s = SpannableString(row.a)
                s.setSpan(StyleSpan(Typeface.ITALIC), 0, s.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                views.setTextViewText(R.id.widget_item_text, s)
                views.setTextViewTextSize(R.id.widget_item_text, TypedValue.COMPLEX_UNIT_SP, 12f)
                views.setTextColor(
                    R.id.widget_item_text,
                    ContextCompat.getColor(context, R.color.widget_text_secondary),
                )
            }
            else -> {
                views.setTextViewText(R.id.widget_item_text, row.a)
                views.setTextViewTextSize(R.id.widget_item_text, TypedValue.COMPLEX_UNIT_SP, 13f)
                views.setTextColor(
                    R.id.widget_item_text,
                    ContextCompat.getColor(context, R.color.widget_text_body),
                )
            }
        }
        views.setOnClickFillInIntent(R.id.widget_item_text, fillIn)
        return views
    }

    override fun getLoadingView(): RemoteViews? = null

    override fun getViewTypeCount(): Int = 1

    override fun getItemId(position: Int): Long = position.toLong()

    override fun hasStableIds(): Boolean = true

    private data class Row(val kind: Int, val a: String, val b: String = "")

    private companion object {
        const val KIND_WORD = 0
        const val KIND_POS = 1
        const val KIND_DEF = 2
    }
}

internal fun splitDefinitionIntoLines(text: String, maxLineLen: Int, maxItems: Int): List<String> {
    val cleaned = text.replace("\r\n", "\n").trim()
    if (cleaned.isEmpty()) {
        return listOf("")
    }
    val out = mutableListOf<String>()
    for (paragraph in cleaned.split("\n")) {
        val p = paragraph.trim()
        if (p.isEmpty()) {
            if (out.isNotEmpty()) {
                out.add("")
            }
            continue
        }
        var remaining = p
        while (remaining.isNotEmpty() && out.size < maxItems) {
            if (remaining.length <= maxLineLen) {
                out.add(remaining)
                break
            }
            val window = remaining.substring(0, maxLineLen)
            val lastSpace = window.lastIndexOf(' ')
            val cut = if (lastSpace > maxLineLen / 3) lastSpace else maxLineLen
            out.add(remaining.substring(0, cut).trimEnd())
            remaining = remaining.substring(cut).trimStart()
        }
    }
    return if (out.isEmpty()) listOf("") else out
}
