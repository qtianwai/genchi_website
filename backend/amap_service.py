# 高德地图模块
# 负责根据店铺名称+城市，通过高德地图 API 搜索获取精确地址和经纬度坐标

import os
import re
import httpx
from dotenv import load_dotenv

load_dotenv()

AMAP_API_KEY = os.getenv("AMAP_API_KEY")
AMAP_SEARCH_URL = "https://restapi.amap.com/v3/place/text"


def _name_similarity(query: str, result: str) -> float:
    """
    计算 AI 提取的店名与高德返回店名的相似度（0~1）。
    策略：检查 query 的核心词是否出现在 result 中。
    用于过滤高德返回的不相关结果（如搜"最山城"却返回"山城烤肉"）。
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

    # 字符级重叠率（用于处理简称/全称差异）
    query_chars = set(query_core or query)
    result_chars = set(result_core or result)
    if not query_chars:
        return 0.0
    overlap = len(query_chars & result_chars) / len(query_chars)
    return overlap


async def _search_amap(keywords: str, city: str, offset: int = 5) -> list[dict]:
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
        "page": 1,
        "extensions": "all",   # all 模式可返回人均消费(biz_ext.avgprice)和图片(photos)
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
            print(f"[高德搜索] 请求失败: {e}")
            return []


def _parse_poi(poi: dict, city: str) -> dict | None:
    """将高德 POI 对象解析为标准格式，坐标无效时返回 None。"""
    location = poi.get("location", "")
    if "," not in location:
        return None
    lng, lat = location.split(",", 1)
    try:
        # 提取人均消费（extensions=all 时 biz_ext.avgprice 有值，单位：元）
        biz_ext = poi.get("biz_ext", {}) or {}
        avg_price_raw = biz_ext.get("avgprice", "")
        avg_price = int(avg_price_raw) if avg_price_raw and avg_price_raw.isdigit() else None

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
        }
    except ValueError:
        return None


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
    pois = await _search_amap(name, city, offset=5)
    best = _pick_best_poi(pois, name, city)
    if best:
        print(f"[高德搜索] 精确匹配成功: {name} → {best['name']} ({best['city']})")
        return best

    # ── 第二级：核心名称（去分店）+ 城市 ──
    if core_name and core_name != name:
        pois = await _search_amap(core_name, city, offset=5)
        best = _pick_best_poi(pois, core_name, city)
        if best:
            print(f"[高德搜索] 核心名称匹配成功: {core_name} → {best['name']} ({best['city']})")
            return best

    # ── 第三级：核心名称 + 不限城市 ──
    if city and city not in ("未知", "unknown", ""):
        pois = await _search_amap(core_name or name, "", offset=5)
        best = _pick_best_poi(pois, core_name or name, city, strict=False)
        if best:
            print(f"[高德搜索] 全国搜索匹配成功: {core_name or name} → {best['name']} ({best['city']})")
            return best

    print(f"[高德搜索] 三级搜索均未找到: {name} ({city})")
    return None


def _pick_best_poi(pois: list[dict], query: str, city: str, strict: bool = True) -> dict | None:
    """
    从高德返回的 POI 列表中挑选最匹配的结果。

    - strict=True：相似度阈值 0.5（有城市限制时使用）
    - strict=False：相似度阈值 0.3（全国搜索时适当放宽）
    """
    threshold = 0.5 if strict else 0.3
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


async def search_restaurant_for_review(name: str, city: str) -> list[dict]:
    """
    复核功能专用：搜索店铺候选列表，返回最多 10 条结果。
    每条结果附加 category_raw（高德原始分类）和 category_mapped（映射后分类）。

    与 search_restaurant 的区别：
    - 返回多条候选供管理员选择，而非自动挑选最佳结果
    - 不做相似度过滤，让管理员自行判断
    - 每条结果包含分类信息
    """
    pois = await _search_amap(name, city, offset=10)

    candidates = []
    for poi in pois:
        location = poi.get("location", "")
        if "," not in location:
            continue
        lng, lat = location.split(",", 1)
        try:
            amap_type = poi.get("type", "")
            biz_ext = poi.get("biz_ext", {}) or {}
            avg_price_raw = biz_ext.get("avgprice", "")
            avg_price = int(avg_price_raw) if avg_price_raw and avg_price_raw.isdigit() else None
            photos = poi.get("photos", []) or []
            photo_url = photos[0].get("url", "") if photos else ""
            candidates.append({
                "amap_id": poi.get("id", ""),
                "name": poi.get("name", ""),
                "address": poi.get("address", ""),
                "city": poi.get("cityname", city) or city,
                "latitude": float(lat),
                "longitude": float(lng),
                "category_raw": amap_type,
                "category_mapped": map_amap_category(amap_type),
                "avg_price": avg_price,   # 人均消费（元）
                "photo_url": photo_url,   # 店铺封面图 URL
            })
        except ValueError:
            continue

    return candidates


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
            avg_price_raw = biz_ext.get("avgprice", "")
            avg_price = int(avg_price_raw) if avg_price_raw and avg_price_raw.isdigit() else None
            photos = poi.get("photos", []) or []
            photo_url = photos[0].get("url", "") if photos else ""
            return {"avg_price": avg_price, "photo_url": photo_url}
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
