<?php
/**
 * PVE UPS Monitor v0.5.0
 * 完整 UPS 监控系统 - PHP 单文件版
 * 安全修复: 配置文件移出 Web 根目录, 输入过滤, AJAX 异步刷新
 */
error_reporting(E_ALL & ~E_NOTICE & ~E_WARNING);

// ─── 数据目录 (Web 根目录外, 防止敏感信息泄露) ───
$DATA_DIR = '/var/lib/ups-monitor';
if (!is_dir($DATA_DIR)) { @mkdir($DATA_DIR, 0755, true); }

$CONFIG_FILE  = "$DATA_DIR/config.json";
$HISTORY_FILE = "$DATA_DIR/history.json";
$LOG_FILE     = "$DATA_DIR/events.log";
$TOKEN_FILE   = "$DATA_DIR/pushplus-token.txt";

$DEFAULT_CONFIG = [
    'refresh'        => 10,
    'low_battery'    => 20,
    'shutdown_delay' => 120,
    'ups_host'       => '127.0.0.1',
    'ups_name'       => 'ups0',
    'theme'          => 'dark',
    'pushplus_token' => '',
];

// ─── 加载配置 ───
if (!file_exists($CONFIG_FILE)) {
    file_put_contents($CONFIG_FILE, json_encode($DEFAULT_CONFIG, JSON_PRETTY_PRINT));
}
$config = json_decode(file_get_contents($CONFIG_FILE), true) ?: [];
foreach ($DEFAULT_CONFIG as $k => $v) {
    if (!isset($config[$k])) $config[$k] = $v;
}

// ─── 安全: 过滤 UPS 连接参数 (防止命令注入) ───
function sanitize_host($s) { return preg_replace('/[^a-zA-Z0-9.\-:]/', '', $s); }
function sanitize_name($s) { return preg_replace('/[^a-zA-Z0-9_\-]/', '', $s); }

$ups_host = sanitize_host($config['ups_host']);
$ups_name = sanitize_name($config['ups_name']);
$ups      = "$ups_name@$ups_host";

// ─── 日志 (带轮转, 最大 1MB) ───
function log_event($type, $msg) {
    global $LOG_FILE;
    $line = "[" . date('Y-m-d H:i:s') . "] [$type] $msg\n";
    file_put_contents($LOG_FILE, $line, FILE_APPEND | LOCK_EX);
    if (file_exists($LOG_FILE) && filesize($LOG_FILE) > 1048576) {
        rename($LOG_FILE, "$LOG_FILE.old");
    }
}

// ─── 获取 UPS 数据 (安全执行 upsc) ───
function get_ups_value($key, $ups) {
    $cmd = "upsc " . escapeshellarg($ups) . " " . escapeshellarg($key) . " 2>/dev/null";
    return trim(shell_exec($cmd));
}

function get_ups_data($ups) {
    $keys = [
        'ups.status', 'battery.charge', 'battery.runtime', 'ups.load',
        'input.voltage', 'output.voltage', 'battery.voltage',
        'ups.model', 'ups.mfr', 'ups.realpower.nominal',
        'input.frequency', 'ups.beeper.status',
        'battery.temperature', 'ups.firmware', 'ups.serial',
    ];
    $data = [];
    foreach ($keys as $key) {
        $val = get_ups_value($key, $ups);
        if ($val !== '') $data[$key] = $val;
    }
    return $data;
}

// ─── 获取 PVE 系统状态 ───
function get_pve_stats() {
    $s = [];
    $cpu = trim(shell_exec("top -bn1 | grep 'Cpu(s)' | awk '{print \$2}' | cut -d'%' -f1 2>/dev/null"));
    $s['cpu'] = $cpu !== '' ? round(floatval($cpu), 1) : 0;
    $load = trim(shell_exec("uptime | awk -F'load average:' '{print \$2}' | cut -d',' -f1 2>/dev/null"));
    $s['load'] = $load !== '' ? trim($load) : '0.00';
    $mem_total = intval(shell_exec("free -m | grep Mem | awk '{print \$2}' 2>/dev/null"));
    $mem_used  = intval(shell_exec("free -m | grep Mem | awk '{print \$3}' 2>/dev/null"));
    $s['mem_total']   = $mem_total;
    $s['mem_used']    = $mem_used;
    $s['mem_percent'] = $mem_total > 0 ? round(($mem_used / $mem_total) * 100, 1) : 0;
    $s['disk']    = trim(shell_exec("df -h / | awk 'NR==2{print \$5}' 2>/dev/null")) ?: '0%';
    $s['uptime']  = trim(shell_exec("uptime -p 2>/dev/null")) ?: '未知';
    return $s;
}

// ─── PushPlus 微信通知 ───
function send_pushplus($token, $title, $content) {
    if (empty($token)) return false;
    $data = json_encode(['token' => $token, 'title' => $title, 'content' => $content, 'template' => 'html']);
    $opts = ['http' => ['method' => 'POST', 'header' => "Content-Type: application/json\r\n", 'content' => $data, 'timeout' => 10]];
    $ctx = stream_context_create($opts);
    return @file_get_contents('https://www.pushplus.plus/send', false, $ctx) !== false;
}

