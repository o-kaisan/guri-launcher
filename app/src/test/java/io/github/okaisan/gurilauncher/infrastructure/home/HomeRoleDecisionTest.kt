package io.github.okaisan.gurilauncher.infrastructure.home

import org.junit.Assert.assertEquals
import org.junit.Test

class HomeRoleDecisionTest {
    @Test
    fun `API 29 uses role manager`() {
        assertEquals(HomeRoleRoute.ROLE_MANAGER, decideHomeRoleRoute(29))
    }

    @Test
    fun `API 28 uses home settings`() {
        assertEquals(HomeRoleRoute.HOME_SETTINGS, decideHomeRoleRoute(28))
    }

    @Test
    fun `minimum supported API uses home settings`() {
        assertEquals(HomeRoleRoute.HOME_SETTINGS, decideHomeRoleRoute(26))
    }
}
