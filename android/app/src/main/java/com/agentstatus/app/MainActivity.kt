package com.agentstatus.app

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.animateColorAsState
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Devices
import androidx.compose.material.icons.outlined.Home
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.Badge
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.lifecycle.viewmodel.compose.viewModel
import com.agentstatus.app.data.repo.StatusUiState
import com.agentstatus.app.domain.MachineUi
import com.agentstatus.app.domain.SessionState
import com.agentstatus.app.domain.SessionUi
import com.agentstatus.app.service.StatusMonitorService
import com.agentstatus.app.ui.MainViewModel
import com.agentstatus.app.ui.theme.AgentStatusTheme
import com.agentstatus.app.ui.theme.StatusPalette

private enum class AppTab { Home, Devices, Settings }

private data class StatusCounts(
    val confirm: Int = 0,
    val working: Int = 0,
    val done: Int = 0,
    val idle: Int = 0,
) {
    val active: Int get() = confirm + working + done
    val total: Int get() = active + idle
}

class MainActivity : ComponentActivity() {
    private val permissionLauncher =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { /* no-op */ }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= 33) {
            val granted = ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED
            if (!granted) permissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
        StatusMonitorService.start(this)
        setContent {
            AgentStatusTheme {
                val vm: MainViewModel = viewModel()
                AppRoot(vm)
            }
        }
    }

    override fun onStart() {
        super.onStart()
        StatusMonitorService.start(this)
        runCatching { (application as AgentStatusApp).repository.reconnectNow() }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AppRoot(vm: MainViewModel) {
    val state by vm.state.collectAsState()
    var tab by remember { mutableStateOf(AppTab.Home) }
    var selectedMachineId by remember { mutableStateOf<String?>(null) }

    BackHandler(enabled = selectedMachineId != null) {
        selectedMachineId = null
    }

    if (!state.configured) {
        FirstRunScreen(onSave = { url, key -> vm.saveConfig(url, key) })
        return
    }

    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            TopAppBar(
                title = {
                    Column {
                        Text(
                            when {
                                selectedMachineId != null -> "设备会话"
                                tab == AppTab.Home -> "总览"
                                tab == AppTab.Devices -> "设备"
                                else -> "设置"
                            },
                            fontWeight = FontWeight.SemiBold,
                        )
                        Text(
                            connectionLabel(state),
                            style = MaterialTheme.typography.labelMedium,
                            color = if (state.connected) {
                                MaterialTheme.colorScheme.secondary
                            } else {
                                MaterialTheme.colorScheme.error
                            },
                        )
                    }
                },
                navigationIcon = {
                    if (selectedMachineId != null) {
                        TextButton(onClick = { selectedMachineId = null }) { Text("返回") }
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.background,
                ),
            )
        },
        bottomBar = {
            if (selectedMachineId == null) {
                val confirmCount = countMachineStatuses(state.machines).confirm
                NavigationBar(
                    containerColor = MaterialTheme.colorScheme.surface,
                    tonalElevation = 3.dp,
                ) {
                    val itemColors = NavigationBarItemDefaults.colors(
                        indicatorColor = MaterialTheme.colorScheme.primaryContainer,
                    )
                    NavigationBarItem(
                        selected = tab == AppTab.Home,
                        onClick = { tab = AppTab.Home },
                        colors = itemColors,
                        icon = {
                            if (confirmCount > 0) {
                                BadgedBox(badge = { Badge { Text("$confirmCount") } }) {
                                    Icon(Icons.Outlined.Home, contentDescription = "总览")
                                }
                            } else {
                                Icon(Icons.Outlined.Home, contentDescription = "总览")
                            }
                        },
                        label = { Text("总览") },
                    )
                    NavigationBarItem(
                        selected = tab == AppTab.Devices,
                        onClick = { tab = AppTab.Devices },
                        colors = itemColors,
                        icon = { Icon(Icons.Outlined.Devices, contentDescription = "设备") },
                        label = { Text("设备") },
                    )
                    NavigationBarItem(
                        selected = tab == AppTab.Settings,
                        onClick = { tab = AppTab.Settings },
                        colors = itemColors,
                        icon = { Icon(Icons.Outlined.Settings, contentDescription = "设置") },
                        label = { Text("设置") },
                    )
                }
            }
        },
    ) { pad ->
        when {
            selectedMachineId != null -> {
                val machine = state.machines.firstOrNull { it.id == selectedMachineId }
                DeviceDetailScreen(
                    padding = pad,
                    machine = machine,
                    error = state.error,
                    loading = state.loading,
                )
            }
            tab == AppTab.Home -> HomeScreen(
                padding = pad,
                state = state,
                onOpenMachine = { selectedMachineId = it },
            )
            tab == AppTab.Devices -> DevicesScreen(
                padding = pad,
                state = state,
                onOpenMachine = { selectedMachineId = it },
            )
            else -> SettingsScreen(
                padding = pad,
                state = state,
                onSaveConfig = { url, key -> vm.saveConfig(url, key) },
                onSaveNotify = { r, y, g -> vm.saveNotify(r, y, g) },
            )
        }
    }
}

