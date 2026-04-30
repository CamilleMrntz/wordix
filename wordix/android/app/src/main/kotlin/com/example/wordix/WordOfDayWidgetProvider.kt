package com.example.wordix

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

class WordOfDayWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        updateWidgets(context, appWidgetManager, appWidgetIds)
    }

    companion object {
        fun updateWidgets(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetIds: IntArray
        ) {
            val prefs = context.getSharedPreferences("WordixWidgetPrefs", Context.MODE_PRIVATE)
            val word = prefs.getString("word", "Wordix") ?: "Wordix"
            val partOfSpeech = prefs.getString("partOfSpeech", "noun") ?: "noun"
            val definition = prefs.getString("definition", "Open the app to load the word of the day.") ?: "Open the app to load the word of the day."

            val launchIntent = Intent(context, MainActivity::class.java)
            val launchPendingIntent = PendingIntent.getActivity(
                context,
                0,
                launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            for (appWidgetId in appWidgetIds) {
                val views = RemoteViews(context.packageName, R.layout.word_of_day_widget)
                views.setTextViewText(R.id.widget_word, word)
                views.setTextViewText(R.id.widget_part_of_speech, partOfSpeech)
                views.setTextViewText(R.id.widget_definition, definition)
                views.setOnClickPendingIntent(R.id.widget_root, launchPendingIntent)
                appWidgetManager.updateAppWidget(appWidgetId, views)
            }
        }

        fun requestUpdateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val componentName = ComponentName(context, WordOfDayWidgetProvider::class.java)
            val ids = manager.getAppWidgetIds(componentName)
            updateWidgets(context, manager, ids)
        }
    }
}
