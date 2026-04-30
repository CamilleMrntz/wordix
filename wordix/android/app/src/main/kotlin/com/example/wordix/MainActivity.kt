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
                    val slot = call.argument<String>("slot") ?: "en"
                    if (slot != "en" && slot != "es") {
                        result.error("bad_slot", "slot must be en or es", null)
                        return@setMethodCallHandler
                    }
                    val word = call.argument<String>("word").orEmpty()
                    val partOfSpeech = call.argument<String>("partOfSpeech").orEmpty()
                    val definition = call.argument<String>("definition").orEmpty()

                    updateWidgetData(slot, word, partOfSpeech, definition)
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
    }

    private fun updateWidgetData(slot: String, word: String, partOfSpeech: String, definition: String) {
        val prefs = applicationContext.getSharedPreferences("WordixWidgetPrefs", Context.MODE_PRIVATE)
        val e = prefs.edit()
        if (slot == "es") {
            e.putString("word_es", word)
                .putString("partOfSpeech_es", partOfSpeech)
                .putString("definition_es", definition)
        } else {
            e.putString("word_en", word)
                .putString("partOfSpeech_en", partOfSpeech)
                .putString("definition_en", definition)
                .putString("word", word)
                .putString("partOfSpeech", partOfSpeech)
                .putString("definition", definition)
        }
        e.apply()

        val appWidgetManager = AppWidgetManager.getInstance(applicationContext)
        if (slot == "es") {
            val componentName = ComponentName(applicationContext, WordOfDayEsWidgetProvider::class.java)
            val appWidgetIds = appWidgetManager.getAppWidgetIds(componentName)
            WordOfDayEsWidgetProvider.updateWidgets(applicationContext, appWidgetManager, appWidgetIds)
        } else {
            val componentName = ComponentName(applicationContext, WordOfDayWidgetProvider::class.java)
            val appWidgetIds = appWidgetManager.getAppWidgetIds(componentName)
            WordOfDayWidgetProvider.updateWidgets(applicationContext, appWidgetManager, appWidgetIds)
        }
    }
}
