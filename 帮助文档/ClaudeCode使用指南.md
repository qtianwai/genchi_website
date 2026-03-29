# Claude Code 使用指南

## 概述

Claude Code 是 Anthropic 公司推出的命令行 AI 助手，可以在终端中直接与 Claude AI 对话，支持代码编辑、文件操作、搜索等多种功能。

---

## 安装与配置

### 环境要求

- Node.js 20.x 或更高版本
- macOS / Linux / Windows (WSL)

### 安装步骤

```bash
# 1. 安装 Node.js（如果未安装）
# 下载地址：https://nodejs.org

# 2. 安装 Claude Code
npm install -g @anthropic-ai/claude-code

# 3. 配置 PATH 环境变量
echo 'export PATH="$HOME/.npm-global/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

### 登录认证

```bash
# 登录 Anthropic 账户
claude auth login

# 查看登录状态
claude auth status

# 退出登录
claude auth logout
```

---

## 常用命令

以下是 Claude Code 最常用的命令汇总：

### 启动命令

```bash
claude                    # 启动交互式对话（默认）
claude -p "你的问题"       # 直接提问并退出（非交互模式）
claude --model opus       # 指定使用 Opus 模型
claude --model sonnet     # 指定使用 Sonnet 模型
```

### 对话控制

```bash
claude -c                 # 继续之前的对话（当前目录）
claude -r [会话ID]         # 指定会话ID恢复对话
```

### 权限与工具

```bash
claude --dangerously-skip-permissions  # 跳过所有确认（谨慎使用）
claude --permission-mode acceptEdits     # 自动接受所有编辑
claude --permission-mode dontAsk        # 不询问权限
claude --permission-mode plan           # 规划模式（先规划再执行）
claude --tools ""                       # 禁用所有工具（纯对话）
claude --add-dir /路径                  # 添加可访问目录
```

### MCP 服务器

```bash
claude mcp list             # 查看已配置的 MCP 服务器
claude mcp add-from-claude-desktop  # 从 Claude Desktop 导入 MCP 配置
claude mcp serve            # 启动 MCP 服务器
```

### 系统管理

```bash
claude auth login           # 登录账户
claude auth status          # 查看登录状态
claude update               # 检查更新
claude doctor               # 诊断检查
```

### 快捷符号（在对话中使用）

```bash
@文件名        # 引用项目中的文件
@Docs         # 引用自定义文档
@Git          # 引用 Git 信息
@Terminal     # 引用终端输出
```

### 命令汇总表

| 类别 | 命令 | 解释 | 使用场景 |
|------|------|------|----------|
| **启动** | `claude` | 启动交互式对话 | 默认启动，进入 AI 助手交互模式 |
| **启动** | `claude -p "问题"` | 直接提问并退出 | 快速单次问答，非交互模式 |
| **启动** | `claude --model opus` | 指定使用 Opus 模型 | 复杂任务，需要最强推理能力 |
| **启动** | `claude --model sonnet` | 指定使用 Sonnet 模型 | 日常任务，平衡性能与成本 |
| **对话** | `claude -c` | 继续之前的对话 | 恢复当前目录的最近会话 |
| **对话** | `claude -r [会话ID]` | 指定会话ID恢复对话 | 从特定历史会话继续工作 |
| **权限** | `claude --dangerously-skip-permissions` | 跳过所有确认 | ⚠️ 沙箱/自动化环境，谨慎使用 |
| **权限** | `claude --permission-mode acceptEdits` | 自动接受所有编辑 | 完全信任 AI 的编辑操作 |
| **权限** | `claude --permission-mode dontAsk` | 不询问权限 | 完全自主模式 |
| **权限** | `claude --permission-mode plan` | 规划模式 | 先规划再执行，适合大型任务 |
| **工具** | `claude --tools ""` | 禁用所有工具 | 纯对话模式，不执行任何操作 |
| **工具** | `claude --allowed-tools "Bash,Read"` | 指定允许的工具 | 限制 AI 可使用的工具范围 |
| **工具** | `claude --add-dir /路径` | 添加可访问目录 | 扩展工作目录范围 |
| **输出** | `claude -p --output-format json` | JSON 格式输出 | 程序化处理响应结果 |
| **输出** | `claude -p --output-format stream-json` | 流式 JSON 输出 | 实时处理 AI 响应 |
| **调试** | `claude --debug` | 启用调试模式 | 排查问题、检查 API 调用 |
| **调试** | `claude --debug api` | API 调试 | 查看 API 请求/响应详情 |
| **调试** | `claude --debug hooks` | Hooks 调试 | 检查 Git hooks 执行情况 |
| **认证** | `claude auth login` | 登录账户 | 首次使用或重新认证 |
| **认证** | `claude auth status` | 查看登录状态 | 确认账户认证状态 |
| **认证** | `claude auth logout` | 退出登录 | 切换账户或清理认证 |
| **系统** | `claude update / upgrade` | 检查并更新 | 更新 Claude Code 版本 |
| **系统** | `claude doctor` | 诊断检查 | 检查环境配置是否正常 |
| **MCP** | `claude mcp list` | 查看已配置的 MCP 服务器 | 了解当前可用的 MCP 扩展 |
| **MCP** | `claude mcp add-from-claude-desktop` | 从 Claude Desktop 导入 | 复用已有的 MCP 配置 |
| **MCP** | `claude mcp serve` | 启动 MCP 服务器 | 启用 MCP 功能 |
| **MCP** | `claude mcp add [名称] -- [命令]` | 添加 MCP 服务器 | 配置新的 MCP 扩展 |
| **MCP** | `claude mcp remove [名称]` | 移除 MCP 服务器 | 删除不需要的扩展 |
| **符号** | `@文件名` | 引用项目中的文件 | 让 AI 分析或参考特定文件 |
| **符号** | `@Docs` | 引用自定义文档 | 使用项目自定义知识库 |
| **符号** | `@Git` | 引用 Git 信息 | 获取 Git 状态、提交历史等 |
| **符号** | `@Terminal` | 引用终端输出 | 分析最近的终端命令输出 |
| **工作流** | `claude -w feature-branch` | 创建 git worktree 并工作 | 在独立分支上开发 |
| **工作流** | `claude -w feature-branch --tmux` | 配合 tmux 使用 | 在 tmux session 中工作 |
| **管道** | `cat file.txt \| claude -p` | 从文件读取输入 | 处理文件内容 |
| **管道** | `claude -p "生成代码" > output.js` | 输出到文件 | 将 AI 输出保存到文件 |
| **扩展** | `claude agents` | 列出配置的 agents | 查看可用的自定义代理 |
| **扩展** | `claude plugin` | 插件管理 | 安装/管理 Claude Code 插件 |

> **模型能力排序**：Opus > Sonnet > Haiku  
> **建议**：日常任务用 Sonnet 即可，复杂推理选 Opus。

---

## 常用选项

### 权限控制

```bash
# 跳过所有权限确认（沙箱环境推荐）
claude --dangerously-skip-permissions

