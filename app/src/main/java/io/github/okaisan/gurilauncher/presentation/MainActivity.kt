package io.github.okaisan.gurilauncher.presentation

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import io.github.okaisan.gurilauncher.infrastructure.AndroidAppContainer

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val appName = AndroidAppContainer.getAppName().value
        setContent { GuriLauncherApp(appName) }
    }
}

@Composable
fun GuriLauncherApp(appName: String) {
    MaterialTheme {
        Surface(modifier = Modifier.fillMaxSize()) {
            Box(contentAlignment = Alignment.Center) { Text(appName) }
        }
    }
}

@Preview(showBackground = true)
@Composable
private fun Preview() = GuriLauncherApp("guri-launcher")
