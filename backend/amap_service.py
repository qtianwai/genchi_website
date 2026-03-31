# 高德地图模块
# 负责根据店铺名称+城市，通过高德地图 API 搜索获取精确地址和经纬度坐标

import os
import httpx
from dotenv import load_dotenv

load_dotenv()

AMAP_API_KEY = os.getenv("AMAP_API_KEY")
AMAP_SEARCH_URL = "https://restapi.amap.com/v3/place/text"


async def search_restaurant(name: str, city: str) -> dict | None:
    """
    通过高德地图 POI 搜索接口，根据店铺名称和城市查找店铺详情

    输入：
    - name: 店铺名称（如"老四川火锅"）
    - city: 城市（如"成都"）

    输出：{
        name: 店铺名称,
        address: 详细地址,
        latitude: 纬度,
        longitude: 经度,
        amap_id: 高德 POI ID（唯一标识）
    } 或 None（未找到）
    """
    params = {
        "key": AMAP_API_KEY,
        "keywords": name,
        "city": city,
        "types": "050000",  # 050000 = 餐饮服务类别
        "output": "json",
        "offset": 1,        # 只取第一条最相关结果
        "page": 1,
        "extensions": "base",
    }

    async with httpx.AsyncClient(timeout=10) as client:
        try:
            resp = await client.get(AMAP_SEARCH_URL, params=params)
            data = resp.json()

            # 高德返回 status=1 表示成功
            if data.get("status") != "1":
                print(f"[高德搜索] 接口返回错误: {data.get('info')}")
                return None

            pois = data.get("pois", [])
            if not pois:
                print(f"[高德搜索] 未找到店铺: {name} ({city})")
                return None

            poi = pois[0]

            # 高德返回的经纬度格式是 "经度,纬度"（注意顺序）
            location = poi.get("location", "")
            if "," in location:
                lng, lat = location.split(",")
            else:
                return None

            return {
                "name": poi.get("name", name),
                "address": poi.get("address", ""),
                "latitude": float(lat),
                "longitude": float(lng),
                "amap_id": poi.get("id", ""),
                "city": city,
            }

        except Exception as e:
            print(f"[高德搜索] 请求失败: {e}")
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
