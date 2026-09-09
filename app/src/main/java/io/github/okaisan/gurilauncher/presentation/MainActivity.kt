package io.github.okaisan.gurilauncher.presentation

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import io.github.okaisan.gurilauncher.R
import io.github.okaisan.gurilauncher.infrastructure.AndroidAppContainer
import io.github.okaisan.gurilauncher.infrastructure.home.HomeRoleRequestResult
import io.github.okaisan.gurilauncher.infrastructure.home.HomeRoleRequester

class MainActivity : ComponentActivity() {
    private val homeRoleRequester = HomeRoleRequester()
    private var homeRoleResult by mutableStateOf<HomeRoleRequestResult>(HomeRoleRequestResult.NotHome)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val appName = AndroidAppContainer.getAppName().value
        homeRoleResult = homeRoleRequester.currentResult(this)
        setContent {
            GuriLauncherApp(
                appName = appName,
                homeRoleResult = homeRoleResult,
                onSetDefaultHome = ::requestDefaultHome,
            )
        }
    }

    override fun onResume() {
        super.onResume()
        homeRoleResult = homeRoleResultOnResume(
            previousResult = homeRoleResult,
            isCurrentHome = homeRoleRequester.currentResult(this) ==
                HomeRoleRequestResult.AlreadyHome,
        )
    }

    private fun requestDefaultHome() {
        homeRoleResult = homeRoleRequester.request(this)
    }
}

internal fun homeRoleResultOnResume(
    previousResult: HomeRoleRequestResult,
    isCurrentHome: Boolean,
): HomeRoleRequestResult = when {
    isCurrentHome -> HomeRoleRequestResult.AlreadyHome
    previousResult == HomeRoleRequestResult.RequestStarted ||
        previousResult == HomeRoleRequestResult.SettingsOpened -> HomeRoleRequestResult.Denied
    previousResult == HomeRoleRequestResult.Failed ||
        previousResult == HomeRoleRequestResult.Unavailable -> previousResult
    else -> HomeRoleRequestResult.NotHome
}

@Composable
fun GuriLauncherApp(
    appName: String,
    homeRoleResult: HomeRoleRequestResult,
    onSetDefaultHome: () -> Unit,
) {
    MaterialTheme {
        Surface(modifier = Modifier.fillMaxSize()) {
            Box(contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(appName)
                    Text(
                        text = homeRoleResult.statusText(),
                        modifier = Modifier.padding(top = 12.dp),
                    )
                    Button(
                        onClick = onSetDefaultHome,
                        enabled = homeRoleResult != HomeRoleRequestResult.AlreadyHome,
                        modifier = Modifier.padding(top = 12.dp),
                    ) {
                        Text(stringResource(R.string.set_default_home))
                    }
                }
            }
        }
    }
}

@Composable
private fun HomeRoleRequestResult.statusText(): String = stringResource(
    when (this) {
        HomeRoleRequestResult.NotHome -> R.string.home_status_not_selected
        HomeRoleRequestResult.AlreadyHome -> R.string.home_status_selected
        HomeRoleRequestResult.RequestStarted,
        HomeRoleRequestResult.SettingsOpened,
        -> R.string.home_status_choose_in_system_ui
        HomeRoleRequestResult.Denied -> R.string.home_status_not_selected
        HomeRoleRequestResult.Unavailable -> R.string.home_status_unavailable
        HomeRoleRequestResult.Failed -> R.string.home_status_failed
    },
)

@Preview(showBackground = true)
@Composable
private fun Preview() = GuriLauncherApp(
    appName = "guri-launcher",
    homeRoleResult = HomeRoleRequestResult.NotHome,
    onSetDefaultHome = {},
)
