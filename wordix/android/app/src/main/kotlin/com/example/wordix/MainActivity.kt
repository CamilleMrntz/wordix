package com.example.wordix

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "wordix/widget"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                if (call.method == "updateWordWidget") {
                    val word = call.argument<String>("word").orEmpty()
                    val partOfSpeech = call.argument<String>("partOfSpeech").orEmpty()
                    val definition = call.argument<String>("definition").orEmpty()

                    updateWidgetData(word, partOfSpeech, definition)
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
    }

    private fun updateWidgetData(word: String, partOfSpeech: String, definition: String) {
        val prefs = applicationContext.getSharedPreferences("WordixWidgetPrefs", Context.MODE_PRIVATE)
        prefs.edit()
            .putString("word", word)
            .putString("partOfSpeech", partOfSpeech)
            .putString("definition", definition)
            .apply()

        val appWidgetManager = AppWidgetManager.getInstance(applicationContext)
        val componentName = ComponentName(applicationContext, WordOfDayWidgetProvider::class.java)
        val appWidgetIds = appWidgetManager.getAppWidgetIds(componentName)
        WordOfDayWidgetProvider.updateWidgets(applicationContext, appWidgetManager, appWidgetIds)
    }
}
