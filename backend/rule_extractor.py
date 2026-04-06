# 规则预提取模块
# 在 AI 调用之前，用正则/规则从视频标题、话题标签、评论中提取候选店铺名
# 零 API 成本，纯本地计算，用于辅助 AI 决策和兜底

import re
from collections import Counter


# ─────────────────────────────────────────
# 停用词表：这些词单独出现时不是店铺名
# ─────────────────────────────────────────

# 探店/美食泛词（单独出现时剔除，作为店名一部分时保留）
STOP_WORDS = {
    "探店", "打卡", "必吃", "网红", "美食", "推荐", "好吃", "绝了",
    "这家", "那家", "太好吃", "真的绝", "yyds", "天花板", "封神",
    "宝藏", "小众", "排队", "人均", "性价比", "氛围感", "出片",
    "约会", "聚餐", "一人食", "深夜食堂", "夜宵", "早餐", "午餐", "晚餐",
    "周末", "假期", "节日", "生日", "纪念日",
    "vlog", "日常", "记录", "分享", "合集", "攻略", "指南",
}

# 品类泛词（单独出现时剔除，如"楠火锅"中"火锅"作为后缀保留）
CATEGORY_WORDS = {
    "火锅", "奶茶", "面馆", "烧烤", "串串", "麻辣烫", "冒菜",
    "咖啡", "甜品", "蛋糕", "面包", "烘焙", "西餐", "日料",
    "韩餐", "粤菜", "川菜", "湘菜", "东北菜", "海鲜", "小吃",
    "快餐", "自助餐", "烤肉", "烤鱼", "烤鸭", "炸鸡", "汉堡",
    "披萨", "寿司", "拉面", "米粉", "饺子", "包子", "粥",
    "茶饮", "酒吧", "清吧", "餐厅", "饭店", "食堂",
}

# 城市泛词（单独出现时剔除）
CITY_WORDS = {
    "北京", "天津", "上海", "重庆", "广州", "深圳", "成都",
    "杭州", "南京", "武汉", "长沙", "西安", "苏州", "厦门",
    "青岛", "大连", "宁波", "无锡", "佛山", "东莞", "珠海",
    "福州", "合肥", "济南", "郑州", "昆明", "贵阳", "南宁",
    "海口", "三亚", "哈尔滨", "长春", "沈阳", "太原", "兰州",
    "石家庄", "南昌", "温州", "常州", "徐州", "烟台",
}

# 赞助商/品牌合作常见标签关键词
SPONSOR_KEYWORDS = {"华商", "中国华商", "赞助", "广告", "合作", "品牌"}


def _is_stop_word(text: str) -> bool:
    """判断文本是否为停用词（单独出现时）"""
    clean = text.strip()
    return (
        clean in STOP_WORDS
        or clean in CATEGORY_WORDS
        or clean in CITY_WORDS
        or clean in SPONSOR_KEYWORDS
    )


def _clean_candidate(text: str) -> str:
    """清理候选店铺名：去掉多余符号、空格"""
    # 去掉常见无意义前缀
    text = re.sub(r'^[#@＃＠]+', '', text)
    # 去掉表情符号（常见 Unicode 范围）
    text = re.sub(r'[\U0001F600-\U0001F64F\U0001F300-\U0001F5FF\U0001F680-\U0001F6FF\U0001F1E0-\U0001F1FF\U00002702-\U000027B0\U0000FE00-\U0000FE0F\U0001F900-\U0001F9FF\U0001FA00-\U0001FA6F\U0001FA70-\U0001FAFF]', '', text)
    # 合并空格
    text = re.sub(r'\s+', '', text).strip()
    return text


def _is_valid_candidate(name: str, author_name: str = "") -> bool:
    """
    判断候选名是否有效：
    - 长度 2~20 字
    - 不是纯停用词
    - 不是博主昵称
    - 不是纯数字/符号
    """
    if not name or len(name) < 2 or len(name) > 20:
        return False
    if _is_stop_word(name):
        return False
    # 剔除博主昵称（完全匹配或包含关系）
    if author_name and (name == author_name or name in author_name or author_name in name):
        return False
    # 纯数字/符号
    if re.match(r'^[\d\s\W]+$', name):
        return False
    return True


# ─────────────────────────────────────────
# 提取规则
# ─────────────────────────────────────────

