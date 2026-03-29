# OpenClaw 使用指南

## 简介

OpenClaw 是一个开源的 AI 代理框架，支持多种通讯渠道（如 Telegram、Discord、WhatsApp 等），可以让你通过这些渠道与 AI 代理进行交互。

- **版本**：2026.3.7
- **官网**：https://docs.openclaw.ai/

---

## 快速开始

### 1. 初始化配置

首次使用需要初始化配置：

```bash
openclaw setup
```

这会创建配置文件 `~/.openclaw/openclaw.json` 和代理工作区。

### 2. 交互式配置向导（推荐）

运行以下命令进行交互式设置（包括凭证、渠道、网关和代理默认配置）：

```bash
openclaw configure
```

可以选择配置以下部分：
- `workspace` - 工作区配置
- `model` - 模型配置
- `web` - Web 配置
- `gateway` - 网关配置
- `daemon` - 守护进程配置
- `channels` - 通讯渠道配置
- `skills` - 技能配置
- `health` - 健康检查配置

### 3. 一键初始化向导

使用 onboard 命令可以一键完成网关、工作区和技能的设置：

```bash
openclaw onboard
```

常用选项：
- `--install-daemon` - 安装网关服务（开机自启）
- `--flow <flow>` - 向导流程：`quickstart`（快速）|`advanced`（高级）|`manual`（手动）
- `--non-interactive` - 非交互模式运行
- `--anthropic-api-key <key>` - Anthropic API key
- `--openai-api-key <key>` - OpenAI API key
- `--gateway-auth <mode>` - 网关认证方式：`token` 或 `password`
- `--skip-channels` - 跳过渠道设置
- `--skip-skills` - 跳过技能设置

示例：

```bash
# 快速初始化并安装网关服务
openclaw onboard --install-daemon --flow quickstart

# 非交互模式（需要先配置 API key 环境变量）
openclaw onboard --non-interactive --accept-risk --install-daemon
```

### 4. 启动网关

启动 WebSocket 网关（前置服务）：

```bash
# 前台运行
openclaw gateway run

# 或者作为服务运行
openclaw gateway start

# 查看状态
openclaw gateway status
```

---

## 常用命令

### 网关管理

| 命令 | 说明 |
|------|------|
| `openclaw gateway run` | 前台运行网关 |
| `openclaw gateway start` | 启动网关服务 |
| `openclaw gateway stop` | 停止网关服务 |
| `openclaw gateway status` | 查看网关状态 |
| `openclaw gateway restart` | 重启网关服务 |
| `openclaw gateway health` | 检查网关健康状态 |

### 渠道管理

| 命令 | 说明 |
|------|------|
| `openclaw channels` | 查看渠道列表 |
| `openclaw channels login` | 登录渠道（如 WhatsApp） |

### 消息发送

```bash
# 发送消息示例
openclaw message send --target +15555550123 --message "Hello"
openclaw message send --channel telegram --target @mychat --message "Hi"
```

### 代理交互

```bash
# 与代理对话
openclaw agent --to +15555550123 --message "运行摘要" --deliver
```

### 模型管理

```bash
# 查看可用模型
openclaw models --help
```

---

## 配置文件说明

OpenClaw 的配置文件位于 `~/.openclaw/openclaw.json`。

### 主要配置项

```json
{
  "gateway": {
    "mode": "local",
    "bind": "loopback",
    "port": 18789
  },
  "agents": {
    "defaults": {
      "workspace": "~/.openclaw/workspace"
    }
  },
  "channels": {
    // 渠道配置
  }
}
```

---

## 常见选项

| 选项 | 说明 |
|------|------|
| `--dev` | 开发模式（隔离状态） |
| `--profile <name>` | 使用命名配置 |
| `--log-level <level>` | 日志级别 (silent\|fatal\|error\|warn\|info\|debug\|trace) |
| `--no-color` | 禁用 ANSI 颜色 |
| `-h, --help` | 显示帮助 |
| `-V, --version` | 显示版本 |

---

## 故障排除

### 检查健康状态

```bash
openclaw doctor
```

### 查看日志

```bash
openclaw logs
```

### 重置配置

```bash
openclaw reset
```

---

## 更多资源

- 官方文档：https://docs.openclaw.ai/cli
- 命令帮助：`openclaw <command> --help`
