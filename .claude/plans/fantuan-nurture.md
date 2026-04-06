# 10.10 饭团养成体系实施计划

## 改动范围

| 层 | 文件 | 改动 |
|----|------|------|
| DB | Supabase SQL | 新建 `fantuan_status` 表 |
| 后端 | `backend/db.py` | 新增 6 个养成数据库函数 |
| 后端 | `backend/main.py` | 新增 3 个 API + 改造 3 个现有 API |
| iOS | `Models/Models.swift` | 新增 `FanTuanStatus` 模型 |
| iOS | `Services/APIService.swift` | 新增 3 个 API 方法 |
| iOS | `ViewModels/FanTuanViewModel.swift` | 新增养成属性+方法，改造 mood 判定逻辑 |
| iOS | `Views/FanTuanView.swift` | 新增长按手势（摸摸）+ 浮动数字动画 |
| iOS | `Views/FanTuanStatusView.swift` | 新建：饭团状态面板 |
| iOS | `Views/FanTuanView.swift` (FanTuanMenuSheet) | 菜单新增「饭团状态」入口 |
| iOS | `Views/MapView.swift` | APP 启动时调用登录签到 |
| 文档 | `supabase_schema.sql` | 追加表定义 |

## 实施步骤

### Step 1: 数据库建表

通过 Supabase REST API 执行 SQL，创建 `fantuan_status` 表：

```sql
CREATE TABLE fantuan_status (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID NOT NULL,
    satiety INTEGER NOT NULL DEFAULT 80,
    intimacy INTEGER NOT NULL DEFAULT 0,
    intimacy_level INTEGER NOT NULL DEFAULT 1,
    consecutive_login_days INTEGER NOT NULL DEFAULT 0,
    last_login_date DATE,
    last_pet_date DATE,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(user_id)
);
CREATE INDEX idx_fantuan_status_user ON fantuan_status(user_id);
```

同步更新 `backend/supabase_schema.sql`。

### Step 2: 后端 db.py — 新增 6 个函数

1. **`get_fantuan_status(user_id)`** — 查询饭团状态，不存在则自动创建默认记录（upsert）
2. **`fantuan_daily_login(user_id)`** — 每日登录签到：
   - 计算 `last_login_date` 到今天的天数差 `days_away`
   - 饱食度衰减：`satiety = max(0, satiety - days_away * 5)`
   - 连续登录：昨天登录过 → `consecutive_login_days + 1`，否则重置为 1
   - 饱食度 +10，亲密度 +2（连续≥3天则 ×1.5 → +3）
   - 更新 `last_login_date = today`，重算 `intimacy_level`
   - 返回更新后的完整状态
3. **`fantuan_pet(user_id)`** — 摸摸饭团：
   - 检查 `last_pet_date == today` → 返回 `{"already_pet": true}`
   - 饱食度 +5，亲密度 +3（连续≥3天 ×1.5 → +4）
   - 更新 `last_pet_date = today`
   - 返回更新后状态 + `{"already_pet": false}`
4. **`update_fantuan_on_gacha(user_id)`** — 抽卡附带：饱食度 +3，亲密度 +1（连续≥3天 ×1.5）
5. **`update_fantuan_on_checkin(user_id)`** — 打卡附带：饱食度 +15，亲密度 +5（连续≥3天 ×1.5）
6. **`update_fantuan_on_favorite(user_id)`** — 收藏附带：饱食度 +2

函数 4/5/6 内部逻辑统一：读取当前状态 → 计算新值（satiety 上限 100）→ 重算 intimacy_level → update → 返回更新后状态。

`intimacy_level` 计算逻辑（后端统一维护）：
```python
def _calc_intimacy_level(intimacy: int) -> int:
    if intimacy >= 500: return 5
    if intimacy >= 300: return 4
    if intimacy >= 150: return 3
    if intimacy >= 50: return 2
    return 1
```

### Step 3: 后端 main.py — 新增 3 个 API

```python
# 请求模型
class FanTuanUserRequest(BaseModel):
    user_id: str

# GET /api/fantuan/status?user_id=xxx
# 返回：{ satiety, intimacy, intimacy_level, consecutive_login_days, last_login_date, last_pet_date }

# POST /api/fantuan/login  body: { user_id }
# 返回：{ status, satiety_change, intimacy_change, fantuan_status: {...} }

# POST /api/fantuan/pet  body: { user_id }
# 返回：{ status, already_pet, satiety_change, intimacy_change, fantuan_status: {...} }
```

### Step 4: 后端 main.py — 改造 3 个现有 API

在以下端点的成功逻辑末尾，附带调用养成更新函数，并将 `fantuan_status` 附加到响应中：

