package io.github.okaisan.gurilauncher.domain

/** Framework-independent application name. */
@JvmInline
value class AppName(val value: String) {
    init { require(value.isNotBlank()) { "App name must not be blank" } }
}
