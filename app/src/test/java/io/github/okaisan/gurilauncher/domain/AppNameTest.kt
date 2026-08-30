package io.github.okaisan.gurilauncher.domain

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class AppNameTest {
    @Test fun `non-blank name is accepted`() {
        assertEquals("guri-launcher", AppName("guri-launcher").value)
    }
    @Test fun `blank name is rejected`() {
        assertThrows(IllegalArgumentException::class.java) { AppName(" ") }
    }
}
