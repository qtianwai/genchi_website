# 高德地图模块
# 负责根据店铺名称+城市，通过高德地图 API 搜索获取精确地址和经纬度坐标

import os
import re
import math
import asyncio
import httpx
from dotenv import load_dotenv

load_dotenv()

AMAP_API_KEY = os.getenv("AMAP_API_KEY")
AMAP_SEARCH_URL = "https://restapi.amap.com/v3/place/text"


def _name_similarity(query: str, result: str) -> float:
    """
    计算搜索词与高德返回店名的相似度（0~1）。
    策略：
    1. 完全包含 → 1.0
    2. 去掉分店信息后包含 → 0.9
    3. 搜索词可拆分为多个片段时，计算片段命中率（解决"马场老火锅金桥"排序问题）
    4. 兜底：字符级重叠率
    """
    query = query.strip().lower()
    result = result.strip().lower()

    if not query or not result:
        return 0.0

    # 完全包含：query 是 result 的子串，或 result 是 query 的子串
    if query in result or result in query:
        return 1.0

    # 去掉括号内的分店信息后再比较（如"最山城（人民广场店）" → "最山城"）
    query_core = re.sub(r'[（(][^）)]*[）)]', '', query).strip()
    result_core = re.sub(r'[（(][^）)]*[）)]', '', result).strip()
    if query_core and (query_core in result_core or result_core in query_core):
        return 0.9

    # 片段命中率：将搜索词拆分为连续片段，检查每个片段是否出现在结果中
    # 例如搜"马场老火锅金桥"，拆分为可能的子片段，检查"金桥"是否在结果中
    # 这样包含"金桥"的结果会比不包含的得分更高
    result_full = result_core or result
    query_full = query_core or query
    if len(query_full) >= 4:
        # 尝试用滑动窗口找出搜索词中所有长度>=2的子串在结果中的命中情况
        # 简化方案：把搜索词按2字符窗口切片，计算命中率
        bigrams = [query_full[i:i+2] for i in range(len(query_full) - 1)]
        if bigrams:
            hits = sum(1 for bg in bigrams if bg in result_full)
            bigram_score = hits / len(bigrams)
            # bigram 命中率映射到 0.3~0.85 区间（避免与包含匹配的 0.9/1.0 冲突）
            score = 0.3 + bigram_score * 0.55
            # 同时计算字符重叠率作为补充
            query_chars = set(query_full)
            result_chars = set(result_full)
            char_overlap = len(query_chars & result_chars) / len(query_chars) if query_chars else 0
            # 取两者较高值
            return max(score, char_overlap)

    # 字符级重叠率（用于处理简称/全称差异）
    query_chars = set(query_core or query)
    result_chars = set(result_core or result)
    if not query_chars:
        return 0.0
    overlap = len(query_chars & result_chars) / len(query_chars)
    return overlap


async def _search_amap(
    keywords: str,
    city: str,
    offset: int = 20,
    page: int = 1
) -> list[dict]:
    """
    调用高德 POI 搜索接口，返回原始 POI 列表。
    city 为空时不传城市参数（全国搜索）。
    """
    params = {
        "key": AMAP_API_KEY,
        "keywords": keywords,
        "types": "050000",  # 050000 = 餐饮服务类别
        "output": "json",
        "offset": offset,
        "page": page,
        "extensions": "all",   # all 模式可返回人均消费(biz_ext.cost)和图片(photos)
    }
    # 城市有效时才加城市限制（"未知"/"" 不传，避免搜索范围错误）
    if city and city not in ("未知", "unknown"):
        params["city"] = city

    async with httpx.AsyncClient(timeout=10) as client:
        try:
            resp = await client.get(AMAP_SEARCH_URL, params=params)
            data = resp.json()
            if data.get("status") != "1":
                print(f"[高德搜索] 接口返回错误: {data.get('info')}")
                return []
            return data.get("pois", []) or []
        except Exception as e:
            print(f"[高德搜索] 请求失败: keywords={keywords}, city={city}, page={page}, error={type(e).__name__}: {e}")
            return []