# 交互式权限模式
claude --permission-mode acceptEdits  # 自动接受所有编辑
claude --permission-mode dontAsk      # 不询问
claude --permission-mode plan        # 规划模式
```

### 工具控制

```bash
# 指定允许的工具
claude --allowed-tools "Bash,Read,Edit"

# 禁用所有工具（纯对话）
claude --tools ""

# 允许所有工具（默认）
claude --tools default

# 添加可访问的目录
claude --add-dir /path/to/directory
```

### 输出格式

```bash
claude -p --output-format json "你好"        # JSON 格式
claude -p --output-format stream-json "你好" # 流式 JSON
```

### 调试选项

```bash
# 启用调试模式
claude --debug

# 调试特定类别
claude --debug api              # API 调试
claude --debug hooks            # Hooks 调试
claude --debug !1p,!file        # 排除某些调试
```

---

## 子命令

### MCP 服务器管理

```bash
# 列出已配置的 MCP 服务器
claude mcp list

# 添加 MCP 服务器
claude mcp add server-name -- npx command

# 导入 Claude Desktop 的 MCP 配置
claude mcp add-from-claude-desktop

# 移除 MCP 服务器
claude mcp remove server-name

# 启动 MCP 服务器
claude mcp serve
```

### 插件管理

```bash
# 插件相关命令
claude plugin
```

### Agent 管理

```bash
# 列出配置的 agents
claude agents
```

### 更新

```bash
# 检查并更新
claude update
claude upgrade
```

### 诊断

```bash
# 检查健康状态
claude doctor
```

---

## 工作流

### Git Worktree 集成

```bash
# 创建新的 git worktree 并在其中工作
claude -w feature-branch

# 配合 tmux 使用
claude -w feature-branch --tmux
```

### 管道集成

```bash
# 从文件读取输入
cat file.txt | claude -p

