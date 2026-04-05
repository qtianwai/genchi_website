# 天气服务模块（v8.0 新增）
# 接入和风天气 API，为 AI 推荐提供天气上下文
# 免费版每日 1000 次调用，后端做 30 分钟缓存

import os
import time
import httpx
from dotenv import load_dotenv

load_dotenv()

# 和风天气 API Key（免费开发版）
QWEATHER_API_KEY = os.getenv("QWEATHER_API_KEY", "")
# 免费版用 devapi，商业版用 api
QWEATHER_BASE_URL = os.getenv("QWEATHER_BASE_URL", "https://devapi.qweather.com")

# 内存缓存：{cache_key: (timestamp, data)}
# cache_key = "lat_lng" 四舍五入到小数点后 1 位（约 11km 精度，同城共享缓存）
_weather_cache: dict[str, tuple[float, dict]] = {}
CACHE_TTL = 1800  # 30 分钟


def _round_location(lat: float, lng: float) -> str:
    """将经纬度四舍五入到 1 位小数，作为缓存 key"""
    return f"{round(lat, 1)}_{round(lng, 1)}"


def _clean_expired_cache():
    """清理过期缓存条目"""
    now = time.time()
    expired_keys = [k for k, (ts, _) in _weather_cache.items() if now - ts > CACHE_TTL]
    for k in expired_keys:
        del _weather_cache[k]


async def get_weather(lat: float, lng: float) -> dict:
    """
    获取当前天气信息。
    返回格式：{
        "text": "晴",           # 天气状况文字（晴/多云/小雨/大雨/雪 等）
        "temp": "25",           # 温度（摄氏度）
        "icon": "100",          # 天气图标代码
        "wind_dir": "东南风",    # 风向
        "humidity": "65",       # 湿度百分比
        "precip": "0.0",        # 降水量 mm
        "category": "sunny"     # 简化分类：sunny/cloudy/rainy/snowy/hot/cold
    }
    若 API 调用失败，返回默认值（不影响推荐流程）。
    """
    # 检查缓存
    cache_key = _round_location(lat, lng)
    now = time.time()
    if cache_key in _weather_cache:
        ts, data = _weather_cache[cache_key]
        if now - ts < CACHE_TTL:
            return data

    # 定期清理过期缓存
    if len(_weather_cache) > 100:
        _clean_expired_cache()

    # 无 API Key 时返回默认值
    if not QWEATHER_API_KEY:
        return _default_weather()

    try:
        url = f"{QWEATHER_BASE_URL}/v7/weather/now"
        params = {
            "location": f"{lng},{lat}",  # 和风天气格式：经度,纬度
            "key": QWEATHER_API_KEY,
            "lang": "zh",
        }
        async with httpx.AsyncClient(timeout=5.0) as client:
            resp = await client.get(url, params=params)
            resp.raise_for_status()
            result = resp.json()

        if result.get("code") != "200":
            print(f"[天气API] 返回错误: code={result.get('code')}")
            return _default_weather()

        now_data = result.get("now", {})
        weather = {
            "text": now_data.get("text", "未知"),
            "temp": now_data.get("temp", "20"),
            "icon": now_data.get("icon", "999"),
            "wind_dir": now_data.get("windDir", ""),
            "humidity": now_data.get("humidity", "50"),
            "precip": now_data.get("precip", "0.0"),
            "category": _classify_weather(now_data),
        }

        # 写入缓存
        _weather_cache[cache_key] = (time.time(), weather)
        return weather

    except Exception as e:
        print(f"[天气API] 请求失败: {e}")
        return _default_weather()


def _classify_weather(now_data: dict) -> str:
    """
    将天气状况简化为推荐系统可用的分类。
    用于限定卡触发和推荐策略调整。
    """
    text = now_data.get("text", "")
    temp = int(now_data.get("temp", "20"))

    # 降水类
    if any(w in text for w in ["雨", "雷", "阵雨"]):
        return "rainy"
    if any(w in text for w in ["雪", "冰"]):
        return "snowy"

    # 温度类
    if temp >= 35:
        return "hot"
    if temp <= 5:
        return "cold"

    # 天气类
    if any(w in text for w in ["晴", "少云"]):
        return "sunny"
    if any(w in text for w in ["云", "阴"]):
        return "cloudy"

    return "normal"


def _default_weather() -> dict:
    """API 不可用时的默认天气（不影响推荐流程）"""
    return {
        "text": "未知",
        "temp": "20",
        "icon": "999",
        "wind_dir": "",
        "humidity": "50",
        "precip": "0.0",
        "category": "normal",
    }
