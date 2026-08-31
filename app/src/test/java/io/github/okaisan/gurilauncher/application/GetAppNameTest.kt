package io.github.okaisan.gurilauncher.application

import org.junit.Assert.assertEquals
import org.junit.Test

class GetAppNameTest {
    @Test fun `returns product name`() {
        assertEquals("guri-launcher", GetAppName()().value)
    }
}
