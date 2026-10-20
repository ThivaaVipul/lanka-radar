package app.lankaradar

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.TimeUnit

/**
 * The home-screen widget: Petrol 92, Diesel, USD/LKR and the next holiday as
 * the app last saved them (lib/core/home_screen_widget.dart), with a line for
 * a power cut at a place. It works out only what changes with the clock: the
 * holiday's countdown, and whether the numbers are old enough to say when they
 * were read. A tap opens the tab the part belongs to.
 */
class RadarWidget : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val views = draw(context, widgetData, System.currentTimeMillis())
        appWidgetIds.forEach { appWidgetManager.updateAppWidget(it, views) }
    }

    private fun draw(context: Context, data: SharedPreferences, now: Long) =
        RemoteViews(context.packageName, R.layout.radar_widget).apply {
            number(data, "petrol", R.id.petrol_value, R.id.petrol_rise, R.id.petrol_fall, R.id.petrol_note)
            number(data, "diesel", R.id.diesel_value, R.id.diesel_rise, R.id.diesel_fall, R.id.diesel_note)
            number(data, "usd", R.id.usd_value, R.id.usd_rise, R.id.usd_fall, R.id.usd_note)
            holiday(data, now)
            cut(data)
            asOf(data, now)
            setOnClickPendingIntent(android.R.id.background, open(context, "today"))
            setOnClickPendingIntent(R.id.petrol, open(context, "prices"))
            setOnClickPendingIntent(R.id.diesel, open(context, "prices"))
            setOnClickPendingIntent(R.id.usd, open(context, "prices"))
            setOnClickPendingIntent(R.id.holiday, open(context, "dates"))
            setOnClickPendingIntent(R.id.cut, open(context, "power"))
        }

    /** A number: its value, a rise or a fall and by how much, and its note. */
    private fun RemoteViews.number(
        data: SharedPreferences,
        key: String,
        value: Int,
        rise: Int,
        fall: Int,
        note: Int,
    ) {
        setTextViewText(value, data.getString("$key.value", null) ?: "-")
        show(rise, data.getString("$key.rise", null))
        show(fall, data.getString("$key.fall", null))
        show(note, data.getString("$key.note", null))
    }

    /** The first holiday from today on, with how far away it is. */
    private fun RemoteViews.holiday(data: SharedPreferences, now: Long) {
        val today = isoDay(now)
        // One a line: the day, the name, the day as shown.
        val next = data.getString("holidays", null).orEmpty()
            .lines()
            .map { it.split('\t') }
            .firstOrNull { it.size == 3 && it[0] >= today }
        setTextViewText(R.id.holiday_value, next?.get(1) ?: "-")
        show(R.id.holiday_note, next?.let { "${it[2]}, ${countdown(it[0], today)}" })
    }

    /** The power cut line, only while a place has a cut. */
    private fun RemoteViews.cut(data: SharedPreferences) {
        val title = data.getString("cut.title", null)
        setViewVisibility(R.id.cut, if (title == null) View.GONE else View.VISIBLE)
        setTextViewText(R.id.cut_title, title.orEmpty())
        show(R.id.cut_note, data.getString("cut.note", null))
    }

    /** "as of 09:00" once the fuel prices were read more than 3 hours ago. */
    private fun RemoteViews.asOf(data: SharedPreferences, now: Long) {
        val read = data.getString("asOf", null)?.toLongOrNull()
        val old = read != null && now - read > TimeUnit.HOURS.toMillis(3)
        show(R.id.as_of, if (old) "as of ${stamp(read!!, now)}" else null)
    }

    /** Shows [text] in [view], or hides the view when there is none. */
    private fun RemoteViews.show(view: Int, text: String?) {
        setViewVisibility(view, if (text == null) View.GONE else View.VISIBLE)
        setTextViewText(view, text.orEmpty())
    }

    private fun open(context: Context, tab: String) =
        HomeWidgetLaunchIntent.getActivity(
            context,
            MainActivity::class.java,
            Uri.parse("lankaradar://$tab"),
        )

    /** 2026-10-24 on the phone's clock, as the app writes days. */
    private fun isoDay(time: Long) =
        SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date(time))

    /** "today", "tomorrow" or "in 4 days", as in the app. */
    private fun countdown(day: String, today: String): String {
        val format = SimpleDateFormat("yyyy-MM-dd", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }
        val days = TimeUnit.MILLISECONDS.toDays(
            format.parse(day)!!.time - format.parse(today)!!.time,
        )
        return when (days) {
            0L -> "today"
            1L -> "tomorrow"
            else -> "in $days days"
        }
    }

    /** "09:00" today, "19 Oct" on another day. */
    private fun stamp(time: Long, now: Long) =
        SimpleDateFormat(
            if (isoDay(time) == isoDay(now)) "HH:mm" else "d MMM",
            Locale.US,
        ).format(Date(time))
}
