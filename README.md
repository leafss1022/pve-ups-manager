# PVE UPS 管理器

在 Proxmox VE (PVE) 中配置 UPS 断电自动关机方案。支持 **NUT (Network UPS Tools)** 和 **apcupsd** 两种主流工具。

## 功能

- Web 仪表板实时显示 UPS 状态
- 在线编辑 NUT 配置文件 (ups.conf, upsd.conf, upsd.users, upsmon.conf)
- 在线编辑 apcupsd 配置文件 (apcupsd.conf)
- 查看 PVE 虚拟机/容器列表
- 执行安全关机（关闭所有 VM/CT → 宿主机）
- Docker 部署支持
- REST API + WebSocket 实时监控

## 两种 Web 界面

### 1. Node.js 管理器（全功能）

完整的 UPS 管理系统，支持配置编辑、虚拟机管理、安全关机等。

```bash
# 一键部署
bash <(curl -sL https://raw.githubusercontent.com/leafss1022/pve-ups-manager/main/scripts/quick-install.sh)
```

访问 `http://<IP>:3456`

### 2. PHP 监控页（轻量级）

轻量级 UPS 监控面板，适合直接部署在 PVE 的 Apache 上。支持：

- UPS 实时状态监控（电量、电压、负载、运行时间等）
- PVE 系统状态（CPU、内存、磁盘、负载）
- 历史电量趋势图（最近 30 次记录）
- 事件日志系统（彩色分类）
- 微信通知（PushPlus）
- 深色/亮色主题切换
- 手机自适应
- AJAX 异步刷新（无需整页刷新）
- 桌面通知
- UPS 自检
- 断电告警弹窗

```bash
# 安装 PHP 监控页
git clone https://github.com/leafss1022/pve-ups-manager.git /opt/pve-ups-manager
bash /opt/pve-ups-manager/scripts/install-php-monitor.sh
```

访问 `http://<IP>/ups.php`

**PHP 版特点**：
- 单文件部署，无需 Node.js
- 配置文件存储在 `/var/lib/ups-monitor/`（Web 根目录外，安全）
- 输入参数过滤，防止命令注入
- 日志自动轮转（最大 1MB）
- AJAX 异步数据刷新


## 远程 NUT (NAS 场景)

当 UPS 连接在 NAS 或其他服务器上，PVE 通过远程 NUT 协议获取状态：

1. NAS 端安装 NUT (nut-server)，UPS 通过 USB/串口连接
2. PVE 端仅安装 nut-client (无需 nut-server)
3. 在 PVE UPS Manager 的"设置"页面配置 NUT 服务器地址 (如 192.168.10.7)
4. WebSocket 自动推送到前端，无需定时轮询

需确保 PVE 能访问 NAS 的 3493 端口 (NUT 默认端口)。

## 快速开始

### 方式一：Node.js 全功能管理器

```bash
git clone https://github.com/leafss1022/pve-ups-manager
cd pve-ups-manager
npm install
cd frontend && npm install && cd ..
npm start
```

访问 [http://localhost:3456](http://localhost:3456)

### 方式二：PHP 轻量监控页

```bash
git clone https://github.com/leafss1022/pve-ups-manager.git /opt/pve-ups-manager
bash /opt/pve-ups-manager/scripts/install-php-monitor.sh
```

访问 `http://<IP>/ups.php`

### 方式三：Docker 部署

```bash
cd docker
docker-compose up -d
```

### 方式四：安装 UPS 客户端

```bash
# 安装 NUT
chmod +x scripts/install-nut.sh
./scripts/install-nut.sh

# 或安装 apcupsd
chmod +x scripts/install-apcupsd.sh
./scripts/install-apcupsd.sh
```

## 断电自动关机流程

1. UPS 检测市电中断，通过 USB/串口通知 PVE 主机
2. upsmon (NUT) 或 apcupsd 检测电池电量低于阈值
3. 触发关机脚本，先安全关闭所有虚拟机 (qm shutdown) 和容器 (pct shutdown)
4. 确认所有 VM/CT 停止后，宿主机执行 shutdown
5. 市电恢复后 PVE 自动启动（需 BIOS 设置通电自启）

## 环境要求

- Proxmox VE 7.x / 8.x
- Node.js 18+（运行 Node.js 管理器）
- PHP 7.4+（运行 PHP 监控页）
- NUT 或 apcupsd（UPS 通信）
- Docker + Docker Compose（可选）

## API (Node.js 版)

| 端点 | 方法 | 说明 |
|---|---|---|
| /api/nut/config | GET | 读取 NUT 配置 |
| /api/nut/config | POST | 保存 NUT 配置 |
| /api/nut/status | GET | UPS 状态 |
| /api/nut/restart | POST | 重启 NUT 服务 |
| /api/apcupsd/config | GET | 读取 apcupsd 配置 |
| /api/apcupsd/config | POST | 保存 apcupsd 配置 |
| /api/apcupsd/status | GET | apcupsd UPS 状态 |
| /api/apcupsd/restart | POST | 重启 apcupsd |
| /api/pve/list | GET | 列出 VM/CT |
| /api/pve/shutdown | POST | 执行安全关机 |
| /api/system/info | GET | 系统信息 |
| /api/system/tools | GET | 检测已安装的 UPS 工具 |

## 许可证

MIT