function get_token() {
    global $TOKEN_FILE, $config;
    $t = '';
    if (file_exists($TOKEN_FILE)) $t = trim(file_get_contents($TOKEN_FILE));
    if (empty($t) && !empty($config['pushplus_token'])) $t = $config['pushplus_token'];
    return $t;
}

// ═══════════════════════════════════════════
// AJAX API 处理
// ═══════════════════════════════════════════
if (isset($_GET['api'])) {
    header('Content-Type: application/json; charset=utf-8');
    $action = $_GET['api'];

    switch ($action) {
        case 'data':
            $ups_data  = get_ups_data($ups);
            $pve_stats = get_pve_stats();
            $status    = $ups_data['ups.status'] ?? '';
            $is_online   = strpos($status, 'OL') !== false;
            $is_connected = !empty($status);
            $charge      = intval($ups_data['battery.charge'] ?? 0);
            $runtime     = intval($ups_data['battery.runtime'] ?? 0);
            $runtime_min = $runtime > 0 ? round($runtime / 60, 1) : 0;

            // 保存历史
            $history = [];
            if (file_exists($HISTORY_FILE)) {
                $history = json_decode(file_get_contents($HISTORY_FILE), true) ?: [];
            }
            $history[] = ['time' => date('H:i'), 'charge' => $charge, 'status' => $is_online ? 'OL' : 'OB'];
            if (count($history) > 30) array_shift($history);
            file_put_contents($HISTORY_FILE, json_encode($history), LOCK_EX);

            // 告警检测
            $alert = null;
            if ($is_connected && !$is_online && $charge < 50) {
                $alert = ['type' => 'power_outage', 'charge' => $charge, 'runtime' => $runtime_min];
                log_event('告警', "UPS 切换到电池模式, 电量 {$charge}%, 剩余 {$runtime_min} 分钟");
                // 微信推送
                $token = get_token();
                if (!empty($token)) {
                    $msg = "<h3>UPS 断电告警</h3><p>UPS 已切换到电池模式</p><p>电量: {$charge}% | 剩余: {$runtime_min} 分钟</p><p>时间: " . date('Y-m-d H:i:s') . "</p>";
                    send_pushplus($token, 'UPS 断电告警', $msg);
                    log_event('微信', "断电告警已推送到微信");
                }
            }

            echo json_encode([
                'success'   => true,
                'connected' => $is_connected,
                'online'    => $is_online,
                'ups'       => $ups_data,
                'pve'       => $pve_stats,
                'history'   => $history,
                'alert'     => $alert,
                'time'      => date('Y-m-d H:i:s'),
            ], JSON_UNESCAPED_UNICODE);
            exit;

        case 'logs':
            $logs = [];
            if (file_exists($LOG_FILE) && filesize($LOG_FILE) > 0) {
                $logs = array_slice(array_reverse(file($LOG_FILE, FILE_IGNORE_NEW_LINES)), 0, 100);
            }
            echo json_encode(['success' => true, 'logs' => $logs], JSON_UNESCAPED_UNICODE);
            exit;

        case 'clear_history':
            file_put_contents($HISTORY_FILE, '[]', LOCK_EX);
            log_event('操作', '历史记录已清空');
            echo json_encode(['success' => true]);
            exit;

        case 'clear_logs':
            file_put_contents($LOG_FILE, '', LOCK_EX);
            echo json_encode(['success' => true]);
            exit;

        case 'test_wechat':
            $token = get_token();
            if (empty($token)) {
                echo json_encode(['success' => false, 'message' => '未配置 PushPlus Token']);
                exit;
            }
            $msg = '<h3>UPS 监控测试</h3><p>微信通知测试成功</p><p>时间: ' . date('Y-m-d H:i:s') . '</p>';
            $ok = send_pushplus($token, 'UPS 监控测试', $msg);
            log_event('微信', $ok ? '测试通知已发送' : '测试通知发送失败');
            echo json_encode(['success' => $ok, 'message' => $ok ? '测试通知已发送' : '发送失败, 请检查 Token']);
            exit;

        case 'selftest':
            $cmd = "upscmd -u " . escapeshellarg(sanitize_name($_POST['user'] ?? 'admin')) .
                   " -p " . escapeshellarg($_POST['pass'] ?? 'admin123') .
                   " " . escapeshellarg($ups) . " test.battery.start 2>&1";
            $output = shell_exec($cmd);
            log_event('操作', 'UPS 自检已触发');
            echo json_encode(['success' => true, 'message' => '自检命令已发送', 'output' => $output]);
            exit;
    }
}

