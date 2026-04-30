package com.example.wordix

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.os.Build
import android.widget.RemoteViews

internal object WordWidgetUpdates {
    const val SLOT_EN = "en"
    const val SLOT_ES = "es"

    private const val LIST_URI_SCHEME = "wordix-widget-list"

    fun prefsWordKey(slot: String): String = if (slot == SLOT_ES) "word_es" else "word_en"

    fun prefsPosKey(slot: String): String = if (slot == SLOT_ES) "partOfSpeech_es" else "partOfSpeech_en"

    fun prefsDefKey(slot: String): String = if (slot == SLOT_ES) "definition_es" else "definition_en"

    fun readWord(prefs: SharedPreferences, slot: String): String {
        val k = prefsWordKey(slot)
        val v = prefs.getString(k, null)
        if (v != null) return v
        return if (slot == SLOT_EN) prefs.getString("word", null) ?: "Wordix" else "Wordix"
    }

    fun readPartOfSpeech(prefs: SharedPreferences, slot: String): String {
        val k = prefsPosKey(slot)
        val v = prefs.getString(k, null)
        if (v != null) return v
        return if (slot == SLOT_EN) prefs.getString("partOfSpeech", null) ?: "noun" else ""
    }

    fun update(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        slot: String,
    ) {
        val listPiFlags = PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                PendingIntent.FLAG_MUTABLE
            } else {
                0
            }
        for (appWidgetId in appWidgetIds) {
            val listTemplateIntent = PendingIntent.getActivity(
                context,
                1000 + appWidgetId,
                Intent(context, MainActivity::class.java),
                listPiFlags,
            )

            val views = RemoteViews(context.packageName, R.layout.word_of_day_widget)

            val svcIntent = Intent(context, WordOfDayWidgetService::class.java).apply {
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
                putExtra("slot", slot)
                data = Uri.parse("$LIST_URI_SCHEME://widget/$slot/$appWidgetId")
            }
            views.setRemoteAdapter(R.id.widget_definition_list, svcIntent)

            views.setPendingIntentTemplate(R.id.widget_definition_list, listTemplateIntent)

            appWidgetManager.updateAppWidget(appWidgetId, views)
            appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetId, R.id.widget_definition_list)
        }
    }
}
