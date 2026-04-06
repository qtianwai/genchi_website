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


# ─────────────────────────────────────────
# 视频标题 AI 过滤（优化 3.2：零成本过滤非美食视频）
# ─────────────────────────────────────────

async def filter_food_video_titles(video_titles: list[dict]) -> list[dict]:
    """
    批量过滤视频标题，判断是否为美食/探店类视频（零 JustOneAPI 成本）。

    优化 3.2：将一批视频标题（如 10~20 条）一次性发给 AI，批量判断是否为探店/美食类。
    不消耗任何 JustOneAPI 接口调用，只消耗 AI 调用（通义千问）。

    输入格式：[{"video_id": "...", "title": "...", "share_url": "..."}, ...]
    输出格式：保留原格式，只过滤掉非美食/探店视频
           [过滤后的视频列表，未通过的为空列表（表示全部过滤）]
    """
    if not video_titles:
        return []

    # 构建 AI prompt
    titles_text = "\n".join(
        f'{i+1}. {v.get("title", "")}' for i, v in enumerate(video_titles)
    )

    prompt = f"""你是一个美食探店视频识别专家。请判断以下抖音视频标题列表中，哪些是"探店/美食推荐"类视频。

定义：探店/美食推荐视频是指博主前往某个实体店铺（餐厅、咖啡馆、小吃店、奶茶店、火锅店、烧烤摊等），介绍这家店的美食内容的视频。

请对每个标题返回 true（是探店/美食视频）或 false（不是探店/美食视频）。

标题列表：
{titles_text}

要求：
1. 标题为空时，保守处理为 true（不过滤，避免漏掉无标题的探店视频）
2. 只根据标题判断，不要猜测
3. 以下类型应返回 false：
   - 旅游景点介绍（如"三亚旅游攻略"、"打卡网红景点"）
   - 日常生活分享（如"今天吃了什么"、"周末日常"）
   - 购物开箱（如"新买的衣服"、"开箱测评"）
   - 娱乐内容（如"搞笑合集"、"舞蹈视频"）
   - 知识科普（如"如何做菜"、"烹饪教程"）—— 注意：这是教做菜，不是探店
   - 纯风景/打卡（如"这个海边太美了"）

以 JSON 数组格式返回，每个元素为 true 或 false，顺序与输入标题对应。
示例：[true, false, true, false]

只返回 JSON 数组，不要有其他文字。"""

    try:
        response = await dashscope_client.chat.completions.create(
            model="qwen-plus",
            messages=[
                {"role": "system", "content": "你是专业的美食探店视频识别专家，擅长判断视频是否属于探店/美食推荐类内容。"},
                {"role": "user", "content": prompt},
            ],
            temperature=0.1,
            max_tokens=500,
        )

        result_text = response.choices[0].message.content.strip()

        # 清理可能的 markdown 代码块格式
        if result_text.startswith("```"):
            result_text = re.sub(r"```(?:json)?\n?", "", result_text).strip("` \n")

        # 解析 JSON 数组
        try:
            results = json.loads(result_text)
        except json.JSONDecodeError:
            print(f"[AI过滤] JSON 解析失败，返回全部保留: {result_text[:100]}")
            return video_titles

        # 验证结果长度
        if len(results) != len(video_titles):
            print(f"[AI过滤] 结果长度不匹配 ({len(results)} vs {len(video_titles)})，返回全部保留")
            return video_titles

        # 过滤视频列表
        filtered = [
            video for video, is_food in zip(video_titles, results)
            if is_food
        ]

        filtered_count = len(filtered)
        total_count = len(video_titles)
        print(f"[AI过滤] 过滤完成: {total_count} 条视频中保留 {filtered_count} 条美食探店视频（过滤掉 {total_count - filtered_count} 条）")

        return filtered

    except Exception as e:
        print(f"[AI过滤] AI 调用失败: {e}，返回全部保留")
        return video_titles


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
- reason: 判断依据（简短说明你是从哪里得出这个店铺名的，如"标题直接包含店名"、"评论中多次提到该店名"；如果返回 null，说明为什么无法判断）

只返回 JSON 对象，不要有其他文字。如果完全无法判断，返回 {{"result": null, "reason": "无法判断的原因"}}。

