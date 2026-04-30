package com.example.wordix

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context

class WordOfDayEsWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        WordWidgetUpdates.update(context, appWidgetManager, appWidgetIds, WordWidgetUpdates.SLOT_ES)
    }

    companion object {
        fun updateWidgets(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetIds: IntArray,
        ) {
            WordWidgetUpdates.update(context, appWidgetManager, appWidgetIds, WordWidgetUpdates.SLOT_ES)
        }

        fun requestUpdateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val componentName = ComponentName(context, WordOfDayEsWidgetProvider::class.java)
            val ids = manager.getAppWidgetIds(componentName)
            updateWidgets(context, manager, ids)
        }
    }
}
