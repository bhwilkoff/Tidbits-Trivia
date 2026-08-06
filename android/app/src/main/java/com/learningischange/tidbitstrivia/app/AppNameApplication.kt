package com.learningischange.tidbitstrivia.app

import android.app.Application
import com.learningischange.tidbitstrivia.data.Billing
import com.learningischange.tidbitstrivia.data.Duels
import com.learningischange.tidbitstrivia.data.QuizStore
import com.learningischange.tidbitstrivia.data.Entitlement
import com.learningischange.tidbitstrivia.data.JsonQuestionSet
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
        Duels.init(this)   // L5: persist tracked duel ids across process death
        JsonQuestionSet.init(this)   // shape sets load on first use, not at boot
        QuizStore.init(this)   // saved quizzes: local is the source of truth (QUIZ-CONTRACT §4)
        Entitlement.init(this)   // Club gate: cached last-known-good survives process death
        Billing.start(this)   // Club gate Class A: Play Billing local check + purchase flow
    }
}

class AppContainer(val store: Store)