async def _search_amap_pages(
    keywords: str,
    city: str,
    offset: int = 20,
    max_pages: int = 3
) -> list[dict]:
    """
    连续拉取多页高德文本搜索结果。
    用于候选列表搜索，尽量避免热门连锁店因第一页截断而找不到目标分店。
    """
    all_pois: list[dict] = []

    for page in range(1, max_pages + 1):
        pois = await _search_amap(keywords, city, offset=offset, page=page)
        if not pois:
            break

        all_pois.extend(pois)

        # 高德返回数量不足一页时，说明已经到底。
        if len(pois) < offset:
            break

    return all_pois


def _parse_poi(poi: dict, city: str) -> dict | None:
    """将高德 POI 对象解析为标准格式，坐标无效时返回 None。"""
    location = poi.get("location", "")
    if "," not in location:
        return None
    lng, lat = location.split(",", 1)
    try:
        # 提取人均消费（extensions=all 时 biz_ext.cost 有值，单位：元）
        # 注意：高德 API 已将字段名从 avgprice 改为 cost，此处兼容两种格式
        biz_ext = poi.get("biz_ext", {}) or {}
        avg_price_raw = biz_ext.get("cost", "") or biz_ext.get("avgprice", "")
        # cost 字段可能带小数（如 "101.00"），取整数部分
        try:
            avg_price = int(float(avg_price_raw)) if avg_price_raw else None
        except (ValueError, TypeError):
            avg_price = None

        # 提取第一张图片 URL（extensions=all 时 photos 为列表）
        photos = poi.get("photos", []) or []
        photo_url = photos[0].get("url", "") if photos else ""

        return {
            "name": poi.get("name", ""),
            "address": poi.get("address", ""),
            "latitude": float(lat),
            "longitude": float(lng),
            "amap_id": poi.get("id", ""),
            "city": poi.get("cityname", city) or city,
            "avg_price": avg_price,       # 人均消费（元），无数据时为 None
            "photo_url": photo_url,       # 店铺封面图 URL，无数据时为空字符串
            "tel": poi.get("tel", ""),    # 商家联系电话，无数据时为空字符串
        }
    except ValueError:
        return None


async def search_nearby_restaurants(lat: float, lng: float, radius: int = 3000, limit: int = 20) -> list[dict]:
    """
    搜索附近餐饮 POI（v8.0 新增，用于推荐池补充）。
    使用高德周边搜索 API（/v3/place/around）。
    返回标准格式的店铺列表。
    """
    url = "https://restapi.amap.com/v3/place/around"
    params = {
        "key": AMAP_API_KEY,
        "location": f"{lng},{lat}",  # 高德格式：经度,纬度
        "types": "050000",           # 餐饮服务
        "radius": radius,
        "offset": limit,
        "page": 1,
        "extensions": "all",
        "sortrule": "weight",        # 按综合排序
    }
    async with httpx.AsyncClient(timeout=10) as client:
        try:
            resp = await client.get(url, params=params)
            data = resp.json()
            if data.get("status") != "1":
                print(f"[高德周边搜索] 接口返回错误: {data.get('info')}")
                return []
            pois = data.get("pois", []) or []
            results = []
            for poi in pois:
                parsed = _parse_poi(poi, "")
                if parsed:
                    # 补充品类信息（高德 typecode 转可读分类）
                    type_name = poi.get("type", "")
                    if type_name:
                        # 取最后一级分类（如"餐饮服务;中餐厅;川菜" → "川菜"）
                        parts = type_name.split(";")
                        parsed["category"] = parts[-1] if parts else ""
                    results.append(parsed)
            return results
        except Exception as e:
            print(f"[高德周边搜索] 请求失败: {e}")
            return []


def _distance_meters(
    from_lat: float,
    from_lng: float,
    to_lat: float,
    to_lng: float,
) -> float:
    """使用 haversine 公式计算两点间直线距离（米）。"""
    earth_radius = 6371000

    lat1 = math.radians(from_lat)
    lat2 = math.radians(to_lat)
    delta_lat = math.radians(to_lat - from_lat)
    delta_lng = math.radians(to_lng - from_lng)

    a = (
        math.sin(delta_lat / 2) ** 2 +
        math.cos(lat1) * math.cos(lat2) * math.sin(delta_lng / 2) ** 2
    )
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    return earth_radius * c


