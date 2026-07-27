package com.screenstreaks.screenstreaks

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

/// Home-screen widget: this week's progress chips + current streak.
/// Data is pushed from Flutter via the home_widget plugin (see
/// lib/services/home_widget_service.dart).
class WeekWidgetProvider : HomeWidgetProvider() {

    private val tileIds = intArrayOf(
        R.id.tile0, R.id.tile1, R.id.tile2, R.id.tile3,
        R.id.tile4, R.id.tile5, R.id.tile6
    )
    private val letterIds = intArrayOf(
        R.id.letter0, R.id.letter1, R.id.letter2, R.id.letter3,
        R.id.letter4, R.id.letter5, R.id.letter6
    )

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        val met = 0xFF10B981.toInt()
        val missed = 0xFFF0524B.toInt()
        val none = 0xFF26262B.toInt()

        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.week_widget)

            val streak = widgetData.getInt("streak", 0)
            views.setTextViewText(R.id.streak_count, streak.toString())
            views.setTextViewText(
                R.id.streak_label,
                if (streak == 1) "day streak" else "day streak"
            )

            for (i in 0..6) {
                val status = widgetData.getString("day$i", "none")
                val color = when (status) {
                    "met" -> met
                    "missed" -> missed
                    else -> none
                }
                views.setInt(tileIds[i], "setColorFilter", color)
                views.setTextViewText(
                    letterIds[i],
                    widgetData.getString("letter$i", "") ?: ""
                )
            }

            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