1. **`/api/gacha/select`**（约 L2646）— 在成就检测后追加：
   ```python
   fantuan = update_fantuan_on_gacha(req.user_id)
   # 返回中追加 "fantuan_status": fantuan
   ```

2. **`/api/checkins`**（约 L2803）— 在成就检测后追加：
   ```python
   fantuan = update_fantuan_on_checkin(req.user_id)
   # 返回中追加 "fantuan_status": fantuan
   ```

3. **`/api/favorites/add`**（约 L1441）— 在 return 前追加：
   ```python
   fantuan = update_fantuan_on_favorite(req.user_id)
   # 返回中追加 "fantuan_status": fantuan
   ```

### Step 5: iOS Models.swift — 新增模型

```swift
struct FanTuanStatus: Codable, Hashable {
    let satiety: Int
    let intimacy: Int
    let intimacy_level: Int
    let consecutive_login_days: Int
    let last_login_date: String?
    let last_pet_date: String?
}

struct FanTuanLoginResponse: Codable {
    let status: String
    let satiety_change: Int
    let intimacy_change: Int
    let fantuan_status: FanTuanStatus
}

struct FanTuanPetResponse: Codable {
    let status: String
    let already_pet: Bool
    let satiety_change: Int
    let intimacy_change: Int
    let fantuan_status: FanTuanStatus
}
```

### Step 6: iOS APIService.swift — 新增 3 个方法

```swift
func getFanTuanStatus(userId: String) async throws -> FanTuanStatus
func fanTuanLogin(userId: String) async throws -> FanTuanLoginResponse
func fanTuanPet(userId: String) async throws -> FanTuanPetResponse
```

### Step 7: iOS FanTuanViewModel.swift — 养成集成

新增 @Published 属性：
- `fanTuanStatus: FanTuanStatus?` — 养成数值
- `showPetFeedback: Bool` — 摸摸反馈动画开关
- `petFeedbackText: String` — 浮动文字（"+5 饱食度 +3 亲密度"）
- `todayPetted: Bool` — 今日是否已摸

新增方法：
- `loadStatus(userId:)` — 加载养成状态
- `dailyLogin(userId:)` — 登录签到，更新状态
- `petFanTuan(userId:)` — 摸摸饭团，调 API + 播放 happy 动画 + 显示浮动数字
- `updateStatusFromResponse(_ status: FanTuanStatus)` — 统一更新本地状态

改造 `updateMoodForCurrentTime()`：
```
饱食度优先级高于时间段：
if satiety < 20 → mood = .starving（最高优先级）
elif satiety < 50 → mood = .hungry（高于时间段）
else → 按现有时间/天气逻辑
```

改造冒泡文案：根据 `intimacy_level` 选择不同语气的文案池。

### Step 8: iOS FanTuanView.swift — 手势改造

将 `.onTapGesture` 改为同时支持短按和长按：
- 短按（现有逻辑）：打开菜单
- 长按（0.5 秒）：触发摸摸

长按触发后：
1. 调用 `viewModel.petFanTuan(userId:)`
2. 播放 happy 动画
3. 显示浮动数字动画（"+5 饱食度 +3 亲密度" 向上飘出并淡出）
4. 已摸过则显示冒泡"今天已经被摸过啦~明天再来嘛"

### Step 9: iOS FanTuanStatusView.swift — 新建状态面板

Sheet 弹窗，从 FanTuanMenuSheet 新增入口进入：
- 顶部：大号饭团动画（120pt，当前状态）
- 饱食度进度条：绿(≥50)/黄(20-49)/红(<20) + 数字
- 亲密度：等级名称 + 进度条（当前值/下一等级阈值）
- 连续登录天数
- "今日已摸摸 ✓" 或 "摸摸饭团" 按钮

### Step 10: iOS MapView.swift — 登录签到

在 `.task` 中（加载地图数据的同一位置），调用：
```swift
await fanTuanVM.dailyLogin(userId: authState.userId)
```

这样每次打开 APP 自动签到，饱食度衰减也在此时计算。

### Step 11: FanTuanMenuSheet — 新增入口

在现有两个能力卡片（干饭抽卡、智能问答）下方，新增第三个卡片：
- 图标：heart.fill（粉色）
- 标题："饭团状态"
- 副标题：显示当前饱食度和亲密度等级
- 点击打开 FanTuanStatusView

### Step 12: 文档更新

- `backend/supabase_schema.sql` 追加表定义
- `需求文档&技术方案/AI美食决策助手实施计划.md` 更新 10.10 状态为已完成
- `需求文档&技术方案/产品功能清单.md` 新增已完成功能
- `README.md` 追加会话总结
- `帮助文档/会话记录.md` 追加记录
