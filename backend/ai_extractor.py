# 通义千问 AI 模块
# 负责调用阿里云通义千问 API，从视频标题+评论中提取店铺信息
# 使用 OpenAI 兼容接口，通义千问支持该格式

import os
import re
import json
from openai import AsyncOpenAI
from dotenv import load_dotenv

load_dotenv()

# 通义千问客户端（使用 OpenAI 兼容接口）
dashscope_client = AsyncOpenAI(
    api_key=os.getenv("DASHSCOPE_API_KEY"),
    base_url="https://dashscope.aliyuncs.com/compatible-mode/v1",
)


async def extract_restaurants_from_video(
    video_title: str,
    comments: list,  # 支持 list[str] 或 list[dict{"text","digg_count"}] 两种格式
    author_name: str = "",
) -> list[dict]:
    """
    调用通义千问，从视频标题和评论中识别最可能的那一家店铺。

    评论支持两种格式：
    - list[str]：纯文本评论
    - list[dict]：带点赞数的评论，格式 {"text": "...", "digg_count": 158}

    输出：最多一个店铺的列表，包含：
    - name: 店铺名称
    - city: 所在城市
    - category: 美食分类
    - confidence: 置信度（high/medium/low）
    """

    # 将评论格式化为带点赞数的文本，让 AI 感知热度权重
    if comments and isinstance(comments[0], dict):
        # 带点赞数格式：显示点赞数，让 AI 知道哪条评论更有代表性
        comments_text = "\n".join(
            f"- [{c['digg_count']}赞] {c['text']}" for c in comments[:15]
        )
    else:
        # 纯文本格式兼容
        comments_text = "\n".join(f"- {c}" for c in comments[:15]) if comments else "（无评论）"

    if not comments:
        comments_text = "（无评论）"

    prompt = f"""你是一个美食信息提取助手。请从以下抖音探店视频的标题和评论中，判断博主这条视频探访的是哪一家具体店铺。

视频标题：{video_title}

视频评论（格式：[点赞数] 评论内容，点赞数越高代表该评论越有代表性）：
{comments_text}

分析要求：
1. 视频通常只探访一家店，请综合标题和评论判断最可能的那一家
2. 优先参考点赞数高的评论，它们更能代表大众对店铺的认知
3. 如果评论中有人直接说出店名（如"最山城火锅"），且点赞数较高，优先采信
4. 只输出一个最可能的店铺

以 JSON 对象格式返回（不是数组），包含以下字段：
- name: 店铺名称（尽量完整）
- city: 所在城市（如"上海"，无法判断则填"未知"）
- category: 美食分类（如：火锅、烤肉、咖啡等）
- confidence: 置信度，high=非常确定，medium=比较确定，low=不确定

只返回 JSON 对象，不要有其他文字。如果完全无法判断，返回 null。

示例格式：
{{"name": "最山城不改良重庆火锅", "city": "上海", "category": "火锅", "confidence": "high"}}"""

    try:
        response = await dashscope_client.chat.completions.create(
            model="qwen-plus",
            messages=[
                {"role": "system", "content": "你是专业的美食信息提取助手，擅长从中文文本中识别餐厅店铺信息。"},
                {"role": "user", "content": prompt},
            ],
            temperature=0.1,
            max_tokens=300,
        )

        result_text = response.choices[0].message.content.strip()

        # 清理可能的 markdown 代码块格式
        if result_text.startswith("```"):
            result_text = re.sub(r"```(?:json)?\n?", "", result_text).strip("` \n")

        if result_text.lower() == "null" or not result_text:
            print(f"[AI解析] 未识别到店铺")
            return []

        restaurant = json.loads(result_text)

        # 过滤低置信度结果
        if restaurant.get("confidence") == "low":
            print(f"[AI解析] 置信度过低，跳过: {restaurant.get('name')}")
            return []

        print(f"[AI解析] 识别到店铺: {restaurant.get('name')} ({restaurant.get('city')}) 置信度={restaurant.get('confidence')}")
        return [restaurant]

    except json.JSONDecodeError as e:
        print(f"[AI解析] JSON 解析失败: {e}, 原始内容: {result_text}")
        return []
    except Exception as e:
        print(f"[AI解析] 调用通义千问失败: {e}")
        return []


