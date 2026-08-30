package io.github.okaisan.gurilauncher.application

import io.github.okaisan.gurilauncher.domain.AppName

/** Returns the product name shown on the initial screen. */
class GetAppName {
    operator fun invoke(): AppName = AppName("guri-launcher")
}