# 输出到文件
claude -p "生成代码" > output.js
```

---

## 使用技巧

1. **快速提问**：使用 `-p` 进行快速单次问答
2. **会话管理**：使用 `-c` 继续之前的对话
3. **权限预设**：在沙箱环境使用 `--dangerously-skip-permissions`
4. **模型选择**：根据任务选择合适模型（opus > sonnet > haiku）
5. **MCP 集成**：配置 MCP 服务器扩展功能

---

## 注意事项

1. **认证要求**：首次使用需运行 `claude auth login` 登录
2. **API 费用**：使用 API 账户会产生费用，请关注使用量
3. **权限安全**：谨慎使用 `--dangerously-skip-permissions` 参数
4. **会话保存**：默认会话会保存到磁盘，可使用 `-r` 恢复

---

## 相关链接

- 官方文档：https://docs.anthropic.com/en/docs/claude-code/overview
- GitHub：https://github.com/anthropics/claude-code

---

*本文档将随 Claude Code 更新持续更新*

---

## Skills（Agent 技能）

Skills 是 Anthropic 推出的可复用 Agent 能力模块，来自官方仓库 [anthropics/skills](https://github.com/anthropics/skills)。每个 skill 是一个独立文件夹，包含 `SKILL.md` 文件，定义了 Claude 在特定任务场景下的执行指令。

> 注意：本项目 `.claude/commands/` 下的 `.md` 文件是**自定义斜杠命令（Slash Commands）**，不是标准 Skills，两者概念不同，见下方对比。

---

### Skills vs Slash Commands 对比

| 对比项 | Skills | Slash Commands（本项目用的） |
|--------|--------|------------------------------|
| 来源 | Anthropic 官方仓库或第三方发布 | 自己在 `.claude/commands/` 下创建 |
| 文件结构 | 独立文件夹 + `SKILL.md`（含 YAML frontmatter） | 单个 `.md` 文件 |
| 调用方式 | 由 Claude 自动识别触发，或 `/skill名` | `/文件名`（斜杠 + 文件名） |
| 适用范围 | 跨项目、可共享、可发布 | 当前项目内使用 |
| 典型用途 | 处理 PDF/Word/Excel 等通用能力 | 自定义角色、工作流、项目规范 |

---

### Skills 的结构

每个 skill 是一个文件夹，核心是 `SKILL.md`，格式如下：

```
my-skill/
├── SKILL.md          # 必须，定义 skill 的元数据和指令
└── （可选）脚本、模板等支持文件
```

`SKILL.md` 文件格式：

```markdown
---
name: skill-name
description: 描述这个 skill 做什么、何时触发
---

# 指令内容

这里写 Claude 执行该 skill 时需要遵循的具体指令...
```

| 字段 | 说明 |
|------|------|
| `name` | skill 的唯一标识符 |
| `description` | 描述用途，Claude 根据此判断何时自动调用 |
| 正文内容 | Claude 执行时遵循的 Markdown 指令 |

---

### Anthropic 官方 Skills 列表

来自 [github.com/anthropics/skills](https://github.com/anthropics/skills)：

| Skill 名称 | 用途 |
|------------|------|
| `pdf` | 读取和处理 PDF 文件内容 |
| `docx` | 读取和处理 Word 文档（.docx） |
| `xlsx` | 读取和处理 Excel 表格（.xlsx） |
| `pptx` | 读取和处理 PowerPoint 文件（.pptx） |

---

### 如何使用官方 Skills

将 skill 文件夹放入项目的 `.claude/skills/` 目录，Claude 会在任务匹配时自动加载：

```
项目根目录/
└── .claude/
    └── skills/
        └── pdf/
            └── SKILL.md
```

也可以通过斜杠命令手动触发：

```
/pdf   分析这份合同文件
/docx  帮我总结这个 Word 文档
```

---

### 自定义斜杠命令（本项目配置）

本项目在 `.claude/commands/` 下配置了一组自定义斜杠命令，用于模拟不同角色的工作方式：

| 命令 | 角色 | 主要职责 | 输出内容 |
|------|------|----------|----------|
| `/需求大师` | 产品经理 | 分析需求、编写用户故事、评估优先级（P0/P1/P2）、识别边界情况 | 功能描述、验收标准、边界情况、依赖关系 |
| `/架构师` | 技术架构师 | 设计系统架构、数据库表结构、API 规范、技术选型 | 数据库 SQL、API 文档、模块划分说明 |
| `/UI设计` | UI 设计师 | 生成 H5 高保真原型、制定设计规范、设计交互动画 | 独立 `.html` 原型文件，移动端适配（375px） |
| `/iOS开发` | iOS 工程师 | SwiftUI 页面开发、业务逻辑、对接 API 和 WebSocket | Swift 代码文件，含中文注释 |
| `/后端开发` | 后端工程师 | RESTful API 实现、数据库操作、第三方服务集成 | 按 controllers/models/services 分层的代码 |
| `/测试工程师` | 测试工程师 | 编写测试用例、API 接口测试、Bug 分析 | 按 P0/P1/P2 优先级分类的测试用例 |

**推荐协作顺序：**

```
/需求大师 → /架构师 → /UI设计
                   → /iOS开发
                   → /后端开发
                   → /测试工程师
```

**如何创建新的斜杠命令：**

在 `.claude/commands/` 下新建 `.md` 文件，文件名即为命令名：

```
.claude/commands/你的命令名.md
```

文件内容直接写角色定位、职责和输出格式即可，无需 YAML frontmatter。
