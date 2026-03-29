# Claude Test 项目

## 2026-03-08 会话总结

### 会话主要目的
- 检查 node 和 openclaw 的安装状态
- 解决终端报错 "node: command not found" 的问题
- 在帮助文档目录添加 openclaw 使用指南

### 完成的主要任务
1. 发现 node 已通过 NVM 安装在 `~/.nvm/versions/node/v22.22.1/bin/`，但环境变量未正确配置
2. 发现用户默认 shell 是 bash，需要配置 `~/.bashrc` 而不是 `~/.zshrc`
3. 解决 git SSH 权限问题（`git@github.com: Permission denied`），配置 git 使用 HTTPS 替代 SSH
4. 重新安装 openclaw（之前的安装文件损坏）
5. 在帮助文档目录创建了 `OpenClaw使用指南.md`

### 关键决策和解决方案
- **问题根因**：用户的默认 shell 是 bash，但之前只配置了 `.zshrc`，新终端没有加载 node 路径
- **解决方案**：在 `~/.bashrc` 中添加 node 的 PATH 配置
- **Git 问题解决**：运行 `git config --global url."https://github.com/".insteadOf "git@github.com:"` 解决 SSH 权限问题

### 使用的技术栈
- NVM (- Node.js v22.Node Version Manager)
22.1
- npm 10.9.4
- OpenClaw 2026.3.7

### 修改的文件
- `~/.zshrc` - 添加了 node PATH 配置
- `~/.bashrc` - 添加了 node PATH 配置
- `帮助文档/OpenClaw使用指南.md` - 新建文件

## 2026-03-08 会话总结（2）

### 会话主要目的
- 解决 OpenClaw 网关控制台中显示的 "unauthorized: gateway password missing" 报错

### 完成的主要任务
1. 根据截图和官方文档，确认这是 Control UI 未配置网关认证 token/密码导致的未授权错误
2. 给出通过 CLI 获取/生成网关 token，并在 Control UI 的设置中填写保存的完整操作步骤

### 关键决策和解决方案
- **问题根因**：网关开启了认证（`gateway auth`），但 Control UI 浏览器端没有保存匹配的 token/密码，因此所有状态检查请求都被网关拒绝
- **解决方案**：
  - 在终端中通过 `openclaw doctor --generate-gateway-token` 或 `openclaw config get gateway.auth.token` 获取 token；
  - 打开 Control UI（网关仪表盘），在右上角齿轮图标进入设置，将 token 粘贴到网关认证/密码输入框中并保存；
  - 如在本机个人环境可选地通过清空 `gateway.auth.token` 并重启网关来关闭认证（仅限本地、受防火墙保护环境）。

### 使用的技术栈
- OpenClaw 网关与 Control UI
- OpenClaw CLI（`openclaw doctor`、`openclaw config` 等命令）

### 修改的文件
- `README.md` - 追加本次会话总结

---

## 2026-03-28 会话总结

### 会话主要目的
- 根据 `ClaudeCode使用指南.md` 帮助文档，用表格梳理 Claude Code 常用命令
- 将汇总表格更新到文档中

### 完成的主要任务
1. 读取并分析 `帮助文档/ClaudeCode使用指南.md` 的完整内容
2. 从文档中提取所有命令，按类别整理为统一的汇总表格
3. 将汇总表格添加到文档的"常用命令"章节中

### 关键决策和解决方案
- 将命令分为 8 大类别：启动、对话、权限、工具、输出/调试、认证/系统、MCP、符号/工作流/管道/扩展
- 表格设计为 4 列：类别、命令、解释、使用场景，便于快速查找
- 添加了模型能力排序提示（Opus > Sonnet > Haiku）

### 使用的技术栈
- Markdown 表格语法

### 修改的文件
- `帮助文档/ClaudeCode使用指南.md` - 添加了命令汇总表