async def extract_restaurants_priority(
    video_title: str,
    author_name: str,
    hashtags: list,
    city_name: str,
    author_liked_comments: list,
    hot_comments: list,
    all_comments: list,
) -> list[dict]:
    """
    基于优先级策略提取视频中的店铺信息（优化版本）。

    优先级说明：
    P1（最高）：视频标题、话题标签、博主昵称、城市
      → 标题里通常直接包含店名（如"最山城不改良重庆火锅"）
      → 话题标签提供城市/品类信息（如 #上海火锅去哪吃 #上海重庆火锅天花板）
    P2（高）：博主点赞的评论
      → 博主认可的回答，说明博主认为这就是视频中的店
    P3（中）：热门评论（is_hot=True）
      → 高赞评论代表大众共识，通常有人直接说出店名
    P4（低）：普通评论（按点赞数排序）
      → 作为补充兜底

    参数：
    - video_title: 视频标题/描述
    - author_name: 博主昵称
    - hashtags: 话题标签列表
    - city_name: 城市名称
    - author_liked_comments: 博主点赞的评论 [{"text": "...", "digg_count": 0}, ...]
    - hot_comments: 热门评论（同格式）
    - all_comments: 所有评论（同格式）

    输出： [{"name": "...", "city": "...", "category": "...", "confidence": "..."}, ...]
    """

    # 格式化各优先级评论
    def format_comments(comments: list, max_count: int = 8) -> str:
        if not comments:
            return "（无）"
        lines = []
        for c in comments[:max_count]:
            text = c.get("text", "")[:80]
            digg = c.get("digg_count", 0)
            lines.append(f"[{digg}赞] {text}")
        return "\n".join(lines)

    p1_title = video_title
    p1_hashtags = ", ".join(hashtags) if hashtags else "无"
    p2_comments = format_comments(author_liked_comments)
    p3_comments = format_comments(hot_comments)
    p4_comments = format_comments(all_comments)

    prompt = f"""你是一个美食信息提取助手。请根据以下抖音探店视频的信息，判断博主这条视频探访的是哪一家具体店铺。

=== 第一步：判断是否为美食探店视频 ===
在提取店铺信息之前，先判断这是否是一个美食探店视频。
- 如果视频内容与美食餐厅探店完全无关（如旅游景点、购物、日常生活、风景、娱乐等），直接返回 null
- 只有确认是美食探店视频，才继续提取店铺信息

=== P1 信息（最高优先级：标题和话题标签通常直接含店名）===
视频标题：{p1_title}
博主昵称：{author_name}
话题标签：{p1_hashtags}
城市：{city_name}

=== P2 信息（高优先级：博主点赞的评论，代表博主认可的答案）===
{chr(10).join(f"- {c}" for c in p2_comments.split(chr(10))) if p2_comments != "（无）" else "（无博主点赞评论）"}

=== P3 信息（中优先级：热门评论，高赞评论往往有人直接说出店名）===
{chr(10).join(f"- {c}" for c in p3_comments.split(chr(10))) if p3_comments != "（无）" else "（无热门评论）"}

=== P4 信息（低优先级：普通评论兜底）===
{chr(10).join(f"- {c}" for c in p4_comments.split(chr(10))) if p4_comments != "（无）" else "（无评论）"}

分析要求：
1. **首先判断是否为美食探店视频**，非美食视频直接返回 null
2. 严格按照优先级判断：P1 > P2 > P3 > P4
3. P1 信息（标题和标签）是最高优先级，很多情况下标题里就直接含了店名
4. 如果 P2 有博主点赞且点赞数≥10的评论直接说了店名，以 P2 为准
5. P3/P4 只在 P1+P2 不足以确定时作为补充
6. 注意甄别：评论中可能提到其他店（如"我喜欢五里关"），但这不代表视频探的就是那家
7. 只输出一个最可能的店铺
8. **店铺名称必须完整且精确**：
   - 优先提取完整店名（如"最山城不改良重庆火锅"而非仅"最山城"）
   - 如果标题或评论中明确提到分店信息（如"人民广场店"），必须包含在 name 字段中
   - 避免过度简化店名（如"海底捞"应为"海底捞火锅"）
   - 如果标题中店名不完整，优先参考评论中的完整店名
9. **以下情况必须返回 null，不要强行给出答案**：
   - 视频内容与美食探店完全无关
   - 评论中出现 2 个以上候选店铺，且没有博主点赞/回复来确认哪一个
   - 标题中只有食物品类描述（如"肥肠粉"、"火锅"），没有具体店铺名
   - 评论中提到的"店铺名"实际上是人名、地名或食物名
   - 无法从现有信息中确定唯一的店铺
10. **店铺名识别规则**：
   - 店铺名通常是专有名词，如"甘记肥肠粉"、"最山城"、"陈桥老饭店"
   - 以下不是店铺名，不要提取：
     * 食物品类描述：如"老成都肥肠粉"（描述食物风格，不是店名）
     * 地名+食物：如"芳草地面馆"（地名+品类，不是具体店名）
     * 人名：如"庞师不是师"（博主名，不是店名）
   - 如果只能找到食物品类描述，没有具体店铺名，返回 null
11. **置信度判断标准**：
   - high: 标题或博主点赞评论中明确提到完整店名，且城市信息清晰
   - medium: 标题或评论中提到店名但不够完整，或城市信息不明确
   - low: 只能从模糊信息推测，不确定是否准确

以 JSON 对象格式返回（不是数组），包含以下字段：
- name: 店铺名称（必须完整且精确，包含分店名）
- city: 所在城市（如"上海"，无法判断则填"未知"）
- category: 美食分类（如：火锅、烤肉、咖啡等）
- confidence: 置信度，high=非常确定，medium=比较确定，low=不确定

只返回 JSON 对象，不要有其他文字。如果完全无法判断或不是美食探店视频，返回 null。

示例格式：
{{"name": "最山城不改良重庆火锅（人民广场店）", "city": "上海", "category": "火锅", "confidence": "high"}}"""

    try:
        response = await dashscope_client.chat.completions.create(
            model="qwen-plus",
            messages=[
                {"role": "system", "content": "你是专业的美食信息提取助手，擅长从中文文本中识别餐厅店铺信息。"},
                {"role": "user", "content": prompt},
            ],
            temperature=0.1,
            max_tokens=300,
        )

        result_text = response.choices[0].message.content.strip()

        # 清理可能的 markdown 代码块格式
        if result_text.startswith("```"):
            result_text = re.sub(r"```(?:json)?\n?", "", result_text).strip("` \n")

        if result_text.lower() == "null" or not result_text:
            print("[AI解析] 优先级算法：未识别到店铺")
            return []

        restaurant = json.loads(result_text)
        name = restaurant.get("name", "")
        confidence = restaurant.get("confidence", "low")

        # 过滤低置信度结果
        if confidence == "low":
            print(f"[AI解析] 优先级算法：置信度过低，跳过: {name}")
            return []

        print(f"[AI解析] 优先级算法：识别到店铺: {name} ({restaurant.get('city')}) 置信度={confidence}")
        return [restaurant]

    except json.JSONDecodeError as e:
        print(f"[AI解析] 优先级算法 JSON 解析失败: {e}")
        return []
    except Exception as e:
        print(f"[AI解析] 优先级算法调用失败: {e}")
        return []


