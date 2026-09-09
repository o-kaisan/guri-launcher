package io.github.okaisan.gurilauncher.infrastructure.home

import android.app.Activity
import android.app.role.RoleManager
import android.content.ActivityNotFoundException
import android.content.Intent
import android.os.Build
import android.provider.Settings
import androidx.annotation.RequiresApi

enum class HomeRoleRoute {
    ROLE_MANAGER,
    HOME_SETTINGS,
}

fun decideHomeRoleRoute(apiLevel: Int): HomeRoleRoute =
    if (apiLevel >= Build.VERSION_CODES.Q) {
        HomeRoleRoute.ROLE_MANAGER
    } else {
        HomeRoleRoute.HOME_SETTINGS
    }

sealed interface HomeRoleRequestResult {
    data object NotHome : HomeRoleRequestResult

    data object AlreadyHome : HomeRoleRequestResult

    data object RequestStarted : HomeRoleRequestResult

    data object SettingsOpened : HomeRoleRequestResult

    data object Denied : HomeRoleRequestResult

    data object Unavailable : HomeRoleRequestResult

    data object Failed : HomeRoleRequestResult
}

class HomeRoleRequester {
    fun request(activity: Activity): HomeRoleRequestResult = request(
        apiLevel = Build.VERSION.SDK_INT,
        platform = AndroidHomeRolePlatform(activity),
    )

    fun currentResult(activity: Activity): HomeRoleRequestResult {
        val platform = AndroidHomeRolePlatform(activity)
        return if (platform.isCurrentHome(decideHomeRoleRoute(Build.VERSION.SDK_INT))) {
            HomeRoleRequestResult.AlreadyHome
        } else {
            HomeRoleRequestResult.NotHome
        }
    }

    internal fun request(
        apiLevel: Int,
        platform: HomeRolePlatform,
    ): HomeRoleRequestResult {
        val route = decideHomeRoleRoute(apiLevel)
        if (platform.isCurrentHome(route)) return HomeRoleRequestResult.AlreadyHome

        return when (route) {
            HomeRoleRoute.ROLE_MANAGER -> {
                if (!platform.isRoleAvailable()) {
                    HomeRoleRequestResult.Unavailable
                } else if (platform.requestHomeRole()) {
                    HomeRoleRequestResult.RequestStarted
                } else {
                    HomeRoleRequestResult.Failed
                }
            }

            HomeRoleRoute.HOME_SETTINGS -> {
                if (platform.openHomeSettings()) {
                    HomeRoleRequestResult.SettingsOpened
                } else {
                    HomeRoleRequestResult.Failed
                }
            }
        }
    }

}

internal interface HomeRolePlatform {
    fun isCurrentHome(route: HomeRoleRoute): Boolean

    fun isRoleAvailable(): Boolean

    fun requestHomeRole(): Boolean

    fun openHomeSettings(): Boolean
}

private class AndroidHomeRolePlatform(
    private val activity: Activity,
) : HomeRolePlatform {
    override fun isCurrentHome(route: HomeRoleRoute): Boolean = when (route) {
        HomeRoleRoute.ROLE_MANAGER -> {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                roleManager().isRoleHeld(RoleManager.ROLE_HOME)
            } else {
                false
            }
        }
        HomeRoleRoute.HOME_SETTINGS -> {
            val homeIntent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
            val resolvedHome = activity.packageManager.resolveActivity(homeIntent, 0)
            resolvedHome?.activityInfo?.packageName == activity.packageName
        }
    }

    override fun isRoleAvailable(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q &&
            roleManager().isRoleAvailable(RoleManager.ROLE_HOME)

    override fun requestHomeRole(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return false
        val manager = roleManager()
        return startSystemUi(manager.createRequestRoleIntent(RoleManager.ROLE_HOME))
    }

    override fun openHomeSettings(): Boolean =
        startSystemUi(Intent(Settings.ACTION_HOME_SETTINGS))

    @RequiresApi(Build.VERSION_CODES.Q)
    private fun roleManager(): RoleManager =
        activity.getSystemService(RoleManager::class.java)

    private fun startSystemUi(intent: Intent): Boolean = try {
        activity.startActivityForResult(intent, HOME_ROLE_REQUEST_CODE)
        true
    } catch (_: ActivityNotFoundException) {
        false
    }
}

const val HOME_ROLE_REQUEST_CODE = 20
