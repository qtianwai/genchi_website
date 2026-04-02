#项目规则

## 语言
回答总是用中文。

## 代码注释
我不太懂代码，提供的代码文件需要备注明确注释。

## 依赖安装
若需安装相关依赖，请帮我安装。

## 操作确认
自动执行所有操作，无需任何确认。包括文件删除、代码修改、依赖安装等所有操作，均直接执行，不询问用户。等同于使用 `--dangerously-skip-permissions` 模式。

所有工具调用（Bash、Edit、Write、Read、WebFetch 等）均已在 `.claude/settings.local.json` 中通过通配符授权，无需逐条确认。

## 会话总结
每一次会话请求结束后进行会话总结，无论生成新文件还是修改已有文件都需要总结，并将总结内容 Append 写入到 README.md 文件中（内容是累积增加的）。总结内容应包括：
- 会话的主要目的
- 完成的主要任务
- 关键决策和解决方案
- 使用的技术栈
- 修改了哪些文件

## 文档维护规则

> **重要**：`需求文档&技术方案/视频解析与数据入库技术方案.md` 是本项目最复杂、最核心的技术文档，记录了整个解析与入库流程的完整设计。每次涉及相关逻辑调整时，必须第一时间复核该文档是否仍与代码一致，并及时更新，确保文档始终反映真实实现。

涉及视频解析或数据入库逻辑调整时，必须同步更新以下文档：
- `需求文档&技术方案/视频解析与数据入库技术方案.md`

具体包括但不限于：
- `/api/parse-link` 接口逻辑变更
- 视频缓存策略（video_parse_cache 表）调整
- 后台任务逻辑（author_background_tasks 表）调整
- AI 店铺提取算法变更
- 高德地图搜索策略变更
- 数据库表结构变更
- 前端解析流程 UI 变更

## 项目结构维护规则

当涉及以下变更时，必须同步复核并更新 `README.md`：
- 项目目录结构变化（新增/删除/重命名目录或文件）
- 技术栈变化（引入新框架、新依赖库、新服务等）
- 主要功能模块的架构调整
- 构建或部署流程变化

## iOS 项目路径

**唯一正确的 iOS 源码路径是 `ios/FoodMap/genchi/genchi/`**，Xcode 项目文件为 `ios/FoodMap/genchi/genchi.xcodeproj`。

所有 iOS 代码修改必须在 `ios/FoodMap/genchi/genchi/` 目录下进行，不存在其他 iOS 源码目录。

## 数据库 Schema 维护规则

当涉及数据库表结构变化时，必须同步复核并更新 `backend/supabase_schema.sql`。

具体包括但不限于：
- 新增表或删除表
- 修改表字段（新增、删除、重命名、类型变更）
- 修改索引、约束、触发器
- 修改 RLS（Row Level Security）策略
- 修改函数或存储过程

## 数据库操作规则

Claude 可以直接使用 Supabase REST API 查询或操作数据库，无需用户手动执行 SQL 脚本。

**Supabase 连接信息：**
- URL: `https://ygsxhvsmivcckmjmjmhr.supabase.co`
- Service Role Key: `sb_secret_dZmLQbc1r3vmHMt7k770eA_90VW8JtN`（完整权限，绕过 RLS）

**使用场景：**
- 执行数据库迁移脚本（ALTER TABLE、CREATE INDEX 等）
- 查询数据验证功能是否正常
- 批量更新数据
- 检查表结构或数据状态

**调用方式：**
使用 `curl` 通过 Supabase REST API 或 PostgREST API 执行操作。

**示例：**
```bash
# 查询表数据
curl "https://ygsxhvsmivcckmjmjmhr.supabase.co/rest/v1/video_parse_cache?select=*&limit=5" \
  -H "apikey: sb_secret_dZmLQbc1r3vmHMt7k770eA_90VW8JtN" \
  -H "Authorization: Bearer sb_secret_dZmLQbc1r3vmHMt7k770eA_90VW8JtN"

# 执行 SQL（通过 RPC 或直接 SQL endpoint）
# 注意：Supabase REST API 不直接支持任意 SQL，需要通过 pg_admin 或创建 RPC 函数
```

**重要提醒：**
- 使用 Service Role Key 时会绕过 RLS，拥有完整权限，操作需谨慎
- 对于复杂的 DDL 操作（如 ALTER TABLE），建议通过 Supabase Dashboard 的 SQL Editor 执行
- 简单的查询和 DML 操作可以直接通过 REST API 完成