示例格式：
{{"name": "最山城不改良重庆火锅", "city": "上海", "category": "火锅", "confidence": "high", "reason": "标题直接包含完整店名"}}"""

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

        parsed = json.loads(result_text)

        # 兼容 {"result": null, "reason": "..."} 格式（无法判断时）
        if parsed.get("result") is None and "reason" in parsed:
            print(f"[AI解析] 未识别到店铺，原因: {parsed.get('reason')}")
            return [{"_no_result": True, "reason": parsed.get("reason", "")}]

        restaurant = parsed

        # 过滤低置信度结果
        if restaurant.get("confidence") == "low":
            print(f"[AI解析] 置信度过低，跳过: {restaurant.get('name')}")
            return [{"_no_result": True, "reason": f"置信度过低: {restaurant.get('reason', '')}"}]

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
    rule_candidates: list = None,
    hot_search_keywords: list = None,  # v10.0 新增：抖音热搜词
) -> list[dict]:
    """
    基于优先级策略提取视频中的店铺信息（v10.0 优化版本）。

    v10.0 变化：
    - 新增 rule_candidates 参数：规则预提取的候选列表，辅助 AI 决策
    - 放宽 null 返回条件：多候选时选最可能的，不再直接返回 null
    - low 置信度不再丢弃：返回结果但标记为 low（后续不入库但缓存供复核参考）
    - 去掉评论回复接口依赖

    优先级说明：
    P1（最高）：视频标题、话题标签、博主昵称、城市
    P2（高）：博主点赞的评论
    P3（中）：热门评论（is_hot=True）
    P4（低）：普通评论（按点赞数排序）

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

    # 格式化规则候选
    def format_candidates(candidates: list) -> str:
        if not candidates:
            return "（无候选）"
        lines = []
        for i, c in enumerate(candidates[:8]):
            lines.append(f"{i+1}. [{c.get('score', 0)}分/{c.get('source', '未知')}] {c.get('name', '')}")
        return "\n".join(lines)

    p1_title = video_title
    p1_hashtags = ", ".join(hashtags) if hashtags else "无"
    p2_comments = format_comments(author_liked_comments)
    p3_comments = format_comments(hot_comments)
    p4_comments = format_comments(all_comments)
    candidates_text = format_candidates(rule_candidates or [])
    hot_keywords_text = ", ".join(hot_search_keywords) if hot_search_keywords else "无"

    prompt = f"""你是一个美食信息提取助手。请根据以下抖音探店视频的信息，判断博主这条视频探访的是哪一家具体店铺。

=== 第一步：判断是否为美食探店视频 ===
- 如果视频内容与美食餐厅探店完全无关（如旅游景点、购物、日常生活、风景、娱乐等），直接返回 null
- 只有确认是美食探店视频，才继续提取店铺信息

=== 规则预提取的候选店铺（供参考，可能包含噪音）===
{candidates_text}

=== P0 信息（极高优先级：抖音热搜词，通常就是店铺名或品牌名）===
热搜词：{hot_keywords_text}

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
2. **优先从规则候选中选择**：如果候选列表中有合理的店铺名，优先确认/选择，而非从零识别
3. 严格按照优先级判断：P1 > P2 > P3 > P4
4. P1 信息（标题和标签）是最高优先级，很多情况下标题里就直接含了店名
5. 如果 P2 有博主点赞且点赞数≥10的评论直接说了店名，以 P2 为准
6. P3/P4 只在 P1+P2 不足以确定时作为补充
7. 只输出一个最可能的店铺
8. **店铺名称必须完整且精确**：
   - 优先提取完整店名（如"最山城不改良重庆火锅"而非仅"最山城"）
   - 如果标题或评论中明确提到分店信息（如"人民广场店"），必须包含在 name 字段中
   - 如果标题中店名不完整，优先参考评论中的完整店名
9. **尽量给出答案，减少返回 null**：
   - 只有以下情况才返回 null：视频完全不是美食探店、所有信息中完全没有任何店铺线索
   - 如果有多个候选但无法确定唯一，选择出现频率最高或最合理的那个，置信度标为 medium
   - 如果只有模糊线索，也给出最可能的答案，置信度标为 low
   - 后续有人工复核兜底，不必过度谨慎
10. **店铺名识别规则**：
   - 店铺名通常是专有名词，如"甘记肥肠粉"、"最山城"、"陈桥老饭店"
   - 以下不是店铺名，不要提取：
     * 食物品类描述：如"老成都肥肠粉"（描述食物风格，不是店名）
     * 地名+食物：如"芳草地面馆"（地名+品类，不是具体店名）
     * 人名：如"庞师不是师"（博主名，不是店名）
     * 赞助商/品牌合作标签：话题标签中出现"华商"、"中国华商"等赞助商名称
   - 话题标签中的赞助商标签特征：通常与视频内容无关，如 #逢年过节中国华商 这类是推广标签
11. **分店信息必须精确提取**：
    - 如果标题或评论中明确提到分店地址（如"人民广场店"），必须包含在name字段中
    - 如果只识别出品牌名而缺少分店信息，置信度最多为 medium
12. **评论高频店铺识别**：
    - 多个高赞评论（≥20赞）反复提到同一店铺名（≥2次），可据此给出答案
    - 这种情况置信度最多为 medium
13. **置信度判断标准**：
   - high: 标题或博主点赞评论中明确提到完整店名，且城市信息清晰
   - medium: 标题或评论中提到店名但不够完整，或城市不明确，或通过评论高频/候选确认
   - low: 只能从模糊信息推测（仍然返回结果，后续由人工复核兜底）

以 JSON 对象格式返回，包含以下字段：
- name: 店铺名称（必须完整且精确，包含分店名）
- city: 所在城市（如"上海"，无法判断则填"未知"）
- category: 美食分类（如：火锅、烤肉、咖啡等）
- confidence: 置信度，high/medium/low
- reason: 判断依据（简短说明）

只返回 JSON 对象，不要有其他文字。如果完全无法判断或不是美食探店视频，返回 {{"result": null, "reason": "原因"}}。

**重要**：如果你在分析过程中已经识别到了可能的店铺名（即使不完全确定），必须以 JSON 店铺对象格式返回，不要返回 null。只有在完全没有任何店铺线索时才返回 null。如果你在 reason 中提到了某个店铺名，说明你已经识别到了，此时必须返回该店铺的 JSON 对象。

=== 反例示范 ===

反例1 - 标题描述当店铺名：
  标题：婆罗门云集的老成都冒烤鸭，紧实的鸭肉裹着淡淡的卤水香
  错误：{{"name": "婆罗门云集的老成都冒烤鸭"}} ← 这是描述不是店名！
  正确：{{"result": null, "reason": "标题只描述了食物风格，没有具体店铺名"}}

反例2 - 人名当店铺名：
  话题标签：#上海探店 #乔妹妹 #云南烧烤
  错误：{{"name": "乔妹妹云南烧烤"}} ← "乔妹妹"是人名！
  正确：{{"result": null, "reason": "话题标签中的乔妹妹是人名"}}

=== 正式输出 ===
示例：{{"name": "最山城不改良重庆火锅（人民广场店）", "city": "上海", "category": "火锅", "confidence": "high", "reason": "标题直接包含完整店名"}}"""

    try:
        response = await dashscope_client.chat.completions.create(
            model="qwen-plus",
            messages=[
                {"role": "system", "content": "你是专业的美食信息提取助手，擅长从中文文本中识别餐厅店铺信息。你的目标是尽量识别出店铺名，只有完全没有线索时才返回 null。"},
                {"role": "user", "content": prompt},
            ],
            temperature=0.1,
            max_tokens=400,
        )

        result_text = response.choices[0].message.content.strip()

        # 清理可能的 markdown 代码块格式
        if result_text.startswith("```"):
            result_text = re.sub(r"```(?:json)?\n?", "", result_text).strip("` \n")

        if result_text.lower() == "null" or not result_text:
            print("[AI解析] 优先级算法：未识别到店铺")
            return []

        parsed = json.loads(result_text)

        # 兼容 {"result": null, "reason": "..."} 格式（无法判断时）
        # v10.0 兜底：如果 reason 中实际包含了店铺名线索（AI 识别到了但格式不对），
        # 尝试从规则候选中找到匹配的店铺名作为结果
        if parsed.get("result") is None and "reason" in parsed:
            reason = parsed.get("reason", "")
            print(f"[AI解析] 优先级算法：AI 返回 null，原因: {reason}")

            # 兜底：检查 reason 中是否提到了规则候选中的店铺名
            if rule_candidates:
                for cand in rule_candidates:
                    cand_name = cand.get("name", "")
                    if cand_name and len(cand_name) >= 2 and cand_name.lower() in reason.lower():
                        print(f"[AI解析] 兜底：reason 中提到了候选「{cand_name}」，作为结果返回")
                        return [{
                            "name": cand_name,
                            "city": city_name or "未知",
                            "category": "",
                            "confidence": "medium",
                            "reason": f"AI返回null但reason中提到了{cand_name}（兜底提取）",
                        }]

            return [{"_no_result": True, "reason": reason}]

        restaurant = parsed
        name = restaurant.get("name", "")
        confidence = restaurant.get("confidence", "low")

        # v10.0 变化：low 置信度不再丢弃，返回结果但标记为 low
        # 后续 parse_single_video_fast 会根据置信度决定是否入库
        if confidence == "low":
            print(f"[AI解析] 优先级算法：低置信度结果（不入库但缓存）: {name}")
        else:
            print(f"[AI解析] 优先级算法：识别到店铺: {name} ({restaurant.get('city')}) 置信度={confidence}")

        return [restaurant]

    except json.JSONDecodeError as e:
        print(f"[AI解析] 优先级算法 JSON 解析失败: {e}")
        return []
    except Exception as e:
        print(f"[AI解析] 优先级算法调用失败: {e}")
        return []


# ─────────────────────────────────────────
# v10.0：extract_restaurants_with_replies 已移除
# 原因：评论回复接口（get-video-sub-comment）帮助不大且增加成本
# 替代方案：规则预提取（rule_extractor.py）+ AI 优化 prompt
# ─────────────────────────────────────────