@Composable
private fun NavGlyph(text: String, selected: Boolean) {
    val color by animateColorAsState(
        if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
        label = "nav",
    )
    Text(text, color = color, fontSize = 16.sp)
}

private fun connectionLabel(state: StatusUiState): String = when {
    state.error != null -> "界面异常 · 请看后台监听通知"
    state.connected -> "界面已连接"
    state.loading -> "同步中…"
    else -> "界面未连接 · 后台可能仍在监听"
}

private fun countMachineStatuses(machines: List<MachineUi>): StatusCounts {
    var c = 0
    var w = 0
    var d = 0
    var i = 0
    machines.forEach { m ->
        m.sessions.forEach { s ->
            when (s.state) {
                SessionState.Confirm -> c++
                SessionState.Working -> w++
                SessionState.Done -> d++
                SessionState.Idle -> i++
            }
        }
    }
    return StatusCounts(c, w, d, i)
}

private fun countSessionStatuses(sessions: List<SessionUi>): StatusCounts {
    var c = 0
    var w = 0
    var d = 0
    var i = 0
    sessions.forEach { s ->
        when (s.state) {
            SessionState.Confirm -> c++
            SessionState.Working -> w++
            SessionState.Done -> d++
            SessionState.Idle -> i++
        }
    }
    return StatusCounts(c, w, d, i)
}