// ═══════════════════════════════════════════
// POST: 保存设置
// ═══════════════════════════════════════════
if ($_SERVER['REQUEST_METHOD'] === 'POST' && ($_POST['action'] ?? '') === 'save') {
    $config['refresh']        = max(3, min(60, intval($_POST['refresh'] ?? 10)));
    $config['low_battery']    = max(5, min(50, intval($_POST['low_battery'] ?? 20)));
    $config['shutdown_delay'] = max(10, min(600, intval($_POST['shutdown_delay'] ?? 120)));
    $config['ups_host']       = sanitize_host($_POST['ups_host'] ?? '127.0.0.1');
    $config['ups_name']       = sanitize_name($_POST['ups_name'] ?? 'ups0');
    $config['theme']          = ($_POST['theme'] ?? 'dark') === 'light' ? 'light' : 'dark';

    $new_token = trim($_POST['pushplus_token'] ?? '');
    if (!empty($new_token)) {
        file_put_contents($TOKEN_FILE, $new_token, LOCK_EX);
        $config['pushplus_token'] = $new_token;
        log_event('操作', '微信 Token 已更新');
    }

    file_put_contents($CONFIG_FILE, json_encode($config, JSON_PRETTY_PRINT), LOCK_EX);
    log_event('操作', "设置已保存: 刷新={$config['refresh']}s, 低电量={$config['low_battery']}%, 关机延迟={$config['shutdown_delay']}s");
    header('Location: ?saved=1');
    exit;
}