def _extract_from_poi(poi_info: dict | None) -> list[dict]:
    """规则1：抖音 POI 直取（最高优先级）"""
    if not poi_info:
        return []
    # 尝试多种可能的字段名
    poi_name = (
        poi_info.get("poi_name", "")
        or poi_info.get("name", "")
        or poi_info.get("poi_biz_name", "")
    )
    if poi_name and len(poi_name) >= 2:
        return [{"name": poi_name.strip(), "source": "douyin_poi", "score": 100}]
    return []


def _extract_from_brackets(title: str) -> list[dict]:
    """规则2：标题中括号包裹的内容"""
    candidates = []
    # 匹配各种括号：【】「」《》""''
    patterns = [
        r'【([^】]+)】',
        r'「([^」]+)」',
        r'《([^》]+)》',
        r'\u201c([^\u201d]+)\u201d',
        r'"([^"]+)"',
        r'\u2018([^\u2019]+)\u2019',
    ]
    for pattern in patterns:
        matches = re.findall(pattern, title)
        for match in matches:
            clean = _clean_candidate(match)
            if clean and len(clean) >= 2 and len(clean) <= 20:
                candidates.append({"name": clean, "source": "title_bracket", "score": 90})
    return candidates


def _extract_from_patterns(text: str, source_prefix: str = "title") -> list[dict]:
    """规则3：探店模式匹配（打卡xxx、推荐xxx 等）"""
    candidates = []
    # 探店模式正则
    patterns = [
        (r'打卡[了]?(.{2,12})', 85),
        (r'推荐[了]?(.{2,12})', 85),
        (r'探店[了]?(.{2,12})', 85),
        (r'发现一家(.{2,12})', 85),
        (r'安利[了]?(.{2,12})', 80),
        (r'种草[了]?(.{2,12})', 80),
        (r'(.{2,10})[,，]?[我]?来了', 75),
        (r'(.{2,10})探店', 80),
        (r'(.{2,10})打卡', 80),
    ]
    for pattern, score in patterns:
        matches = re.findall(pattern, text)
        for match in matches:
            clean = _clean_candidate(match)
            # 去掉末尾的标点和泛词
            clean = re.sub(r'[,，。！!？?~～…]+$', '', clean)
            if clean and len(clean) >= 2:
                candidates.append({"name": clean, "source": f"{source_prefix}_pattern", "score": score})
    return candidates


def _extract_from_hashtags(hashtags: list[str], author_name: str = "") -> list[dict]:
    """规则5：话题标签中的专有名词"""
    candidates = []
    for tag in hashtags:
        tag = tag.strip()
        if not tag:
            continue
        # 跳过明显的泛词标签
        if _is_stop_word(tag):
            continue
        # 跳过包含城市+泛词的组合标签（如"上海探店""成都美食"）
        is_city_combo = False
        for city in CITY_WORDS:
            if tag.startswith(city):
                rest = tag[len(city):]
                if rest in STOP_WORDS or rest in CATEGORY_WORDS or not rest:
                    is_city_combo = True
                    break
        if is_city_combo:
            continue
        # 跳过赞助商标签
        if any(kw in tag for kw in SPONSOR_KEYWORDS):
            continue
        # 跳过博主昵称
        if author_name and (tag == author_name or tag in author_name):
            continue
        # 跳过纯城市名
        if tag in CITY_WORDS:
            continue
        # 跳过过长的标签（通常是描述性的）
        if len(tag) > 15:
            continue
        # 保留：可能是店铺名的标签
        if len(tag) >= 2:
            candidates.append({"name": tag, "source": "hashtag", "score": 70})
    return candidates


def _extract_from_comments_frequency(comments: list[dict], author_name: str = "") -> list[dict]:
    """
    规则6：评论中高频出现的专有名词。
    统计高赞评论（≥20赞）中出现的疑似店铺名，≥2次出现的作为候选。
    """
    if not comments:
        return []

    # 只看高赞评论
    high_digg_comments = [c for c in comments if c.get("digg_count", 0) >= 20]
    if len(high_digg_comments) < 2:
        # 高赞评论不足，放宽到 ≥5 赞
        high_digg_comments = [c for c in comments if c.get("digg_count", 0) >= 5]

    if len(high_digg_comments) < 2:
        return []

    # 从评论中提取疑似店铺名（括号包裹 + 探店模式）
    name_counter = Counter()
    for c in high_digg_comments:
        text = c.get("text", "")
        # 括号包裹
        for pattern in [r'【([^】]+)】', r'「([^」]+)」', r'"([^"]+)"']:
            for match in re.findall(pattern, text):
                clean = _clean_candidate(match)
                if _is_valid_candidate(clean, author_name):
                    name_counter[clean] += 1
        # 直接提到的店名模式（"xxx店"、"xxx馆"等）
        for match in re.findall(r'([\u4e00-\u9fff]{2,8}(?:店|馆|堂|坊|记|号|轩|阁|楼|居|苑))', text):
            clean = _clean_candidate(match)
            if _is_valid_candidate(clean, author_name):
                name_counter[clean] += 1

    candidates = []
    for name, count in name_counter.items():
        if count >= 2:
            candidates.append({"name": name, "source": "comment_frequency", "score": 75, "count": count})

    return candidates


