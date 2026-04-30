package com.example.wordix

import android.content.Intent
import android.widget.RemoteViewsService

class WordOfDayWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory {
        return WordOfDayRemoteViewsFactory(applicationContext, intent)
    }
}
