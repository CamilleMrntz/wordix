package com.example.wordix

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import android.widget.RemoteViewsService

class WordOfDayRemoteViewsFactory(
    private val context: Context,
    intent: Intent,
) : RemoteViewsService.RemoteViewsFactory {

    private val appWidgetId = intent.getIntExtra(
        AppWidgetManager.EXTRA_APPWIDGET_ID,
        AppWidgetManager.INVALID_APPWIDGET_ID,
    )

    private val slot = intent.getStringExtra("slot") ?: WordWidgetUpdates.SLOT_EN

    private var lines: List<String> = emptyList()

    override fun onCreate() {}

    override fun onDataSetChanged() {
        if (appWidgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
            lines = listOf("")
            return
        }
        val prefs = context.getSharedPreferences("WordixWidgetPrefs", Context.MODE_PRIVATE)
        val defKey = WordWidgetUpdates.prefsDefKey(slot)
        var definition = prefs.getString(defKey, null)
        if (definition == null && slot == WordWidgetUpdates.SLOT_EN) {
            definition = prefs.getString("definition", null)
        }
        definition = definition ?: ""
        lines = splitDefinitionIntoLines(definition, maxLineLen = 96, maxItems = 500)
    }

    override fun onDestroy() {}

    override fun getCount(): Int = lines.size.coerceAtLeast(1)

    override fun getViewAt(position: Int): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.word_of_day_widget_item)
        val text = lines.getOrElse(position) { "" }
        views.setTextViewText(R.id.widget_item_text, text)
        val fillIn = Intent()
        views.setOnClickFillInIntent(R.id.widget_item_text, fillIn)
        return views
    }

    override fun getLoadingView(): RemoteViews? = null

    override fun getViewTypeCount(): Int = 1

    override fun getItemId(position: Int): Long = position.toLong()

    override fun hasStableIds(): Boolean = true
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
