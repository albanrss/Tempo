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

class AppBlockerAccessibilityService : AccessibilityService() {

    companion object {
        @Volatile var instance: AppBlockerAccessibilityService? = null
            private set

        private const val TAG = "AppBlockerAccService"
        private const val PREFS_NAME = "FlutterSharedPreferences"
        private const val LIMIT_PREFIX = "flutter.time_limit_"
        private const val APP_NAME_PREFIX = "flutter.app_name_"
        private const val USAGE_WINDOW_MS = 60 * 60 * 1000L // 1 hour
        private const val PERIODIC_CHECK_MS = 5000L // 5 seconds
        private const val ALERT_CHANNEL_ID = "app_limiter_channel"
        private const val ALERT_CHANNEL_NAME = "App Limiter"
        private const val ALERT_CHANNEL_DESCRIPTION = "Notifications for app usage limits"
        // TTL du cache des apps launchable/launcher (10 minutes)
        private const val APPS_CACHE_TTL_MS = 10 * 60 * 1000L
        private const val FORCED_BG_PREFIX = "flutter.forced_bg_"
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

    // Timestamps (ms) at which each package was forcibly sent to background.
    // Used to cap ongoing-session calculation in getUsageInLastHour() when the
    // OS has not yet written the corresponding BACKGROUND event to UsageStatsManager.
    private val forcedBackgroundTimes = mutableMapOf<String, Long>()

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

        // Déléguer la vérification lourde (I/O) au thread de fond
        bgHandler.post { handleAppForeground(packageName) }
    }

    private fun handleAppForeground(packageName: String) {
        // Cette fonction tourne sur bgThread

        if (!isLaunchableApp(packageName)) return

        // Récupérer la vraie application au premier plan selon UsageStatsManager
        // pour ignorer les overlays (ex: Digital Wellbeing, pubs superposées).
        val realApp = getRealForegroundApp()
        val appToCheck = if (realApp != null && realApp != packageName) {
            if (BuildConfig.DEBUG) Log.d(TAG, "Fake window change: ignored $packageName, real app is $realApp")
            realApp
        } else {
            packageName
        }

        // Only track launchable apps as the current foreground app so that
        // background system services (e.g. GMS, SystemUI) cannot override it
        // and cause the periodic check to miss the user-facing app's limit.
        currentForegroundApp = appToCheck

        if (BuildConfig.DEBUG) Log.d(TAG, "Window changed → $appToCheck (blocked=$blockedPackageName)")

        val currentBlocked = blockedPackageName

        // ── Active block + navigated elsewhere ──
        if (currentBlocked != null && appToCheck != currentBlocked) {
            if (isLauncher(appToCheck) || appToCheck == "com.android.settings") {
                if (BuildConfig.DEBUG) Log.d(TAG, "On launcher/settings while blocked — staying blocked")
                return
            }
            if (BuildConfig.DEBUG) Log.d(TAG, "Navigated to $appToCheck — clearing block")
            blockedPackageName = null
            // Fall through to check if new app also has a limit
        }

        if (appToCheck == applicationContext.packageName) return

        if (isLauncher(appToCheck) || appToCheck == "com.android.settings") return

        checkLimitForPackage(appToCheck)
    }

