package albanrss.tempo

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import androidx.core.app.NotificationCompat
import java.util.Calendar

class AppBlockerAccessibilityService : AccessibilityService() {

    companion object {
        @Volatile var instance: AppBlockerAccessibilityService? = null
            private set

        private const val TAG = "AppBlockerAccService"
        private const val PREFS_NAME = "FlutterSharedPreferences"
        private const val LIMIT_PREFIX = "flutter.time_limit_"
        private const val APP_NAME_PREFIX = "flutter.app_name_"
        private const val PERIODIC_CHECK_MS = 5000L // 5 seconds
        private const val ALERT_CHANNEL_ID = "app_limiter_channel"
        private const val ALERT_CHANNEL_NAME = "App Limiter"
        private const val ALERT_CHANNEL_DESCRIPTION = "Notifications for app usage limits"
        // TTL du cache des apps launchable/launcher (10 minutes)
        private const val APPS_CACHE_TTL_MS = 10 * 60 * 1000L
    }

    // Thread dédié aux opérations lourdes (queryEvents, SharedPreferences)
    // pour ne jamais bloquer le thread principal.
    private val bgThread = HandlerThread("AppBlockerBg").also { it.start() }
    private val bgHandler = Handler(bgThread.looper)

    // Ces champs sont accédés depuis bgThread uniquement (après onServiceConnected)
    private var launcherPackages: Set<String>? = null
    private var launcherPackagesTimestamp: Long = 0L
    private var launchableApps: Set<String>? = null
    private var launchableAppsTimestamp: Long = 0L

    // Accédé depuis les deux threads : volatile pour la visibilité
    @Volatile private var blockedPackageName: String? = null
    @Volatile private var currentForegroundApp: String? = null

    // Accédé uniquement depuis bgThread
    private val notifiedSoonPackages = mutableSetOf<String>()