async def search_restaurant(name: str, city: str) -> dict | None:
    """
    通过高德地图 POI 搜索接口，根据店铺名称和城市查找店铺详情。

    搜索策略（三级回退）：
    1. 精确名称 + 城市 → 取相似度最高的结果（≥0.5 才采用）
    2. 若失败：截断分店信息后的核心名称 + 城市
    3. 若失败：核心名称 + 不限城市（全国搜索）

    输入：
    - name: 店铺名称（如"最山城不改良重庆火锅（人民广场店）"）
    - city: 城市（如"上海"，"未知"时不限城市）

    输出：{name, address, latitude, longitude, amap_id, city} 或 None
    """
    # 提取核心名称（去掉括号内的分店信息）
    core_name = re.sub(r'[（(][^）)]*[）)]', '', name).strip()

    # ── 第一级：精确名称 + 城市 ──
    pois = await _search_amap(name, city, offset=20)
    best = _pick_best_poi(pois, name, city)
    if best:
        print(f"[高德搜索] 精确匹配成功: {name} → {best['name']} ({best['city']})")
        return best

    # ── 第二级：核心名称（去分店）+ 城市 ──
    if core_name and core_name != name:
        pois = await _search_amap(core_name, city, offset=20)
        best = _pick_best_poi(pois, core_name, city)
        if best:
            print(f"[高德搜索] 核心名称匹配成功: {core_name} → {best['name']} ({best['city']})")
            return best

    # ── 第三级：核心名称 + 不限城市 ──
    if city and city not in ("未知", "unknown", ""):
        pois = await _search_amap(core_name or name, "", offset=20)
        best = _pick_best_poi(pois, core_name or name, city, strict=False)
        if best:
            print(f"[高德搜索] 全国搜索匹配成功: {core_name or name} → {best['name']} ({best['city']})")
            return best

    print(f"[高德搜索] 三级搜索均未找到: {name} ({city})")
    return None


def _pick_best_poi(pois: list[dict], query: str, city: str, strict: bool = True) -> dict | None:
    """
    从高德返回的 POI 列表中挑选最匹配的结果。

    - strict=True：相似度阈值 0.4（有城市限制时使用，v10.0 从 0.5 放宽）
    - strict=False：相似度阈值 0.25（全国搜索时适当放宽，v10.0 从 0.3 放宽）
    v10.0 放宽原因：允许牺牲一点准确率来提升召回率，后续有人工复核兜底
    """
    threshold = 0.4 if strict else 0.25
    best_poi = None
    best_score = 0.0

    for poi in pois:
        parsed = _parse_poi(poi, city)
        if not parsed:
            continue
        score = _name_similarity(query, parsed["name"])
        if score > best_score:
            best_score = score
            best_poi = parsed

    if best_poi and best_score >= threshold:
        return best_poi

    # 相似度不足但只有一条结果时，记录警告（不采用）
    if pois and best_score < threshold:
        first = _parse_poi(pois[0], city)
        if first:
            print(f"[高德搜索] 相似度过低({best_score:.2f})，丢弃结果: 查询={query}, 返回={first['name']}")
    return None


# ─────────────────────────────────────────
# 高德分类 → 系统分类映射（复核功能使用）
# ─────────────────────────────────────────

