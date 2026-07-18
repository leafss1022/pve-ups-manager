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

## 快速开始

### 方式一：直接运行 (Node.js)

```bash
git clone https://github.com/leafss1022/pve-ups-manager
cd pve-ups-manager
npm install
cd frontend && npm install && cd ..
npm start
```

访问 http://localhost:3456

### 方式二：Docker 部署

```bash
cd docker
docker-compose up -d
```

### 方式三：在 PVE 上安装客户端

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
- Node.js 18+（运行 Web 服务）
- Docker + Docker Compose（可选）

## API

| 端点 | 方法 | 说明 |
|------|------|------|
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

## 截图

Web 管理界面包含：
- 仪表板卡片：UPS 状态、电池电量、输入电压、负载、运行时间
- NUT 配置编辑器（多文件切换标签）
- apcupsd 配置编辑器
- 虚拟机/容器管理列表
- 事件日志
- 系统信息面板
- 安全关机对话框

## 许可证

MIT