    private fun checkCurrentAppLimit() {
        // Tourne sur bgThread
        
        // Update currentForegroundApp with the actual foreground app to prevent
        // stale state if an AccessibilityEvent was missed or overlay-based.
        val realApp = getRealForegroundApp()
        if (realApp != null && isLaunchableApp(realApp)) {
            currentForegroundApp = realApp
        }

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

        val usageSeconds = getUsageInLastHour(packageName)
        if (BuildConfig.DEBUG) Log.d(TAG, "$packageName: used ${usageSeconds}s / limit ${limitMinutes * 60}s")

        if (usageSeconds >= limitMinutes * 60) {
            val appName = prefs.getString("$APP_NAME_PREFIX$packageName", null) ?: packageName
            if (BuildConfig.DEBUG) Log.d(TAG, "BLOCKING $appName (used ${usageSeconds}s >= ${limitMinutes * 60}s)")
            blockedPackageName = packageName
            notifiedSoonPackages.remove(packageName)
            // Record the forced-background timestamp so that getUsageInLastHour() can cap
            // any still-open session even if UsageStatsManager has not yet written the
            // BACKGROUND event (which can be delayed by the OS).
            val blockedAtMs = System.currentTimeMillis()
            forcedBackgroundTimes[packageName] = blockedAtMs
            prefs.edit().putLong("$FORCED_BG_PREFIX$packageName", blockedAtMs).apply()
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

    private fun getRealForegroundApp(): String? {
        val usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as? UsageStatsManager ?: return null
        val now = System.currentTimeMillis()
        val start = now - USAGE_WINDOW_MS // 1 hour

        return try {
            val events = usageStatsManager.queryEvents(start, now)
            val event = UsageEvents.Event()

            val activeApps = mutableMapOf<String, Int>()
            var lastForegroundApp: String? = null

            while (events.hasNextEvent()) {
                events.getNextEvent(event)
                // Filter out non-launchable system stuff if needed, but activeApps will tell us
                // the real apps regardless.
                when (event.eventType) {
                    1, 7 -> { // MOVE_TO_FOREGROUND or ACTIVITY_RESUMED
                        activeApps[event.packageName] = activeApps.getOrDefault(event.packageName, 0) + 1
                        lastForegroundApp = event.packageName
                    }
                    2, 15 -> { // MOVE_TO_BACKGROUND or ACTIVITY_PAUSED
                        val count = activeApps.getOrDefault(event.packageName, 0) - 1
                        if (count <= 0) {
                            activeApps.remove(event.packageName)
                        } else {
                            activeApps[event.packageName] = count
                        }
                    }
                }
            }

            if (lastForegroundApp != null && activeApps.containsKey(lastForegroundApp)) {
                lastForegroundApp
            } else {
                activeApps.keys.lastOrNull()
            }
        } catch (e: Exception) {
            null
        }
    }

    private fun getUsageInLastHour(packageName: String): Long {
        val usageStatsManager =
            getSystemService(Context.USAGE_STATS_SERVICE) as? UsageStatsManager ?: return 0

        val now = System.currentTimeMillis()
        val start = now - USAGE_WINDOW_MS

        // Drop entries that have aged out of the window to avoid unbounded growth.
        forcedBackgroundTimes.entries.removeIf { it.value < start }

        return try {
            val events = usageStatsManager.queryEvents(start, now)
            var totalForegroundMs = 0L
            var lastForegroundTime: Long? = null
            val event = UsageEvents.Event()
            var activeCount = 0

            while (events.hasNextEvent()) {
                events.getNextEvent(event)
                if (event.packageName != packageName) continue

                when (event.eventType) {
                    // MOVE_TO_FOREGROUND or ACTIVITY_RESUMED
                    1, 7 -> {
                        if (activeCount == 0) {
                            lastForegroundTime = event.timeStamp
                        }
                        activeCount++
                    }
                    // MOVE_TO_BACKGROUND or ACTIVITY_PAUSED
                    2, 15 -> {
                        if (activeCount > 0) {
                            activeCount--
                            if (activeCount == 0 && lastForegroundTime != null) {
                                totalForegroundMs += event.timeStamp - lastForegroundTime!!
                                lastForegroundTime = null
                            }
                        } else {
                            // If first event is a background event, the app was in foreground before the window started
                            totalForegroundMs += event.timeStamp - start
                        }
                    }
                }
            }

            // If the session still appears open (no matching BACKGROUND event), the OS may not
            // have written it yet — this happens when the app was forcibly sent home by this
            // service.  Cap the ongoing session at the recorded forced-background time so we do
            // not inflate the usage counter with time the user never actually spent in the app.
            if (activeCount > 0 && lastForegroundTime != null) {
                val forcedBgTime = forcedBackgroundTimes[packageName]
                    ?.takeIf { it > lastForegroundTime!! && it <= now }
                totalForegroundMs += (forcedBgTime ?: now) - lastForegroundTime!!
            } else if (activeCount > 0) {
                // App was already in foreground when the window started
                val forcedBgTime = forcedBackgroundTimes[packageName]
                    ?.takeIf { it in start..now }
                totalForegroundMs += (forcedBgTime ?: now) - start
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