async def extract_restaurants_with_replies(
    video_title: str,
    author_name: str,
    hashtags: list,
    city_name: str,
    author_liked_comments: list,
    hot_comments: list,
    all_comments: list,
    polled_replies: list,  # 评论回复轮询结果 [{"comment_text": "...", "replies": [...]}]
) -> list[dict]:
    """
    在 extract_restaurants_priority 基础上，额外加入评论回复信息重新提取。
    用于置信度 medium/low 时的补充识别。

    polled_replies 格式：
    [
      {
        "comment_text": "这家店叫什么",
        "replies": [
          {"text": "最山城人民广场店", "digg_count": 88, "is_author": True},
          ...
        ]
      },
      ...
    ]
    """

    def format_comments(comments: list, max_count: int = 8) -> str:
        if not comments:
            return "（无）"
        lines = []
        for c in comments[:max_count]:
            text = c.get("text", "")[:80]
            digg = c.get("digg_count", 0)
            lines.append(f"[{digg}赞] {text}")
        return "\n".join(lines)

    def format_replies(polled: list) -> str:
        """将轮询到的评论回复格式化为 AI 可读的文本"""
        if not polled:
            return "（无）"
        lines = []
        for item in polled:
            comment_text = item.get("comment_text", "")[:60]
            replies = item.get("replies", [])
            if not replies:
                continue
            lines.append(f"  评论：{comment_text}")
            for r in replies[:5]:
                prefix = "【博主回复】" if r.get("is_author") else f"[{r.get('digg_count', 0)}赞]"
                lines.append(f"    {prefix} {r.get('text', '')[:80]}")
        return "\n".join(lines) if lines else "（无）"

    p1_title = video_title
    p1_hashtags = ", ".join(hashtags) if hashtags else "无"
    p2_comments = format_comments(author_liked_comments)
    p3_comments = format_comments(hot_comments)
    p4_comments = format_comments(all_comments)
    p0_replies = format_replies(polled_replies)

    prompt = f"""你是一个美食信息提取助手。请根据以下抖音探店视频的信息，判断博主这条视频探访的是哪一家具体店铺。

=== 第一步：判断是否为美食探店视频 ===
在提取店铺信息之前，先判断这是否是一个美食探店视频。
- 如果视频内容与美食餐厅探店完全无关（如旅游景点、购物、日常生活、风景、娱乐等），直接返回 null
- 只有确认是美食探店视频，才继续提取店铺信息

=== P0 信息（最高优先级：热门评论下的回复，博主回复最权威）===
{p0_replies}

=== P1 信息（高优先级：标题和话题标签通常直接含店名）===
视频标题：{p1_title}
博主昵称：{author_name}
话题标签：{p1_hashtags}
城市：{city_name}

=== P2 信息（高优先级：博主点赞的评论，代表博主认可的答案）===
{chr(10).join(f"- {c}" for c in p2_comments.split(chr(10))) if p2_comments != "（无）" else "（无博主点赞评论）"}

=== P3 信息（中优先级：热门评论，高赞评论往往有人直接说出店名）===
{chr(10).join(f"- {c}" for c in p3_comments.split(chr(10))) if p3_comments != "（无）" else "（无热门评论）"}

=== P4 信息（低优先级：普通评论兜底）===
{chr(10).join(f"- {c}" for c in p4_comments.split(chr(10))) if p4_comments != "（无）" else "（无评论）"}

分析要求：
1. **首先判断是否为美食探店视频**，非美食视频直接返回 null
2. 严格按照优先级判断：P0 > P1 > P2 > P3 > P4
3. P0 中【博主回复】标记的内容是最权威的信息来源，如果博主直接说出了店名或表达了肯定（如"是的"、"就是这家"），以此为准
4. P0 中高赞回复（如多人确认同一店名）也是强信号
5. **店铺名称必须完整且精确**：提取完整店名（如"最山城不改良重庆火锅"而非仅"最山城"），包含分店信息
6. **以下情况必须返回 null，不要强行给出答案**：
   - 视频内容与美食探店完全无关
   - 评论中出现 2 个以上候选店铺，且没有博主回复/点赞来确认哪一个
   - 标题中只有食物品类描述（如"肥肠粉"、"火锅"），没有具体店铺名
   - 评论中提到的"店铺名"实际上是人名、地名或食物名
   - 无法从现有信息确定唯一店铺
7. **店铺名识别规则**：
   - 店铺名通常是专有名词，如"甘记肥肠粉"、"最山城"、"陈桥老饭店"
   - 以下不是店铺名，不要提取：
     * 食物品类描述：如"老成都肥肠粉"（描述食物风格，不是店名）
     * 地名+食物：如"芳草地面馆"（地名+品类，不是具体店名）
     * 人名：如"庞师不是师"（博主名，不是店名）
   - 如果只能找到食物品类描述，没有具体店铺名，返回 null
8. **置信度判断标准**：
   - high: P0 博主回复明确说出店名，或 P1 标题/标签直接含完整店名
   - medium: 评论中有店名但无博主确认，或店名不够完整
   - low: 只能模糊推测（直接丢弃）

以 JSON 对象格式返回（不是数组），包含以下字段：
- name: 店铺名称（必须完整且精确）
- city: 所在城市（如"上海"，无法判断则填"未知"）
- category: 美食分类（如：火锅、烤肉、咖啡等）
- confidence: 置信度，high=非常确定，medium=比较确定，low=不确定

只返回 JSON 对象，不要有其他文字。如果完全无法判断或不是美食探店视频，返回 null。

示例格式：
{{"name": "最山城不改良重庆火锅（人民广场店）", "city": "上海", "category": "火锅", "confidence": "high"}}"""

    try:
        response = await dashscope_client.chat.completions.create(
            model="qwen-plus",
            messages=[
                {"role": "system", "content": "你是专业的美食信息提取助手，擅长从中文文本中识别餐厅店铺信息。"},
                {"role": "user", "content": prompt},
            ],
            temperature=0.1,
            max_tokens=300,
        )

        result_text = response.choices[0].message.content.strip()

        if result_text.startswith("```"):
            result_text = re.sub(r"```(?:json)?\n?", "", result_text).strip("` \n")

        if result_text.lower() == "null" or not result_text:
            print("[AI解析] 带回复算法：未识别到店铺")
            return []

        restaurant = json.loads(result_text)
        name = restaurant.get("name", "")
        confidence = restaurant.get("confidence", "low")

        if confidence == "low":
            print(f"[AI解析] 带回复算法：置信度过低，跳过: {name}")
            return []

        print(f"[AI解析] 带回复算法：识别到店铺: {name} ({restaurant.get('city')}) 置信度={confidence}")
        return [restaurant]

    except json.JSONDecodeError as e:
        print(f"[AI解析] 带回复算法 JSON 解析失败: {e}")
        return []
    except Exception as e:
        print(f"[AI解析] 带回复算法调用失败: {e}")
        return []