    private val periodicCheck = object : Runnable {
        override fun run() {
            // Tourne entièrement sur bgThread — pas de blocage du thread principal
            checkCurrentAppLimit()
            bgHandler.postDelayed(this, PERIODIC_CHECK_MS)
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this

        val info = AccessibilityServiceInfo().apply {
            eventTypes = AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED
            feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC
            notificationTimeout = 100
        }
        serviceInfo = info
        if (BuildConfig.DEBUG) Log.d(TAG, "Accessibility service connected")
        createNotificationChannel()
        // Démarrer la vérification périodique sur le thread de fond
        bgHandler.postDelayed(periodicCheck, PERIODIC_CHECK_MS)
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event?.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return

        val packageName = event.packageName?.toString() ?: return

        // Filtrage rapide sans I/O : si l'app est déjà bloquée, retour immédiat
        val currentBlocked = blockedPackageName
        if (currentBlocked != null && packageName == currentBlocked) {
            if (BuildConfig.DEBUG) Log.d(TAG, "Re-opened blocked app $packageName — sending home")
            goToHomeScreen()
            return
        }

        // Mettre à jour l'app au premier plan (visible depuis tous les threads)
        currentForegroundApp = packageName

        // Déléguer la vérification lourde (I/O) au thread de fond
        bgHandler.post { handleAppForeground(packageName) }
    }

    private fun handleAppForeground(packageName: String) {
        // Cette fonction tourne sur bgThread

        if (!isLaunchableApp(packageName)) return

        if (BuildConfig.DEBUG) Log.d(TAG, "Window changed → $packageName (blocked=$blockedPackageName)")

        val currentBlocked = blockedPackageName

        // ── Active block + navigated elsewhere ──
        if (currentBlocked != null && packageName != currentBlocked) {
            if (isLauncher(packageName) || packageName == "com.android.settings") {
                if (BuildConfig.DEBUG) Log.d(TAG, "On launcher/settings while blocked — staying blocked")
                return
            }
            if (BuildConfig.DEBUG) Log.d(TAG, "Navigated to $packageName — clearing block")
            blockedPackageName = null
            // Fall through to check if new app also has a limit
        }

        if (packageName == applicationContext.packageName) return

        if (isLauncher(packageName) || packageName == "com.android.settings") return

        checkLimitForPackage(packageName)
    }

    private fun checkCurrentAppLimit() {
        // Tourne sur bgThread
        val pkg = currentForegroundApp ?: return
        if (blockedPackageName != null) return
        if (pkg == applicationContext.packageName) return
        if (isLauncher(pkg) || pkg == "com.android.settings") return

        checkLimitForPackage(pkg)
    }

    /** Vérifie la limite pour un package donné. Doit être appelé depuis bgThread. */
    private fun checkLimitForPackage(packageName: String) {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val limitKey = "$LIMIT_PREFIX$packageName"
        if (!prefs.contains(limitKey)) return

        val limitMinutes = try {
            prefs.getLong(limitKey, -1)
        } catch (e: ClassCastException) {
            try { prefs.getInt(limitKey, -1).toLong() } catch (_: ClassCastException) {
                if (BuildConfig.DEBUG) Log.e(TAG, "Cannot read limit for $packageName")
                return
            }
        }
        if (limitMinutes <= 0) return

        val usageSeconds = getUsageToday(packageName)
        if (BuildConfig.DEBUG) Log.d(TAG, "$packageName: used ${usageSeconds}s / limit ${limitMinutes * 60}s")

        if (usageSeconds >= limitMinutes * 60) {
            val appName = prefs.getString("$APP_NAME_PREFIX$packageName", null) ?: packageName
            if (BuildConfig.DEBUG) Log.d(TAG, "BLOCKING $appName (used ${usageSeconds}s >= ${limitMinutes * 60}s)")
            blockedPackageName = packageName
            notifiedSoonPackages.remove(packageName)
            goToHomeScreen()
            showLimitNotification(appName, usageSeconds)
        } else if (limitMinutes * 60 - usageSeconds <= 60) {
            if (!notifiedSoonPackages.contains(packageName)) {
                val appName = prefs.getString("$APP_NAME_PREFIX$packageName", null) ?: packageName
                if (BuildConfig.DEBUG) Log.d(TAG, "Approaching limit for $appName (used ${usageSeconds}s)")
                showLimitSoonNotification(appName, usageSeconds, limitMinutes)
                notifiedSoonPackages.add(packageName)
            }
        } else {
            notifiedSoonPackages.remove(packageName)
        }
    }

    private fun isLauncher(packageName: String): Boolean {
        val now = System.currentTimeMillis()
        if (launcherPackages == null || now - launcherPackagesTimestamp > APPS_CACHE_TTL_MS) {
            val intent = Intent(Intent.ACTION_MAIN).apply { addCategory(Intent.CATEGORY_HOME) }
            val resolveInfos = packageManager.queryIntentActivities(intent, 0)
            launcherPackages = resolveInfos.map { it.activityInfo.packageName }.toSet()
            launcherPackagesTimestamp = now
            if (BuildConfig.DEBUG) Log.d(TAG, "Launcher packages refreshed: $launcherPackages")
        }
        return launcherPackages!!.contains(packageName)
    }

    private fun isLaunchableApp(packageName: String): Boolean {
        val now = System.currentTimeMillis()
        if (launchableApps == null || now - launchableAppsTimestamp > APPS_CACHE_TTL_MS) {
            val intent = Intent(Intent.ACTION_MAIN).apply { addCategory(Intent.CATEGORY_LAUNCHER) }
            val resolveInfos = packageManager.queryIntentActivities(intent, 0)
            launchableApps = resolveInfos.map { it.activityInfo.packageName }.toSet()
            launchableAppsTimestamp = now
        }
        return launchableApps!!.contains(packageName)
    }

    private fun getUsageToday(packageName: String): Long {
        val usageStatsManager =
            getSystemService(Context.USAGE_STATS_SERVICE) as? UsageStatsManager ?: return 0

        val now = System.currentTimeMillis()
        val cal = Calendar.getInstance()
        cal.set(Calendar.HOUR_OF_DAY, 0)
        cal.set(Calendar.MINUTE, 0)
        cal.set(Calendar.SECOND, 0)
        cal.set(Calendar.MILLISECOND, 0)
        val startOfDay = cal.timeInMillis

        return try {
            val events = usageStatsManager.queryEvents(startOfDay, now)
            var totalForegroundMs = 0L
            var lastForegroundTime: Long? = null
            val event = UsageEvents.Event()

            while (events.hasNextEvent()) {
                events.getNextEvent(event)
                if (event.packageName != packageName) continue

                when (event.eventType) {
                    // MOVE_TO_FOREGROUND or ACTIVITY_RESUMED
                    1, 7 -> {
                        lastForegroundTime = event.timeStamp
                    }
                    // MOVE_TO_BACKGROUND or ACTIVITY_PAUSED
                    2, 15 -> {
                        if (lastForegroundTime != null) {
                            totalForegroundMs += event.timeStamp - lastForegroundTime
                            lastForegroundTime = null
                        }
                    }
                }
            }

            // If currently in foreground, count the ongoing session
            if (lastForegroundTime != null) {
                totalForegroundMs += now - lastForegroundTime
            }

            totalForegroundMs / 1000 // Return seconds
        } catch (e: Exception) {
            if (BuildConfig.DEBUG) Log.e(TAG, "Error querying usage events: $e")
            0
        }
    }

    private fun goToHomeScreen() {
        val intent = Intent(Intent.ACTION_MAIN).apply {
            addCategory(Intent.CATEGORY_HOME)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }
        startActivity(intent)
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                ALERT_CHANNEL_ID,
                ALERT_CHANNEL_NAME,
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = ALERT_CHANNEL_DESCRIPTION
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(channel)
        }
    }

    private fun showLimitNotification(appName: String, usageSeconds: Long) {
        val usageMinutes = usageSeconds / 60
        val notification = NotificationCompat.Builder(this, ALERT_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_launcher_foreground)
            .setContentTitle("Time Limit Exceeded")
            .setContentText(
                "You used $appName for $usageMinutes minute" +
                (if (usageMinutes > 1) "s" else "")
            )
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .build()

        val manager = getSystemService(NotificationManager::class.java)
        manager?.notify(appName.hashCode(), notification)
    }

    private fun showLimitSoonNotification(appName: String, usageSeconds: Long, limitMinutes: Long) {
        val usageMinutes = usageSeconds / 60
        val notification = NotificationCompat.Builder(this, ALERT_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_launcher_foreground)
            .setContentTitle("Approaching Time Limit")
            .setContentText(
                "You used $appName for $usageMinutes minute" +
                (if (usageMinutes > 1) "s" else "") +
                ". Limit is $limitMinutes minute" +
                (if (limitMinutes > 1) "s" else "")
            )
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setAutoCancel(true)
            .build()

        val manager = getSystemService(NotificationManager::class.java)
        manager?.notify(appName.hashCode(), notification)
    }

    override fun onInterrupt() {
        if (BuildConfig.DEBUG) Log.d(TAG, "Accessibility service interrupted")
        bgHandler.removeCallbacks(periodicCheck)
        bgThread.quitSafely()
        instance = null
    }

    override fun onDestroy() {
        super.onDestroy()
        bgHandler.removeCallbacks(periodicCheck)
        bgThread.quitSafely()
        instance = null
        if (BuildConfig.DEBUG) Log.d(TAG, "Accessibility service destroyed")
    }
}
