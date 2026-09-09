package io.github.okaisan.gurilauncher.infrastructure.home

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class HomeRoleRequesterTest {
    private val requester = HomeRoleRequester()

    @Test
    fun `already selected home is returned without opening system UI`() {
        val platform = FakeHomeRolePlatform(isCurrentHome = true)

        val result = requester.request(apiLevel = 29, platform = platform)

        assertEquals(HomeRoleRequestResult.AlreadyHome, result)
        assertFalse(platform.systemUiOpened)
    }

    @Test
    fun `available role request starts on API 29`() {
        val platform = FakeHomeRolePlatform(roleAvailable = true)

        val result = requester.request(apiLevel = 29, platform = platform)

        assertEquals(HomeRoleRequestResult.RequestStarted, result)
        assertTrue(platform.roleRequestOpened)
    }

    @Test
    fun `unavailable home role returns unavailable without opening system UI`() {
        val platform = FakeHomeRolePlatform(roleAvailable = false)

        val result = requester.request(apiLevel = 29, platform = platform)

        assertEquals(HomeRoleRequestResult.Unavailable, result)
        assertFalse(platform.systemUiOpened)
    }

    @Test
    fun `home settings opens on API 28`() {
        val platform = FakeHomeRolePlatform()

        val result = requester.request(apiLevel = 28, platform = platform)

        assertEquals(HomeRoleRequestResult.SettingsOpened, result)
        assertTrue(platform.homeSettingsOpened)
    }

    @Test
    fun `failed system UI launch returns failed`() {
        val platform = FakeHomeRolePlatform(systemUiCanOpen = false)

        val result = requester.request(apiLevel = 28, platform = platform)

        assertEquals(HomeRoleRequestResult.Failed, result)
    }

}

private class FakeHomeRolePlatform(
    private val isCurrentHome: Boolean = false,
    private val roleAvailable: Boolean = true,
    private val systemUiCanOpen: Boolean = true,
) : HomeRolePlatform {
    var roleRequestOpened = false
        private set
    var homeSettingsOpened = false
        private set

    val systemUiOpened: Boolean
        get() = roleRequestOpened || homeSettingsOpened

    override fun isCurrentHome(route: HomeRoleRoute): Boolean = isCurrentHome

    override fun isRoleAvailable(): Boolean = roleAvailable

    override fun requestHomeRole(): Boolean {
        roleRequestOpened = systemUiCanOpen
        return systemUiCanOpen
    }

    override fun openHomeSettings(): Boolean {
        homeSettingsOpened = systemUiCanOpen
        return systemUiCanOpen
    }
}
