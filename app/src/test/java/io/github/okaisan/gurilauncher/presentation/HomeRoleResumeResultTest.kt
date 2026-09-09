package io.github.okaisan.gurilauncher.presentation

import io.github.okaisan.gurilauncher.infrastructure.home.HomeRoleRequestResult
import org.junit.Assert.assertEquals
import org.junit.Test

class HomeRoleResumeResultTest {
    @Test
    fun `losing home role outside the app refreshes selected state`() {
        val result = homeRoleResultOnResume(
            previousResult = HomeRoleRequestResult.AlreadyHome,
            isCurrentHome = false,
        )

        assertEquals(HomeRoleRequestResult.NotHome, result)
    }

    @Test
    fun `return from role request without home role reports denial`() {
        val result = homeRoleResultOnResume(
            previousResult = HomeRoleRequestResult.RequestStarted,
            isCurrentHome = false,
        )

        assertEquals(HomeRoleRequestResult.Denied, result)
    }

    @Test
    fun `successful selection on return reports selected home`() {
        val result = homeRoleResultOnResume(
            previousResult = HomeRoleRequestResult.SettingsOpened,
            isCurrentHome = true,
        )

        assertEquals(HomeRoleRequestResult.AlreadyHome, result)
    }

    @Test
    fun `launch failure survives resume without a system UI round trip`() {
        val result = homeRoleResultOnResume(
            previousResult = HomeRoleRequestResult.Failed,
            isCurrentHome = false,
        )

        assertEquals(HomeRoleRequestResult.Failed, result)
    }

    @Test
    fun `unavailable role survives resume without a system UI round trip`() {
        val result = homeRoleResultOnResume(
            previousResult = HomeRoleRequestResult.Unavailable,
            isCurrentHome = false,
        )

        assertEquals(HomeRoleRequestResult.Unavailable, result)
    }
}