// ─── 页面变量 ───
$theme      = $config['theme'] ?? 'dark';
$refresh    = intval($config['refresh']);
$low_battery = intval($config['low_battery']);
$has_token  = !empty(get_token());
$just_saved = isset($_GET['saved']);
?>
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>UPS 监控系统 v0.5.0</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
:root{--bg:#1a1a2e;--card:#16213e;--card2:#1a1a3e;--border:#222;--text:#fff;--text2:#888;--shadow:rgba(0,0,0,0.5);--green:#10b981;--green-h:#059669;--red:#ef4444;--orange:#f59e0b;--blue:#3b82f6;--radius:12px}
body.light{--bg:#f0f2f5;--card:#fff;--card2:#e8eaed;--border:#ddd;--text:#1a1a2e;--text2:#666;--shadow:rgba(0,0,0,0.08)}
body{font-family:'Segoe UI',-apple-system,Arial,sans-serif;background:var(--bg);color:var(--text);min-height:100vh;transition:background .3s,color .3s;padding:16px;display:flex;justify-content:center}
.wrap{max-width:900px;width:100%}
.card{background:var(--card);border-radius:var(--radius);padding:24px;margin-bottom:14px;box-shadow:0 4px 20px var(--shadow)}
.hdr{display:flex;align-items:center;justify-content:space-between;flex-wrap:wrap;gap:10px;margin-bottom:4px}
.hdr-l{display:flex;align-items:center;gap:12px}
.hdr-l svg{width:40px;height:40px;flex-shrink:0}
.hdr h1{font-size:20px;font-weight:700}
.hdr .sub{font-size:12px;color:var(--text2);margin-top:2px}
.hdr-r{display:flex;gap:8px;align-items:center;flex-wrap:wrap}
.badge{font-size:11px;padding:3px 10px;border-radius:20px;font-weight:600;display:inline-flex;align-items:center;gap:4px}
.badge.ok{background:rgba(16,185,129,.15);color:var(--green)}
.badge.no{background:rgba(239,68,68,.15);color:var(--red)}
.badge.wait{background:rgba(245,158,11,.15);color:var(--orange)}
.btn{background:var(--green);color:#fff;border:none;padding:8px 16px;border-radius:8px;font-size:13px;font-weight:600;cursor:pointer;transition:.2s;font-family:inherit}
.btn:hover{background:var(--green-h)}
.btn:active{transform:scale(.96)}
.btn-sm{background:var(--card2);color:var(--text);border:1px solid var(--border);padding:6px 12px;border-radius:8px;font-size:12px;cursor:pointer;transition:.2s;font-family:inherit}
.btn-sm:hover{border-color:var(--green);color:var(--green)}
.btn-d{background:var(--red)}.btn-d:hover{background:#dc2626}
.btn-w{background:#07c160}.btn-w:hover{background:#06ad56}
.tabs{display:flex;gap:2px;border-bottom:2px solid var(--border);margin-bottom:16px;overflow-x:auto}
.tab{padding:8px 18px;cursor:pointer;font-weight:600;font-size:13px;background:none;color:var(--text2);border:none;border-bottom:3px solid transparent;transition:.2s;font-family:inherit;white-space:nowrap}
.tab:hover{color:var(--text)}
.tab.act{color:var(--green);border-bottom-color:var(--green)}
.tc{display:none}.tc.act{display:block}
.row{display:flex;justify-content:space-between;align-items:center;padding:8px 0;border-bottom:1px solid var(--border);flex-wrap:wrap;gap:4px}
.label{color:var(--text2);font-size:14px}
.val{font-weight:600}
.online{color:var(--green)}.offline{color:var(--red)}
.bar-bg{background:var(--border);border-radius:6px;height:10px;margin:4px 0 8px;overflow:hidden}
.bar-fill{height:100%;border-radius:6px;transition:width .5s,background .3s}
.grid3{display:grid;grid-template-columns:repeat(3,1fr);gap:10px;margin-top:8px}
.grid2{display:grid;grid-template-columns:repeat(2,1fr);gap:10px}
.metric{background:var(--card2);padding:12px;border-radius:10px;text-align:center}
.metric .ml{font-size:11px;color:var(--text2);text-transform:uppercase;letter-spacing:.5px}
.metric .mv{font-size:18px;font-weight:700;margin-top:4px}
.detail{display:grid;grid-template-columns:repeat(3,1fr);gap:6px;font-size:12px;color:var(--text2);margin-top:8px}
.detail span{color:var(--text)}
.sep{margin-top:14px;padding-top:14px;border-top:1px solid var(--border)}
.section-title{font-size:14px;font-weight:600;margin-bottom:10px}
.time{text-align:center;color:var(--text2);font-size:12px;margin-top:12px}
.set-grid{display:grid;grid-template-columns:1fr 1fr;gap:12px}
.set-item{background:var(--card2);padding:14px;border-radius:10px}
.set-item label{color:var(--text2);font-size:13px;display:block;margin-bottom:6px}
.set-item input,.set-item select{width:100%;padding:8px 12px;border-radius:8px;border:1px solid var(--border);background:var(--bg);color:var(--text);font-size:14px;font-family:inherit}
.set-item input:focus{outline:2px solid var(--green);border-color:transparent}
.set-item .hint{font-size:11px;color:var(--text2);margin-top:4px}
.set-item .hint a{color:var(--green)}
.chart-box{background:var(--card2);border-radius:10px;padding:14px;overflow-x:auto}
.chart{display:flex;align-items:flex-end;height:80px;gap:3px;min-width:200px}
.cbar{flex:1;min-width:10px;border-radius:3px 3px 0 0;transition:height .5s;min-height:3px;cursor:pointer;position:relative}
.cbar:hover{opacity:.8}
.chart-labels{display:flex;gap:3px;margin-top:4px;font-size:8px;color:var(--text2)}
.chart-labels span{flex:1;text-align:center;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.stats-row{display:flex;gap:16px;flex-wrap:wrap;font-size:13px;color:var(--text2);margin-top:10px}
.stats-row b{color:var(--text);font-weight:600}
.alert-ov{position:fixed;inset:0;background:rgba(0,0,0,.6);display:none;justify-content:center;align-items:center;z-index:1000}
.alert-ov.show{display:flex}
.alert-box{background:var(--card);border-radius:16px;padding:36px;max-width:400px;width:90%;text-align:center;border:2px solid var(--red)}
.alert-box .icon{font-size:48px;margin-bottom:12px}
.alert-box h2{color:var(--red);margin-bottom:8px}
.alert-box p{color:var(--text2);margin-bottom:20px;line-height:1.8}
.toast{position:fixed;bottom:20px;right:20px;background:var(--card);color:var(--text);padding:12px 22px;border-radius:10px;display:none;font-weight:600;border-left:4px solid var(--green);box-shadow:0 4px 20px var(--shadow);z-index:999;max-width:90%}
.toast.show{display:block;animation:slideIn .3s}
@keyframes slideIn{from{transform:translateY(100%);opacity:0}to{transform:translateY(0);opacity:1}}
.log-box{background:var(--card2);border-radius:10px;padding:10px;max-height:400px;overflow-y:auto;font-family:'Cascadia Code',Consolas,monospace;font-size:12px;line-height:1.8}
.log-box div{white-space:pre-wrap;word-break:break-all;padding:2px 6px;border-bottom:1px solid rgba(128,128,128,.1)}
.spin{display:inline-block;width:14px;height:14px;border:2px solid var(--border);border-top-color:var(--green);border-radius:50%;animation:spin .6s linear infinite}
@keyframes spin{to{transform:rotate(360deg)}}
@media(max-width:768px){.card{padding:16px}.grid3{grid-template-columns:1fr 1fr}.set-grid{grid-template-columns:1fr}.detail{grid-template-columns:1fr 1fr}.hdr{flex-direction:column;align-items:flex-start}.tabs{width:100%}.tab{flex:1;text-align:center;padding:8px 10px;font-size:12px}.metric .mv{font-size:15px}.hdr h1{font-size:17px}}
@media(max-width:480px){.grid3{grid-template-columns:1fr}.detail{grid-template-columns:1fr}.btn{width:100%}}
</style>
</head>
<body class="<?php echo $theme === 'light' ? 'light' : ''; ?>">
<div class="wrap">

<!-- Toast -->
<div id="toast" class="toast"></div>

<!-- Alert Overlay -->
<div id="alertOv" class="alert-ov">
  <div class="alert-box">
    <div class="icon">⚡</div>
    <h2>断电告警</h2>
    <p>UPS 已切换到电池模式<br>电量: <strong id="aCharge">--</strong><br>预计剩余: <strong id="aRuntime">--</strong> 分钟</p>
    <button class="btn" onclick="document.getElementById('alertOv').classList.remove('show')">我知道了</button>
  </div>
</div>

<!-- Main Card -->
<div class="card">
  <div class="hdr">
    <div class="hdr-l">
      <svg viewBox="0 0 100 100">
        <circle cx="50" cy="50" r="46" fill="none" stroke="#10b981" stroke-width="3"/>
        <rect x="22" y="32" width="42" height="28" rx="4" fill="none" stroke="#10b981" stroke-width="3"/>
        <rect x="58" y="38" width="6" height="16" rx="2" fill="#10b981"/>
        <path d="M33 52 L42 42 H37 L41 32" stroke="#10b981" stroke-width="3" fill="none" stroke-linecap="round" stroke-linejoin="round"/>
        <text x="50" y="80" text-anchor="middle" font-size="12" font-weight="700" fill="#10b981">UPS</text>
      </svg>
      <div>
        <h1>UPS 监控系统 <span style="font-size:12px;color:var(--text2);font-weight:400">v0.5.0</span></h1>
        <div class="sub" id="upsModel">连接中...</div>
      </div>
    </div>
    <div class="hdr-r">
      <span id="connBadge" class="badge wait"><span class="spin"></span> 连接中</span>
      <button class="btn-sm" onclick="toggleTheme()"><?php echo $theme === 'dark' ? '☀️ 亮色' : '🌙 暗色'; ?></button>
      <button class="btn-sm" onclick="loadData(true)">🔄 刷新</button>
    </div>
  </div>

  <!-- Tabs -->
  <div class="tabs">
    <button class="tab act" data-tab="monitor">📊 监控</button>
    <button class="tab" data-tab="history">📈 历史</button>
    <button class="tab" data-tab="settings">⚙️ 设置</button>
    <button class="tab" data-tab="logs">📋 日志</button>
  </div>

  <!-- ─── 监控 ─── -->
  <div id="tab-monitor" class="tc act">
    <div class="row">
      <span class="label">⚡ UPS 状态</span>
      <span class="val" id="dStatus"><span class="spin"></span> 检查中...</span>
    </div>
    <div style="padding:8px 0;border-bottom:1px solid var(--border)">
      <div style="display:flex;justify-content:space-between">
        <span class="label">🔋 电池电量</span>
        <span class="val" id="dCharge">--%</span>
      </div>
      <div class="bar-bg"><div class="bar-fill" id="dChargeBar" style="width:0%;background:var(--text2)"></div></div>
    </div>
    <div class="grid3">
      <div class="metric"><div class="ml">⏱ 剩余时间</div><div class="mv" id="dRuntime">-- min</div></div>
      <div class="metric"><div class="ml">📊 负载</div><div class="mv" id="dLoad">--%</div></div>
      <div class="metric"><div class="ml">⚡ 额定功率</div><div class="mv" id="dPower">-- W</div></div>
    </div>
    <div class="grid3" style="margin-top:10px">
      <div class="metric"><div class="ml">🔌 输入电压</div><div class="mv" id="dInputV">-- V</div></div>
      <div class="metric"><div class="ml">🔌 输出电压</div><div class="mv" id="dOutputV">-- V</div></div>
      <div class="metric"><div class="ml">🔋 电池电压</div><div class="mv" id="dBattV">-- V</div></div>
    </div>
    <div class="sep">
      <div class="detail">
        <div>型号: <span id="dModel">--</span></div>
        <div>厂商: <span id="dMfr">--</span></div>
        <div>频率: <span id="dFreq">-- Hz</span></div>
        <div>电池温度: <span id="dBattTemp">--</span></div>
        <div>蜂鸣器: <span id="dBeeper">--</span></div>
        <div>固件: <span id="dFirmware">--</span></div>
      </div>
    </div>
    <div class="sep">
      <div class="section-title">🖥️ PVE 系统状态</div>
      <div class="grid3">
        <div class="metric"><div class="ml">💻 CPU</div><div class="mv" id="dCpu">--%</div></div>
        <div class="metric"><div class="ml">📊 负载</div><div class="mv" id="dLoadAvg">--</div></div>
        <div class="metric"><div class="ml">💾 内存</div><div class="mv" id="dMem">--%</div></div>
      </div>
      <div class="grid2" style="margin-top:8px;font-size:13px;color:var(--text2)">
        <div>磁盘: <span class="val" id="dDisk">--</span></div>
        <div>运行: <span class="val" id="dUptime">--</span></div>
      </div>
    </div>
    <div class="time" id="dTime">--</div>
  </div>

  <!-- ─── 历史 ─── -->
  <div id="tab-history" class="tc">
    <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:12px;flex-wrap:wrap;gap:8px">
      <span style="color:var(--text2);font-size:14px">📈 最近 30 次电量记录</span>
      <button class="btn-sm" onclick="clearHistory()">🗑️ 清空历史</button>
    </div>
    <div class="chart-box">
      <div class="chart" id="chart"></div>
      <div class="chart-labels" id="chartLabels"></div>
    </div>
    <div class="stats-row" id="histStats"></div>
  </div>

  <!-- ─── 设置 ─── -->
  <div id="tab-settings" class="tc">
    <form method="POST" action="">
      <input type="hidden" name="action" value="save">
      <div class="set-grid">
        <div class="set-item">
          <label>🔄 刷新间隔（秒）</label>
          <input type="number" name="refresh" value="<?php echo $refresh; ?>" min="3" max="60">
          <div class="hint">页面自动刷新频率</div>
        </div>
        <div class="set-item">
          <label>🔴 低电量告警（%）</label>
          <input type="number" name="low_battery" value="<?php echo $low_battery; ?>" min="5" max="50">
          <div class="hint">低于此值显示红色告警</div>
        </div>
        <div class="set-item">
          <label>⏱ 关机等待（秒）</label>
          <input type="number" name="shutdown_delay" value="<?php echo $config['shutdown_delay']; ?>" min="10" max="600">
          <div class="hint">断电后 PVE 延迟关机时间</div>
        </div>
        <div class="set-item">
          <label>🌐 UPS 主机 IP</label>
          <input type="text" name="ups_host" value="<?php echo htmlspecialchars($config['ups_host']); ?>">
          <div class="hint">NUT Server 地址</div>
        </div>
        <div class="set-item">
          <label>📛 UPS 名称</label>
          <input type="text" name="ups_name" value="<?php echo htmlspecialchars($config['ups_name']); ?>">
          <div class="hint">ups.conf 中定义的设备名</div>
        </div>
        <div class="set-item">
          <label>🎨 主题</label>
          <select name="theme">
            <option value="dark" <?php echo $theme === 'dark' ? 'selected' : ''; ?>>🌙 暗色</option>
            <option value="light" <?php echo $theme === 'light' ? 'selected' : ''; ?>>☀️ 亮色</option>
          </select>
        </div>
        <div class="set-item" style="grid-column:1/-1">
          <label>📱 微信通知 Token（PushPlus）</label>
          <input type="text" name="pushplus_token" value="<?php echo $has_token ? htmlspecialchars(get_token()) : ''; ?>" placeholder="前往 pushplus.plus 注册获取" style="font-size:13px">
          <div class="hint">
            <a href="https://www.pushplus.plus" target="_blank">👉 注册 PushPlus</a>
            <?php echo $has_token ? '<span style="color:var(--green);margin-left:8px">✅ 已配置</span>' : '<span style="color:var(--orange);margin-left:8px">⚠️ 未配置</span>'; ?>
          </div>
        </div>
      </div>
      <div style="margin-top:14px;display:flex;gap:10px;flex-wrap:wrap">
        <button type="submit" class="btn">💾 保存设置</button>
        <button type="button" class="btn btn-w" onclick="testWechat()">📱 测试微信通知</button>
        <button type="button" class="btn" onclick="selfTest()">🔋 UPS 自检</button>
      </div>
    </form>
  </div>

  <!-- ─── 日志 ─── -->
  <div id="tab-logs" class="tc">
    <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:12px;flex-wrap:wrap;gap:8px">
      <span style="color:var(--text2);font-size:14px">📋 系统事件日志</span>
      <div style="display:flex;gap:8px">
        <button class="btn-sm" onclick="loadLogs()">🔄 刷新</button>
        <button class="btn-sm btn-d" onclick="clearLogs()">🗑️ 清空</button>
      </div>
    </div>
    <div class="log-box" id="logBox">
      <div style="color:var(--text2)">加载中...</div>
    </div>
    <div style="margin-top:10px;font-size:12px;color:var(--text2);display:flex;gap:14px;flex-wrap:wrap">
      <span>🟢 <span style="color:#10b981">恢复</span></span>
      <span>🟠 <span style="color:#f59e0b">告警</span></span>
      <span>🔴 <span style="color:#ef4444">断电/错误</span></span>
      <span>🔵 <span style="color:#3b82f6">操作</span></span>
      <span>🟢 <span style="color:#07c160">微信</span></span>
    </div>
  </div>
</div>

</div>

<script>
const REFRESH = <?php echo $refresh; ?>;
const LOW_BATT = <?php echo $low_battery; ?>;
let timer = null;
let lastAlertTime = 0;

// ─── Toast ───
function toast(msg, isError) {
    const t = document.getElementById('toast');
    t.textContent = msg;
    t.style.borderLeftColor = isError ? 'var(--red)' : 'var(--green)';
    t.classList.add('show');
    clearTimeout(t._timer);
    t._timer = setTimeout(() => t.classList.remove('show'), 3000);
}

// ─── Tab switching ───
document.querySelectorAll('.tab').forEach(tab => {
    tab.addEventListener('click', function() {
        document.querySelectorAll('.tab').forEach(t => t.classList.remove('act'));
        document.querySelectorAll('.tc').forEach(t => t.classList.remove('act'));
        this.classList.add('act');
        document.getElementById('tab-' + this.dataset.tab).classList.add('act');
    });
});

// ─── Theme toggle ───
function toggleTheme() {
    const url = new URL(window.location.href);
    url.searchParams.set('theme', document.body.classList.contains('light') ? 'dark' : 'light');
    window.location.href = url.toString();
}

// ─── Desktop notification ───
function notifyDesktop(title, body) {
    if (!('Notification' in window)) return;
    if (Notification.permission === 'granted') {
        new Notification(title, { body, icon: 'data:image/svg+xml,' + encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" width="48" height="48"><circle cx="24" cy="24" r="22" fill="#10b981"/><text x="24" y="30" text-anchor="middle" fill="white" font-size="14">UPS</text></svg>') });
    } else if (Notification.permission !== 'denied') {
        Notification.requestPermission().then(p => { if (p === 'granted') new Notification(title, { body }); });
    }
}

// ─── Load UPS + PVE data ───
async function loadData(manual) {
    try {
        const r = await fetch('?api=data', { cache: 'no-store' });
        const d = await r.json();
        if (!d.success) return;

        const badge = document.getElementById('connBadge');
        const statusEl = document.getElementById('dStatus');

        if (!d.connected) {
            badge.className = 'badge no';
            badge.innerHTML = '✕ 未连接';
            statusEl.innerHTML = '<span class="offline">⚠️ UPS 未连接</span>';
            document.getElementById('upsModel').textContent = '无法连接到 NUT Server';
            document.getElementById('dTime').textContent = d.time + ' · 未连接';
            return;
        }

        badge.className = 'badge ok';
        badge.innerHTML = '● 已连接';

        const u = d.ups;
        const isOnline = d.online;
        const charge = parseInt(u['battery.charge'] || 0);
        const runtime = parseInt(u['battery.runtime'] || 0);
        const runtimeMin = runtime > 0 ? Math.round(runtime / 60 * 10) / 10 : 0;
        const load = parseInt(u['ups.load'] || 0);
        const lowBatt = charge <= LOW_BATT;

        // Status
        if (isOnline) {
            statusEl.innerHTML = '<span class="online">✅ 市电正常</span>';
        } else {
            statusEl.innerHTML = '<span class="offline">⚠️ 电池模式</span>' + (lowBatt ? ' <span class="offline">🔴 电量过低!</span>' : '');
        }

        // Battery
        const chargeColor = charge > 60 ? '#10b981' : (charge > 30 ? '#f59e0b' : '#ef4444');
        document.getElementById('dCharge').textContent = charge + '%';
        document.getElementById('dCharge').style.color = chargeColor;
        const bar = document.getElementById('dChargeBar');
        bar.style.width = charge + '%';
        bar.style.background = chargeColor;

        // Metrics
        document.getElementById('dRuntime').textContent = runtimeMin + ' min';
        document.getElementById('dLoad').textContent = load + '%';
        document.getElementById('dPower').textContent = (u['ups.realpower.nominal'] || '--') + ' W';
        document.getElementById('dInputV').textContent = (u['input.voltage'] || '--') + ' V';
        document.getElementById('dOutputV').textContent = (u['output.voltage'] || '--') + ' V';
        document.getElementById('dBattV').textContent = (u['battery.voltage'] || '--') + ' V';

        // Details
        document.getElementById('upsModel').textContent = (u['ups.mfr'] || '') + ' ' + (u['ups.model'] || 'UPS');
        document.getElementById('dModel').textContent = u['ups.model'] || '--';
        document.getElementById('dMfr').textContent = u['ups.mfr'] || '--';
        document.getElementById('dFreq').textContent = (u['input.frequency'] || '--') + ' Hz';
        document.getElementById('dBattTemp').textContent = u['battery.temperature'] ? u['battery.temperature'] + ' C' : '--';
        document.getElementById('dBeeper').textContent = u['ups.beeper.status'] === 'enabled' ? '🔊 开启' : '🔇 关闭';
        document.getElementById('dFirmware').textContent = u['ups.firmware'] || '--';

        // PVE
        const p = d.pve;
        document.getElementById('dCpu').textContent = p.cpu + '%';
        document.getElementById('dLoadAvg').textContent = p.load;
        document.getElementById('dMem').textContent = p.mem_percent + '%';
        document.getElementById('dDisk').textContent = p.disk;
        document.getElementById('dUptime').textContent = p.uptime;
        document.getElementById('dTime').textContent = '🔄 ' + d.time;

        // History chart
        renderChart(d.history);

        // Alert
        if (d.alert) {
            const now = Date.now();
            if (now - lastAlertTime > 60000) {
                lastAlertTime = now;
                document.getElementById('aCharge').textContent = d.alert.charge + '%';
                document.getElementById('aRuntime').textContent = d.alert.runtime;
                document.getElementById('alertOv').classList.add('show');
                notifyDesktop('UPS 断电告警', '电量 ' + d.alert.charge + '%, 剩余 ' + d.alert.runtime + ' 分钟');
            }
        }

        if (manual) toast('数据已刷新');
    } catch(e) {
        document.getElementById('connBadge').className = 'badge no';
        document.getElementById('connBadge').innerHTML = '✕ 连接失败';
        if (manual) toast('刷新失败: ' + e.message, true);
    }
}

// ─── Render history chart ───
function renderChart(history) {
    const chart = document.getElementById('chart');
    const labels = document.getElementById('chartLabels');
    if (!history || history.length === 0) {
        chart.innerHTML = '<div style="color:var(--text2);text-align:center;width:100%;padding:20px">暂无历史数据</div>';
        labels.innerHTML = '';
        document.getElementById('histStats').innerHTML = '';
        return;
    }
    let bars = '', labs = '';
    history.forEach(h => {
        const c = h.charge;
        const color = c > 60 ? '#10b981' : (c > 30 ? '#f59e0b' : '#ef4444');
        const height = Math.max(3, (c / 100) * 70);
        const status = h.status === 'OL' ? '市电' : '电池';
        bars += '<div class="cbar" style="height:' + height + 'px;background:' + color + '" title="' + h.time + ': ' + c + '% ' + status + '"></div>';
        labs += '<span>' + h.time + '</span>';
    });
    chart.innerHTML = bars;
    labels.innerHTML = labs;

    const olCount = history.filter(h => h.status === 'OL').length;
    const obCount = history.filter(h => h.status === 'OB').length;
    const avg = history.length > 0 ? Math.round(history.reduce((s, h) => s + h.charge, 0) / history.length * 10) / 10 : 0;
    document.getElementById('histStats').innerHTML =
        '<span>🟢 市电: <b>' + olCount + '</b> 次</span>' +
        '<span>🟠 电池: <b>' + obCount + '</b> 次</span>' +
        '<span>📊 平均电量: <b>' + avg + '%</b></span>';
}

// ─── Load logs ───
async function loadLogs() {
    try {
        const r = await fetch('?api=logs', { cache: 'no-store' });
        const d = await r.json();
        const box = document.getElementById('logBox');
        if (!d.logs || d.logs.length === 0) {
            box.innerHTML = '<div style="color:var(--text2)">暂无日志记录</div>';
            return;
        }
        box.innerHTML = d.logs.map(line => {
            let color = 'var(--text2)';
            if (line.includes('[ERROR]') || line.includes('[断电]')) color = '#ef4444';
            else if (line.includes('[告警]')) color = '#f59e0b';
            else if (line.includes('[恢复]')) color = '#10b981';
            else if (line.includes('[操作]')) color = '#3b82f6';
            else if (line.includes('[微信]')) color = '#07c160';
            return '<div style="color:' + color + '">' + line.replace(/</g, '&lt;') + '</div>';
        }).join('');
    } catch(e) {
        document.getElementById('logBox').innerHTML = '<div style="color:var(--red)">加载失败: ' + e.message + '</div>';
    }
}

// ─── Clear history ───
async function clearHistory() {
    if (!confirm('确认清空历史记录?')) return;
    try {
        await fetch('?api=clear_history');
        toast('历史已清空');
        loadData();
    } catch(e) { toast('操作失败', true); }
}

// ─── Clear logs ───
async function clearLogs() {
    if (!confirm('确认清空所有日志?')) return;
    try {
        await fetch('?api=clear_logs');
        toast('日志已清空');
        loadLogs();
    } catch(e) { toast('操作失败', true); }
}

// ─── Test WeChat ───
async function testWechat() {
    toast('正在发送测试通知...');
    try {
        const r = await fetch('?api=test_wechat');
        const d = await r.json();
        toast(d.message, !d.success);
    } catch(e) { toast('请求失败: ' + e.message, true); }
}

// ─── UPS Self-test ───
async function selfTest() {
    if (!confirm('确认触发 UPS 电池自检? 这将短暂切换到电池供电。')) return;
    toast('正在发送自检命令...');
    try {
        const r = await fetch('?api=selftest', { method: 'POST', headers: {'Content-Type':'application/x-www-form-urlencoded'}, body: 'user=admin&pass=admin123' });
        const d = await r.json();
        toast(d.message, !d.success);
    } catch(e) { toast('请求失败: ' + e.message, true); }
}

// ─── Auto refresh ───
function startTimer() {
    if (timer) clearInterval(timer);
    timer = setInterval(() => loadData(false), REFRESH * 1000);
}

// ─── Init ───
<?php if ($just_saved): ?>
toast('✅ 设置已保存');
<?php endif; ?>

loadData();
loadLogs();
startTimer();

// Request notification permission
if ('Notification' in window && Notification.permission === 'default') {
    Notification.requestPermission();
}

// Refresh logs when switching to logs tab
document.querySelector('[data-tab="logs"]').addEventListener('click', loadLogs);
</script>
</body>
</html>