@Composable
private fun FirstRunScreen(onSave: (String, String) -> Unit) {
    Scaffold(containerColor = MaterialTheme.colorScheme.background) { pad ->
        Column(
            Modifier
                .fillMaxSize()
                .padding(pad)
                .padding(20.dp),
            verticalArrangement = Arrangement.Center,
        ) {
            OverviewHero()
            Spacer(Modifier.height(20.dp))
            Text("连接私有服务", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
            Spacer(Modifier.height(8.dp))
            Text(
                "填写服务地址与预共享密钥后，即可总览多机 Agent 状态。",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(Modifier.height(20.dp))
            ConfigForm(onSave = onSave)
        }
    }
}

@Composable
private fun OverviewHero() {
    Box(
        Modifier
            .fillMaxWidth()
            .height(120.dp)
            .clip(RoundedCornerShape(24.dp))
            .background(
                Brush.linearGradient(
                    listOf(
                        MaterialTheme.colorScheme.primary,
                        MaterialTheme.colorScheme.secondary,
                    ),
                ),
            )
            .padding(20.dp),
    ) {
        Column {
            Text("Agent Status", color = Color.White, fontWeight = FontWeight.Bold, fontSize = 22.sp)
            Spacer(Modifier.height(6.dp))
            Text("多端会话状态 · 实时总览", color = Color.White.copy(alpha = 0.9f))
        }
    }
}

@Composable
private fun HomeScreen(
    padding: PaddingValues,
    state: StatusUiState,
    onOpenMachine: (String) -> Unit,
) {
    val counts = remember(state.machines) { countMachineStatuses(state.machines) }
    val active = state.machines
        .flatMap { m -> m.sessions.filter { it.state != SessionState.Idle }.map { it to m } }
        .sortedWith(
            compareByDescending<Pair<SessionUi, MachineUi>> { it.first.state.priority() }
                .thenBy { it.second.name },
        )
    val onlineMachines = state.machines.count { it.online }

    LazyColumn(
        Modifier
            .fillMaxSize()
            .padding(padding)
            .padding(horizontal = 16.dp),
        contentPadding = PaddingValues(vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item {
            ConnectionBanner(connected = state.connected, error = state.error)
        }
        item {
            OverviewDashboard(
                counts = counts,
                machineTotal = state.machines.size,
                machineOnline = onlineMachines,
            )
        }
        item {
            SectionTitle("活跃任务", trailing = "${active.size}")
        }
        if (active.isEmpty()) {
            item {
                EmptyPanel(
                    title = "当前没有活跃任务",
                    subtitle = "确认中 / 工作中 / 刚完成 的会话会出现在这里",
                )
            }
        } else {
            items(active, key = { it.first.key }) { (session, machine) ->
                SessionCard(
                    session = session.copy(machineId = machine.id, machineName = machine.name),
                    onClick = { onOpenMachine(machine.id) },
                )
            }
        }
    }
}

@Composable
private fun DevicesScreen(
    padding: PaddingValues,
    state: StatusUiState,
    onOpenMachine: (String) -> Unit,
) {
    val counts = remember(state.machines) { countMachineStatuses(state.machines) }
    LazyColumn(
        Modifier
            .fillMaxSize()
            .padding(padding)
            .padding(horizontal = 16.dp),
        contentPadding = PaddingValues(vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item {
            OverviewDashboard(
                counts = counts,
                machineTotal = state.machines.size,
                machineOnline = state.machines.count { it.online },
            )
        }
        item { SectionTitle("全部设备", trailing = "${state.machines.size}") }
        if (state.machines.isEmpty()) {
            item { EmptyPanel("还没有设备", "监控端上报后会出现在这里") }
        } else {
            items(state.machines, key = { it.id }) { machine ->
                MachineCard(machine = machine, onClick = { onOpenMachine(machine.id) })
            }
        }
    }
}

@Composable
private fun DeviceDetailScreen(
    padding: PaddingValues,
    machine: MachineUi?,
    error: String?,
    loading: Boolean,
) {
    if (machine == null) {
        Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
            EmptyPanel("设备不存在", "可能已离线或尚未上报")
        }
        return
    }
    val counts = remember(machine.sessions) { countSessionStatuses(machine.sessions) }
    val active = machine.sessions.filter { it.state != SessionState.Idle }
        .sortedByDescending { it.state.priority() }
    val idle = machine.sessions.filter { it.state == SessionState.Idle }
    var showIdle by remember { mutableStateOf(false) }

    LazyColumn(
        Modifier
            .fillMaxSize()
            .padding(padding)
            .padding(horizontal = 16.dp),
        contentPadding = PaddingValues(vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item {
            MachineHero(machine = machine, counts = counts)
        }
        if (error != null) {
            item {
                Text(error, color = MaterialTheme.colorScheme.error)
            }
        }
        item { SectionTitle("会话", trailing = "${machine.sessions.size}") }
        if (active.isEmpty() && idle.isEmpty()) {
            item {
                EmptyPanel(
                    "暂无会话",
                    if (loading) "加载中…" else "该设备当前没有会话记录",
                )
            }
        } else {
            items(active, key = { it.key }) { session ->
                SessionCard(session = session.copy(machineName = machine.name, machineId = machine.id))
            }
            if (idle.isNotEmpty()) {
                item {
                    OutlinedButton(
                        onClick = { showIdle = !showIdle },
                        modifier = Modifier.fillMaxWidth(),
                        shape = RoundedCornerShape(12.dp),
                    ) {
                        Text(if (showIdle) "收起空闲 · ${idle.size}" else "展开空闲 · ${idle.size}")
                    }
                }
                if (showIdle) {
                    items(idle, key = { it.key }) { session ->
                        SessionCard(session = session.copy(machineName = machine.name, machineId = machine.id))
                    }
                }
            }
        }
    }
}

@Composable
private fun ConnectionBanner(connected: Boolean, error: String?) {
    val ok = connected && error == null
    val bg = if (ok) Color(0xFFECFDF5) else Color(0xFFFEF2F2)
    val fg = if (ok) Color(0xFF047857) else Color(0xFFB91C1C)
    val dark = MaterialTheme.colorScheme.background == Color(0xFF0B1220)
    Surface(
        color = if (dark) {
            if (ok) Color(0xFF064E3B).copy(alpha = 0.35f) else Color(0xFF7F1D1D).copy(alpha = 0.35f)
        } else {
            bg
        },
        shape = MaterialTheme.shapes.medium,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Row(
            Modifier.padding(horizontal = 14.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            PulseDot(active = ok, color = if (ok) StatusPalette.Done else StatusPalette.Confirm)
            Spacer(Modifier.width(10.dp))
            Column(Modifier.weight(1f)) {
                Text(
                    if (ok) "实时链路正常" else "界面链路异常",
                    fontWeight = FontWeight.SemiBold,
                    color = if (dark) MaterialTheme.colorScheme.onSurface else fg,
                )
                Text(
                    if (ok) "列表会随 WebSocket 推送更新" else "后台监听进程可能仍在收通知",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@Composable
private fun OverviewDashboard(
    counts: StatusCounts,
    machineTotal: Int,
    machineOnline: Int,
) {
    Card(
        shape = MaterialTheme.shapes.large,
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.cardElevation(defaultElevation = 3.dp),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column {
                    Text("状态总览", fontWeight = FontWeight.Bold, style = MaterialTheme.typography.titleMedium)
                    Text(
                        "设备 $machineOnline/$machineTotal 在线 · 活跃 ${counts.active}",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                StatusRing(counts = counts, size = 64.dp)
            }

            StatusStackedBar(counts = counts)

            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                StatTile(
                    modifier = Modifier.weight(1f),
                    label = "需确认",
                    value = counts.confirm,
                    color = statusColor(SessionState.Confirm),
                )
                StatTile(
                    modifier = Modifier.weight(1f),
                    label = "工作中",
                    value = counts.working,
                    color = statusColor(SessionState.Working),
                )
                StatTile(
                    modifier = Modifier.weight(1f),
                    label = "完成",
                    value = counts.done,
                    color = statusColor(SessionState.Done),
                )
                StatTile(
                    modifier = Modifier.weight(1f),
                    label = "空闲",
                    value = counts.idle,
                    color = statusColor(SessionState.Idle),
                )
            }
        }
    }
}

@Composable
private fun StatTile(
    modifier: Modifier = Modifier,
    label: String,
    value: Int,
    color: Color,
) {
    Column(
        modifier
            .clip(RoundedCornerShape(14.dp))
            .background(color.copy(alpha = 0.12f))
            .padding(vertical = 10.dp, horizontal = 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text("$value", fontWeight = FontWeight.Bold, color = color, fontSize = 18.sp)
        Text(label, style = MaterialTheme.typography.labelSmall, color = color)
    }
}

@Composable
private fun StatusStackedBar(counts: StatusCounts, height: Dp = 12.dp) {
    val total = counts.total.coerceAtLeast(1)
    val segments = listOf(
        counts.confirm to statusColor(SessionState.Confirm),
        counts.working to statusColor(SessionState.Working),
        counts.done to statusColor(SessionState.Done),
        counts.idle to statusColor(SessionState.Idle),
    )
    Row(
        Modifier
            .fillMaxWidth()
            .height(height)
            .clip(RoundedCornerShape(999.dp))
            .background(MaterialTheme.colorScheme.surfaceVariant),
    ) {
        segments.forEach { (count, color) ->
            if (count > 0) {
                Box(
                    Modifier
                        .weight(count.toFloat())
                        .fillMaxHeight()
                        .background(color),
                )
            }
        }
        // keep bar visible when empty
        if (segments.all { it.first == 0 }) {
            Box(Modifier.weight(1f).fillMaxHeight())
        }
    }
    // silence unused warning when total only used conceptually
    @Suppress("UNUSED_EXPRESSION")
    total
}

@Composable
private fun StatusRing(counts: StatusCounts, size: Dp) {
    val total = counts.total.coerceAtLeast(1).toFloat()
    val parts = listOf(
        counts.confirm / total to statusColor(SessionState.Confirm),
        counts.working / total to statusColor(SessionState.Working),
        counts.done / total to statusColor(SessionState.Done),
        counts.idle / total to statusColor(SessionState.Idle),
    )
    Box(Modifier.size(size), contentAlignment = Alignment.Center) {
        Canvas(Modifier.fillMaxSize()) {
            val stroke = Stroke(width = 10.dp.toPx(), cap = StrokeCap.Butt)
            var start = -90f
            val diameter = this.size.minDimension
            val topLeft = Offset((this.size.width - diameter) / 2f, (this.size.height - diameter) / 2f)
            val arcSize = Size(diameter, diameter)
            if (counts.total == 0) {
                drawArc(
                    color = Color(0xFFCBD5E1),
                    startAngle = 0f,
                    sweepAngle = 360f,
                    useCenter = false,
                    topLeft = topLeft,
                    size = arcSize,
                    style = stroke,
                )
            } else {
                parts.forEach { (ratio, color) ->
                    val sweep = ratio * 360f
                    if (sweep > 0f) {
                        drawArc(
                            color = color,
                            startAngle = start,
                            sweepAngle = sweep,
                            useCenter = false,
                            topLeft = topLeft,
                            size = arcSize,
                            style = stroke,
                        )
                        start += sweep
                    }
                }
            }
        }
        Text(
            "${counts.active}",
            fontWeight = FontWeight.Bold,
            style = MaterialTheme.typography.titleMedium,
        )
    }
}

@Composable
private fun MachineHero(machine: MachineUi, counts: StatusCounts) {
    Card(
        shape = MaterialTheme.shapes.large,
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.cardElevation(defaultElevation = 3.dp),
    ) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                PulseDot(active = machine.online, color = if (machine.online) StatusPalette.Online else StatusPalette.Idle)
                Spacer(Modifier.width(10.dp))
                Column(Modifier.weight(1f)) {
                    Text(machine.name, fontWeight = FontWeight.Bold, style = MaterialTheme.typography.titleLarge)
                    Text(
                        buildString {
                            append(if (machine.online) "在线" else "离线")
                            append(" · ")
                            append(machine.platform.ifBlank { "unknown" })
                            if (machine.version.isNotBlank()) {
                                append(" · ")
                                append(machine.version)
                            }
                        },
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        style = MaterialTheme.typography.bodyMedium,
                    )
                }
                StatusRing(counts = counts, size = 56.dp)
            }
            StatusStackedBar(counts = counts, height = 10.dp)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                StatTile(Modifier.weight(1f), "确认", counts.confirm, statusColor(SessionState.Confirm))
                StatTile(Modifier.weight(1f), "工作", counts.working, statusColor(SessionState.Working))
                StatTile(Modifier.weight(1f), "完成", counts.done, statusColor(SessionState.Done))
                StatTile(Modifier.weight(1f), "空闲", counts.idle, statusColor(SessionState.Idle))
            }
        }
    }
}

@Composable
private fun MachineCard(machine: MachineUi, onClick: () -> Unit) {
    val counts = remember(machine.sessions) { countSessionStatuses(machine.sessions) }
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick),
        shape = MaterialTheme.shapes.large,
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp),
    ) {
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                PulseDot(active = machine.online, color = if (machine.online) StatusPalette.Online else StatusPalette.Idle)
                Spacer(Modifier.width(10.dp))
                Column(Modifier.weight(1f)) {
                    Text(machine.name, fontWeight = FontWeight.SemiBold, style = MaterialTheme.typography.titleMedium)
                    Text(
                        buildString {
                            append(machine.platform.ifBlank { "unknown" })
                            if (machine.version.isNotBlank()) {
                                append(" · ")
                                append(machine.version)
                            }
                            append(" · 会话 ${machine.sessions.size}")
                        },
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                Text("查看", color = MaterialTheme.colorScheme.primary, fontWeight = FontWeight.Medium)
            }
            StatusStackedBar(counts = counts, height = 8.dp)
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                MiniBadge("确认 ${counts.confirm}", statusColor(SessionState.Confirm))
                MiniBadge("工作 ${counts.working}", statusColor(SessionState.Working))
                MiniBadge("完成 ${counts.done}", statusColor(SessionState.Done))
            }
        }
    }
}

@Composable
private fun SessionCard(session: SessionUi, onClick: (() -> Unit)? = null) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier),
        shape = MaterialTheme.shapes.large,
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp),
    ) {
        Row(Modifier.padding(14.dp)) {
            Box(
                Modifier
                    .width(5.dp)
                    .height(64.dp)
                    .clip(RoundedCornerShape(8.dp))
                    .background(statusColor(session.state)),
            )
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    StatusChip(session.state)
                    Spacer(Modifier.width(8.dp))
                    AgentBadge(session.agent)
                    Spacer(Modifier.weight(1f))
                    if (session.updatedLabel.isNotBlank()) {
                        Text(
                            session.updatedLabel,
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
                Text(
                    session.title,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    session.subtitle,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}

@Composable
private fun AgentBadge(agent: String) {
    if (agent.isBlank()) return
    val color = when (agent.lowercase()) {
        "claude" -> Color(0xFFD97706)
        "codex" -> Color(0xFF2563EB)
        else -> MaterialTheme.colorScheme.primary
    }
    Surface(color = color.copy(alpha = 0.12f), shape = RoundedCornerShape(999.dp)) {
        Text(
            agent,
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 2.dp),
            style = MaterialTheme.typography.labelSmall,
            color = color,
            fontWeight = FontWeight.SemiBold,
        )
    }
}

@Composable
private fun MiniBadge(text: String, color: Color) {
    Surface(color = color.copy(alpha = 0.12f), shape = RoundedCornerShape(999.dp)) {
        Text(
            text,
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 3.dp),
            style = MaterialTheme.typography.labelSmall,
            color = color,
            fontWeight = FontWeight.Medium,
        )
    }
}

@Composable
private fun StatusChip(state: SessionState) {
    Surface(
        color = statusColor(state).copy(alpha = 0.16f),
        shape = RoundedCornerShape(999.dp),
    ) {
        Text(
            state.labelZh,
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 2.dp),
            style = MaterialTheme.typography.labelSmall,
            color = statusColor(state),
            fontWeight = FontWeight.SemiBold,
        )
    }
}

@Composable
private fun PulseDot(active: Boolean, color: Color) {
    Box(contentAlignment = Alignment.Center, modifier = Modifier.size(14.dp)) {
        if (active) {
            Box(
                Modifier
                    .size(14.dp)
                    .background(color.copy(alpha = 0.25f), CircleShape),
            )
        }
        Box(
            Modifier
                .size(8.dp)
                .background(color, CircleShape),
        )
    }
}

@Composable
private fun SectionTitle(title: String, trailing: String? = null) {
    Row(
        Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, fontWeight = FontWeight.SemiBold, style = MaterialTheme.typography.titleMedium)
        if (trailing != null) {
            Text(trailing, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun EmptyPanel(title: String, subtitle: String) {
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(18.dp))
            .border(1.dp, MaterialTheme.colorScheme.outline.copy(alpha = 0.4f), RoundedCornerShape(18.dp))
            .padding(28.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(
            Modifier
                .size(48.dp)
                .background(MaterialTheme.colorScheme.surfaceVariant, CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            Text("∅", fontSize = 20.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Spacer(Modifier.height(12.dp))
        Text(title, fontWeight = FontWeight.SemiBold)
        Spacer(Modifier.height(6.dp))
        Text(
            subtitle,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun SettingsScreen(
    padding: PaddingValues,
    state: StatusUiState,
    onSaveConfig: (String, String) -> Unit,
    onSaveNotify: (Boolean, Boolean, Boolean) -> Unit,
) {
    val context = LocalContext.current
    LazyColumn(
        Modifier
            .fillMaxSize()
            .padding(padding)
            .padding(horizontal = 16.dp),
        contentPadding = PaddingValues(vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        item {
            ConnectionBanner(connected = state.connected, error = state.error)
        }
        item {
            SettingsSectionCard(title = "服务连接") {
                ConfigForm(compact = true, onSave = onSaveConfig)
            }
        }
        item {
            SettingsSectionCard(title = "通知开关") {
                Text(
                    "默认只开红色（需确认）。摘要会出现在通知正文。",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Spacer(Modifier.height(10.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    FilterChip(
                        selected = state.notifyRed,
                        onClick = { onSaveNotify(!state.notifyRed, state.notifyYellow, state.notifyGreen) },
                        label = { Text("红 · 确认") },
                    )
                    FilterChip(
                        selected = state.notifyYellow,
                        onClick = { onSaveNotify(state.notifyRed, !state.notifyYellow, state.notifyGreen) },
                        label = { Text("黄 · 工作中") },
                    )
                    FilterChip(
                        selected = state.notifyGreen,
                        onClick = { onSaveNotify(state.notifyRed, state.notifyYellow, !state.notifyGreen) },
                        label = { Text("绿 · 完成") },
                    )
                }
            }
        }
        item {
            SettingsSectionCard(title = "后台保活") {
                Text(
                    "需要常驻「后台监听」通知。部分系统还要关闭电池优化。",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Spacer(Modifier.height(10.dp))
                Button(
                    onClick = { StatusMonitorService.start(context) },
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(12.dp),
                ) { Text("重新启动后台监听") }
                Spacer(Modifier.height(8.dp))
                OutlinedButton(
                    onClick = {
                        val pm = context.getSystemService(PowerManager::class.java)
                        val pkg = context.packageName
                        val intent = if (pm != null && !pm.isIgnoringBatteryOptimizations(pkg)) {
                            Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                                data = Uri.parse("package:$pkg")
                            }
                        } else {
                            Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                        }
                        runCatching { context.startActivity(intent) }
                    },
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(12.dp),
                ) { Text("关闭电池优化") }
                Spacer(Modifier.height(8.dp))
                OutlinedButton(
                    onClick = {
                        val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                            putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
                        }
                        runCatching { context.startActivity(intent) }
                    },
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(12.dp),
                ) { Text("打开通知设置") }
            }
        }
    }
}

@Composable
private fun SettingsSectionCard(title: String, content: @Composable () -> Unit) {
    Card(
        shape = MaterialTheme.shapes.large,
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(Modifier.padding(16.dp)) {
            Text(title, fontWeight = FontWeight.SemiBold, style = MaterialTheme.typography.titleMedium)
            Spacer(Modifier.height(10.dp))
            content()
        }
    }
}

@Composable
private fun ConfigForm(compact: Boolean = false, onSave: (String, String) -> Unit) {
    var url by remember { mutableStateOf("") }
    var key by remember { mutableStateOf("") }
    Column {
        if (compact) {
            Text("服务地址与密钥", style = MaterialTheme.typography.bodyMedium)
            Spacer(Modifier.height(8.dp))
        }
        OutlinedTextField(
            value = url,
            onValueChange = { url = it },
            label = { Text("Server URL") },
            placeholder = { Text("http://100.x.x.x:8080") },
            modifier = Modifier.fillMaxWidth(),
            singleLine = true,
            shape = RoundedCornerShape(12.dp),
        )
        Spacer(Modifier.height(8.dp))
        OutlinedTextField(
            value = key,
            onValueChange = { key = it },
            label = { Text("预共享密钥") },
            modifier = Modifier.fillMaxWidth(),
            singleLine = true,
            shape = RoundedCornerShape(12.dp),
        )
        Button(
            onClick = { onSave(url.trim(), key.trim()) },
            modifier = Modifier
                .padding(top = 12.dp)
                .fillMaxWidth(),
            enabled = url.isNotBlank() && key.isNotBlank(),
            shape = RoundedCornerShape(12.dp),
        ) {
            Text("保存")
        }
    }
}

private fun statusColor(state: SessionState): Color = when (state) {
    SessionState.Confirm -> StatusPalette.Confirm
    SessionState.Working -> StatusPalette.Working
    SessionState.Done -> StatusPalette.Done
    SessionState.Idle -> StatusPalette.Idle
}

private fun SessionState.priority(): Int = when (this) {
    SessionState.Confirm -> 4
    SessionState.Working -> 3
    SessionState.Done -> 2
    SessionState.Idle -> 1
}
