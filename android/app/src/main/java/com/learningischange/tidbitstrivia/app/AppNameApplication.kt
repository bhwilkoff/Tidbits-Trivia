package com.learningischange.tidbitstrivia.app

import android.app.Application
import com.learningischange.tidbitstrivia.data.Store

/**
 * Composition root — manual DI (android-production-gotchas v1 rule:
 * Hilt arrives when module count demands it, not before). Holds the
 * single [Store] (records / streak / seen) the whole app shares.
 */
class AppNameApplication : Application() {
    lateinit var container: AppContainer
        private set

    override fun onCreate() {
        super.onCreate()
        container = AppContainer(Store(this))
    }
}

class AppContainer(val store: Store)
