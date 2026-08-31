package io.github.okaisan.gurilauncher.infrastructure

import io.github.okaisan.gurilauncher.application.GetAppName

/** Android composition root for application dependencies. */
object AndroidAppContainer {
    val getAppName = GetAppName()
}