# 高德 POI type 字段格式示例："餐饮服务;火锅店;火锅店"
# 映射规则：按关键词匹配，优先匹配更具体的分类
AMAP_CATEGORY_MAP = {
    "火锅": "火锅",
    "烤肉": "烤肉",
    "烧烤": "烧烤",
    "串串": "串串",
    "麻辣烫": "麻辣烫",
    "冒菜": "冒菜",
    "烤鱼": "烤鱼",
    "烤鸭": "烤鸭",
    "烤鸡": "烤鸡",
    "炸鸡": "炸鸡",
    "汉堡": "汉堡",
    "披萨": "披萨",
    "意大利": "西餐",
    "西餐": "西餐",
    "牛排": "西餐",
    "日本料理": "日料",
    "日料": "日料",
    "寿司": "日料",
    "拉面": "日料",
    "韩国料理": "韩餐",
    "韩餐": "韩餐",
    "泰国料理": "东南亚菜",
    "东南亚": "东南亚菜",
    "越南": "东南亚菜",
    "粤菜": "粤菜",
    "广东": "粤菜",
    "川菜": "川菜",
    "四川": "川菜",
    "湘菜": "湘菜",
    "湖南": "湘菜",
    "江浙菜": "江浙菜",
    "淮扬": "江浙菜",
    "东北菜": "东北菜",
    "云南": "云南菜",
    "贵州": "贵州菜",
    "新疆": "新疆菜",
    "清真": "清真",
    "面条": "面食",
    "面馆": "面食",
    "米粉": "米粉",
    "粉": "米粉",
    "饺子": "饺子",
    "包子": "包子",
    "粥": "粥",
    "小吃": "小吃",
    "快餐": "快餐",
    "自助": "自助餐",
    "海鲜": "海鲜",
    "龙虾": "海鲜",
    "螃蟹": "海鲜",
    "咖啡": "咖啡",
    "茶": "茶饮",
    "奶茶": "茶饮",
    "甜品": "甜品",
    "蛋糕": "甜品",
    "冰淇淋": "甜品",
    "面包": "烘焙",
    "烘焙": "烘焙",
}


def map_amap_category(amap_type: str) -> str:
    """
    将高德 POI type 字段映射为系统简短分类标签。
    amap_type 示例："餐饮服务;火锅店;火锅店"
    返回示例："火锅"，无匹配时返回二级分类或"餐饮"
    """
    if not amap_type:
        return "餐饮"

    # 按关键词匹配（优先匹配更具体的词）
    for keyword, category in AMAP_CATEGORY_MAP.items():
        if keyword in amap_type:
            return category

    # 无匹配时取二级分类（如"餐饮服务;火锅店;火锅店" → "火锅店"）
    parts = amap_type.split(";")
    if len(parts) >= 2:
        return parts[1]

    return "餐饮"


async def search_restaurant_for_review(
    name: str,
    city: str,
    user_lat: float | None = None,
    user_lng: float | None = None,
    max_results: int = 50,
) -> list[dict]:
    """
    复核功能专用：搜索店铺候选列表，返回最多 10 条结果。
    每条结果附加 category_raw（高德原始分类）和 category_mapped（映射后分类）。

    与 search_restaurant 的区别：
    - 返回多条候选供管理员选择，而非自动挑选最佳结果
    - 不做相似度过滤，让管理员自行判断
    - 每条结果包含分类信息
    """
    # --- 构建多关键词搜索策略 ---
    # 1. 原始名称
    # 2. 去掉括号分店信息的核心名称
    core_name = re.sub(r'[（(][^）)]*[）)]', '', name).strip()
    primary_keywords = [name.strip()]
    if core_name and core_name not in primary_keywords:
        primary_keywords.append(core_name)

    deduped_pois: dict[str, dict] = {}
    for keyword in primary_keywords:
        pois = await _search_amap_pages(keyword, city, offset=20, max_pages=3)
        for poi in pois:
            poi_id = poi.get("id", "")
            if poi_id and poi_id not in deduped_pois:
                deduped_pois[poi_id] = poi

    # 3. 补充搜索：如果初始结果太少（<5条），可能是用户输入不完整
    #    例如"马场老火"实际想搜"马场老火锅"，补充常见餐饮后缀再搜
    #    只在结果不足时触发，避免浪费 API 调用
    #    要求搜索词 ≥3 字符（2字词如"马厂"加后缀无意义）
    #    并发执行所有后缀搜索，避免串行导致总耗时过长
    _COMMON_SUFFIXES = ["锅", "店", "馆", "堂", "坊"]
    search_term = core_name or name.strip()
    if len(deduped_pois) < 5 and 3 <= len(search_term) <= 6:
        expand_keywords = [
            search_term + suffix
            for suffix in _COMMON_SUFFIXES
            if search_term + suffix not in primary_keywords
        ]
        if expand_keywords:
            # 并发搜索所有后缀关键词（每个只拉1页，控制总请求量）
            tasks = [
                _search_amap_pages(kw, city, offset=20, max_pages=1)
                for kw in expand_keywords
            ]
            results = await asyncio.gather(*tasks, return_exceptions=True)
            for result in results:
                if isinstance(result, Exception):
                    print(f"[高德补充搜索] 并发请求异常: {result}")
                    continue
                for poi in result:
                    poi_id = poi.get("id", "")
                    if poi_id and poi_id not in deduped_pois:
                        deduped_pois[poi_id] = poi

    candidates = []
    for poi in deduped_pois.values():
        # 复用 _parse_poi() 提取基础字段（name/address/lat/lng/amap_id/city/avg_price/photo_url/tel）
        parsed = _parse_poi(poi, city)
        if parsed is None:
            continue

        amap_type = poi.get("type", "")
        similarity = _name_similarity(name, parsed["name"])
        distance_meters = None
        if user_lat is not None and user_lng is not None:
            distance_meters = round(
                _distance_meters(user_lat, user_lng, parsed["latitude"], parsed["longitude"]),
                1
            )

        candidates.append({
            **parsed,                                    # 基础字段（含 tel）
            "category_raw": amap_type,                   # 高德原始分类
            "category_mapped": map_amap_category(amap_type),  # 映射后分类
            "distance_meters": distance_meters,
            "_similarity": similarity,
        })

    def _sort_key(candidate: dict) -> tuple:
        similarity = candidate.get("_similarity", 0.0)
        # 先保证名称足够接近，再在同层里按距离由近到远。
        if similarity >= 0.95:
            similarity_bucket = 0
        elif similarity >= 0.75:
            similarity_bucket = 1
        elif similarity >= 0.5:
            similarity_bucket = 2
        else:
            similarity_bucket = 3

        distance = candidate.get("distance_meters")
        distance_sort = distance if distance is not None else float("inf")
        return (similarity_bucket, distance_sort, -similarity, candidate.get("name", ""))

    candidates.sort(key=_sort_key)

    cleaned_results = []
    for candidate in candidates[:max_results]:
        candidate.pop("_similarity", None)
        cleaned_results.append(candidate)

    return cleaned_results


