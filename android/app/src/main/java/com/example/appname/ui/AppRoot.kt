package com.example.appname.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.adaptive.currentWindowAdaptiveInfo
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteScaffold
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

/**
 * Root scaffold. Hosts the size-class-adaptive nav surface
 * (NavigationBar on compact, NavigationRail on medium+, drawer on
 * expanded) via [NavigationSuiteScaffold]. One Composable hierarchy;
 * never fork per form factor.
 *
 * Per ANDROID-DESIGN §6.6, every screen MUST work on compact /
 * medium / expanded. Adaptive concerns belong here at the root, not
 * inside per-feature screens.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AppRoot() {
    // FILL IN: replace with your destination enum. Survives process death
    // via rememberSaveable; the actual ViewModel state survives via
    // SavedStateHandle (Hilt-injected).
    var selectedTab by rememberSaveable { mutableStateOf("home") }

    NavigationSuiteScaffold(
        navigationSuiteItems = {
            // FILL IN: navigation destinations
            // item(
            //     selected = selectedTab == "home",
            //     onClick = { selectedTab = "home" },
            //     icon = { Icon(Icons.Default.Home, null) },
            //     label = { Text("Home") },
            // )
        },
    ) {
        Scaffold(
            topBar = {
                CenterAlignedTopAppBar(
                    title = { Text("App Name") },
                    colors = TopAppBarDefaults.centerAlignedTopAppBarColors(),
                )
            },
        ) { padding ->
            // FILL IN: route to per-destination Composable
            Column(
                modifier = Modifier.fillMaxSize().padding(padding).padding(24.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center,
            ) {
                Text("Welcome — selected: $selectedTab")
                Text(
                    "Size class: ${currentWindowAdaptiveInfo().windowSizeClass}",
                )
            }
        }
    }
}