def _extract_from_author_liked(author_liked_comments: list[dict], author_name: str = "") -> list[dict]:
    """规则4：博主点赞评论中的店名"""
    candidates = []
    for c in author_liked_comments:
        text = c.get("text", "")
        # 括号包裹
        for cand in _extract_from_brackets(text):
            cand["source"] = "author_liked_bracket"
            cand["score"] = 85
            candidates.append(cand)
        # 探店模式
        for cand in _extract_from_patterns(text, "author_liked"):
            cand["score"] = 85
            candidates.append(cand)
        # "xxx店"模式
        for match in re.findall(r'([\u4e00-\u9fff]{2,8}(?:店|馆|堂|坊|记|号|轩|阁|楼|居|苑))', text):
            clean = _clean_candidate(match)
            if _is_valid_candidate(clean, author_name):
                candidates.append({"name": clean, "source": "author_liked_pattern", "score": 85})
    return candidates


# ─────────────────────────────────────────
# 主入口
# ─────────────────────────────────────────

def extract_candidates(
    title: str,
    hashtags: list[str],
    author_name: str,
    author_liked_comments: list[dict],
    all_comments: list[dict],
    poi_info: dict | None = None,
    hot_search_keywords: list[str] = None,
) -> list[dict]:
    """
    从所有文本源中用正则/规则提取候选店铺名（零 API 成本）。

    返回格式：[{"name": "xxx", "source": "title_bracket", "score": 90}, ...]
    按 score 降序排列，已去重。
    """
    all_candidates = []

    # 0. 抖音热搜词（非常强的信号，通常就是店铺名）
    if hot_search_keywords:
        for kw in hot_search_keywords:
            kw = kw.strip()
            if kw and len(kw) >= 2 and not _is_stop_word(kw):
                all_candidates.append({"name": kw, "source": "hot_search_keyword", "score": 92})

    # 1. 抖音 POI（最高优先级）
    all_candidates.extend(_extract_from_poi(poi_info))

    # 2. 标题括号包裹
    all_candidates.extend(_extract_from_brackets(title))

    # 3. 标题探店模式
    all_candidates.extend(_extract_from_patterns(title, "title"))

    # 4. 博主点赞评论
    all_candidates.extend(_extract_from_author_liked(author_liked_comments, author_name))

    # 5. 话题标签
    all_candidates.extend(_extract_from_hashtags(hashtags, author_name))

    # 6. 评论高频词
    all_candidates.extend(_extract_from_comments_frequency(all_comments, author_name))

    # 去噪 + 验证
    valid_candidates = []
    seen_names = set()
    for cand in all_candidates:
        name = cand["name"]
        if not _is_valid_candidate(name, author_name):
            continue
        # 去重（同名取最高分）
        name_lower = name.lower().strip()
        if name_lower in seen_names:
            # 更新已有候选的分数（取最高）
            for existing in valid_candidates:
                if existing["name"].lower().strip() == name_lower:
                    if cand["score"] > existing["score"]:
                        existing["score"] = cand["score"]
                        existing["source"] = cand["source"]
                    break
            continue
        seen_names.add(name_lower)
        valid_candidates.append(cand)

    # 按 score 降序排列
    valid_candidates.sort(key=lambda x: x["score"], reverse=True)

    if valid_candidates:
        print(f"[规则预提取] 提取到 {len(valid_candidates)} 个候选: "
              + ", ".join(f"{c['name']}({c['source']}/{c['score']})" for c in valid_candidates[:5]))
    else:
        print("[规则预提取] 未提取到候选")

    return valid_candidates