async def get_poi_detail(amap_id: str) -> dict | None:
    """
    通过高德 POI 详情接口，根据 amap_id 直接查询店铺详情（含均价和图片）。
    比重新搜索更精准，用于回填已入库店铺的 avg_price 和 photo_url。
    """
    params = {
        "key": AMAP_API_KEY,
        "id": amap_id,
        "extensions": "all",
    }
    async with httpx.AsyncClient(timeout=10) as client:
        try:
            resp = await client.get("https://restapi.amap.com/v3/place/detail", params=params)
            data = resp.json()
            if data.get("status") != "1":
                print(f"[高德详情] 接口返回错误: {data.get('info')}")
                return None
            pois = data.get("pois", []) or []
            if not pois:
                return None
            poi = pois[0]
            biz_ext = poi.get("biz_ext", {}) or {}
            avg_price_raw = biz_ext.get("cost", "") or biz_ext.get("avgprice", "")
            try:
                avg_price = int(float(avg_price_raw)) if avg_price_raw else None
            except (ValueError, TypeError):
                avg_price = None
            photos = poi.get("photos", []) or []
            photo_url = photos[0].get("url", "") if photos else ""
            return {"avg_price": avg_price, "photo_url": photo_url, "tel": poi.get("tel", "")}
        except Exception as e:
            print(f"[高德详情] 请求失败: {e}")
            return None


async def batch_search_restaurants(restaurants: list[dict]) -> list[dict]:
    """
    批量搜索店铺地址
    输入：AI 提取的店铺列表 [{"name": ..., "city": ..., "category": ...}]
    输出：补充了地址和坐标的店铺列表
    """
    import asyncio

    async def search_one(r: dict) -> dict | None:
        result = await search_restaurant(r["name"], r.get("city", ""))
        if result:
            # 合并 AI 提取的分类信息
            result["category"] = r.get("category", "")
            result["confidence"] = r.get("confidence", "medium")
            return result
        return None

    # 并发搜索所有店铺
    tasks = [search_one(r) for r in restaurants]
    results = await asyncio.gather(*tasks)

    # 过滤掉未找到的结果
    return [r for r in results if r is not None]
