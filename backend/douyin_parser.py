# 抖音链接解析模块
# 使用 JustOneAPI 稳定获取视频信息和博主视频列表
# 替代原来的自行爬取方案，解决反爬不稳定问题

import os
import re
import httpx
from typing import Optional

# JustOneAPI base URL 和 token
JUSTONEAPI_BASE = "https://api.justoneapi.com"
JUSTONEAPI_TOKEN = os.getenv("JUSTONEAPI_TOKEN", "2UJdMdkQiP4xaOIS")


def _get(path: str, params: dict) -> dict:
    """
    同步调用 JustOneAPI GET 接口。
    token 通过 query 参数传递，这是 JustOneAPI 的标准认证方式。
    """
    params["token"] = JUSTONEAPI_TOKEN
    # 过滤掉值为 None 的参数
    params = {k: v for k, v in params.items() if v is not None}
    with httpx.Client(timeout=30, follow_redirects=True) as client:
        resp = client.get(f"{JUSTONEAPI_BASE}{path}", params=params)
        return resp.json()


async def _aget(path: str, params: dict, max_retries: int = 2) -> dict:
    """
    异步调用 JustOneAPI GET 接口（供 async 函数使用）。
    自动重试 301/500/502/503/504 等临时错误，提升接口稳定性。
    """
    for attempt in range(max_retries + 1):
        params["token"] = JUSTONEAPI_TOKEN
        params = {k: v for k, v in params.items() if v is not None}
        try:
            async with httpx.AsyncClient(timeout=30, follow_redirects=True) as client:
                resp = await client.get(f"{JUSTONEAPI_BASE}{path}", params=params)
                result = resp.json()
            code = result.get("code", -1)
            # 301/500/502/503/504 表示临时错误，可以重试
            if code in (301, 500, 502, 503, 504) and attempt < max_retries:
                print(f"[JustOneAPI] 尝试 {attempt+1} 失败 (code={code})，重试中...")
                continue
            return result
        except Exception as e:
            if attempt < max_retries:
                print(f"[JustOneAPI] 网络错误 (attempt {attempt+1}): {e}，重试中...")
                continue
            raise


def extract_url_from_text(text: str) -> str:
    """
    从分享文字中提取抖音链接。
    用户粘贴的通常是整段分享文字，如：
    "5.82 复制打开抖音，看看【xxx】... https://v.douyin.com/xxx/ 04/09 ..."
    需要从中提取出 https:// 开头的链接。
    """
    match = re.search(r'https?://\S+', text)
    if match:
        # 去掉末尾可能粘连的标点符号
        url = match.group(0).rstrip('.,;:!?，。；：！？')
        return url
    return text.strip()


async def parse_douyin_link(url: str) -> dict:
    """
    主入口：解析抖音分享链接，返回视频信息（优化版：合并获取扩展信息）。

    三步流程：
    1. share-url-transfer/v1：将分享短链转换为 redirect_url，从中提取视频 ID
    2. get-video-detail/v2：获取完整视频信息、博主信息、扩展信息（话题标签、城市）
       （优化1：一次调用获取所有信息，避免重复调用）
    3. 提取评论中博主点赞的评论（用于 AI 识别店铺）

    输入：抖音分享链接或包含链接的分享文字
    输出：{
        video_id, title, author_id, author_name, author_avatar,
        author_sec_uid, hashtags, city_name, author_liked_comments,
        hot_comments, hot_comments_raw, all_comments
    }
    """
    # 第一步：从文本中提取纯链接（兼容用户粘贴整段分享文字的情况）
    share_url = extract_url_from_text(url)
    print(f"[抖音解析] 提取到链接: {share_url}")

    # 第二步：调用 share-url-transfer/v1，拿到 redirect_url
    result = await _aget("/api/douyin/share-url-transfer/v1", {"shareUrl": share_url})
    print(f"[抖音解析] share-url-transfer 返回 code={result.get('code')}")

    if result.get("code") != 0 or not result.get("data"):
        raise ValueError(f"JustOneAPI 解析失败: {result.get('message', '未知错误')} (code={result.get('code')})")

    # 从 redirect_url 中提取视频 ID
    # redirect_url 格式：https://www.iesdouyin.com/share/video/7621134274259171761/?...
    redirect_url = result["data"].get("redirect_url", "")
    # 匹配 /video/数字 格式（可能后面是 / 或 ? 或 &）
    match = re.search(r'/video/(\d+)', redirect_url)
    if not match:
        raise ValueError(f"无法从 redirect_url 提取视频 ID: {redirect_url}")
    video_id = match.group(1)
    print(f"[抖音解析] 提取到视频 ID: {video_id}")

    # 第三步：调用 get-video-detail/v2 获取完整信息（优化1：一次调用获取所有字段）
    detail_result = await _aget("/api/douyin/get-video-detail/v2", {"videoId": video_id})
    print(f"[抖音解析] get-video-detail 返回 code={detail_result.get('code')}")

    if detail_result.get("code") != 0 or not detail_result.get("data"):
        raise ValueError(f"获取视频详情失败: {detail_result.get('message', '未知错误')}")

    # 数据结构：data.aweme_detail
    aweme = detail_result["data"].get("aweme_detail", {})
    author = aweme.get("author", {})

    # 基础信息
    title = aweme.get("desc", "")
    author_id = str(author.get("uid", ""))
    author_name = author.get("nickname", "")
    author_sec_uid = author.get("sec_uid", "")
    # 头像取 url_list 第一个
    author_avatar = (
        author.get("avatar_thumb", {}).get("url_list", [""])[0]
        or author.get("avatar_medium", {}).get("url_list", [""])[0]
        or ""
    )

    # 扩展信息（优化1：直接从这次调用中提取，不再单独调用 fetch_video_detail_extra）
    # 从 text_extra 中提取话题标签（type=1 表示话题标签）
    text_extras = aweme.get("text_extra", []) or []
    hashtags = [
        t.get("hashtag_name", "")
        for t in text_extras
        if t.get("type") == 1 and t.get("hashtag_name")
    ]

    # 城市编码转中文
    city_code = str(aweme.get("city", ""))
    city_map = {
        # 直辖市
        "110000": "北京", "120000": "天津", "310000": "上海", "500000": "重庆",
        # 省会城市
        "130100": "石家庄", "140100": "太原", "150100": "呼和浩特", "210100": "沈阳",
        "220100": "长春", "230100": "哈尔滨", "320100": "南京", "330100": "杭州",
        "340100": "合肥", "350100": "福州", "360100": "南昌", "370100": "济南",
        "410100": "郑州", "420100": "武汉", "430100": "长沙", "440100": "广州",
        "450100": "南宁", "460100": "海口", "510100": "成都", "520100": "贵阳",
        "530100": "昆明", "540100": "拉萨", "610100": "西安", "620100": "兰州",
        "630100": "西宁", "640100": "银川", "650100": "乌鲁木齐",
        # 重点城市
        "440300": "深圳", "320500": "苏州", "330200": "宁波", "350200": "厦门",
        "370200": "青岛", "440400": "珠海", "440600": "佛山", "441300": "惠州",
        "441900": "东莞", "442000": "中山", "445100": "潮州", "445200": "揭阳",
        "510700": "绵阳", "511100": "乐山", "610200": "铜川", "610300": "宝鸡",
    }
    city_name_from_code = city_map.get(city_code, "未知" if not city_code or city_code == "0" else city_code)

    # 从标题和话题标签中提取城市（优先级高于 city_code）
    CITY_NAMES = [
        "北京", "天津", "上海", "重庆",
        "石家庄", "太原", "呼和浩特", "沈阳", "长春", "哈尔滨",
        "南京", "杭州", "合肥", "福州", "南昌", "济南",
        "郑州", "武汉", "长沙", "广州", "南宁", "海口",
        "成都", "贵阳", "昆明", "拉萨", "西安", "兰州",
        "西宁", "银川", "乌鲁木齐",
        "深圳", "苏州", "宁波", "厦门", "青岛", "珠海",
        "佛山", "惠州", "东莞", "中山", "潮州", "揭阳",
        "绵阳", "乐山", "宝鸡", "常州", "无锡", "温州",
        "嘉兴", "金华", "台州", "泉州", "漳州", "赣州",
        "烟台", "威海", "济宁", "临沂", "洛阳", "南阳",
        "宜昌", "襄阳", "株洲", "湘潭", "衡阳", "汕头",
        "江门", "湛江", "茂名", "肇庆", "清远", "梅州",
        "遵义", "大理", "丽江", "桂林", "柳州", "北海",
        "三亚", "海南", "西双版纳", "德宏",
        "大连", "鞍山", "抚顺", "本溪", "丹东",
        "哈尔滨", "齐齐哈尔", "牡丹江", "佳木斯",
        "包头", "鄂尔多斯", "呼伦贝尔",
        "唐山", "保定", "邯郸", "秦皇岛",
        "运城", "大同", "晋城",
        "徐州", "南通", "连云港", "淮安", "盐城", "扬州", "镇江", "泰州",
        "芜湖", "马鞍山", "安庆", "黄山",
        "郫县", "郫都",
    ]
    title_city = next((c for c in CITY_NAMES if c in title), None)
    tag_city = None
    if not title_city:
        for tag in hashtags:
            tag_city = next((c for c in CITY_NAMES if c in tag), None)
            if tag_city:
                break
    city_name = title_city or tag_city or city_name_from_code

    # 评论信息（从这次详情调用中获取）
    author_liked_comments = []
    hot_comments = []
    hot_comments_raw = []
    all_comments = []

    comments_result = await _aget(
        "/api/douyin/get-video-comment/v1",
        {"awemeId": video_id, "page": 1},
    )
    if comments_result.get("code") == 0:
        raw_comments = (comments_result.get("data") or {}).get("comments", []) or []
        for c in raw_comments:
            text = c.get("text", "")
            if not text:
                continue
            digg = c.get("digg_count", 0)
            comment_data = {"text": text, "digg_count": digg}

            all_comments.append(comment_data)

            # 博主点赞的评论：P1 最高优先级
            if c.get("is_author_digged"):
                author_liked_comments.append(comment_data)

            # 热门评论：P2 次优先级，同时保留 cid 供回复轮询使用
            if c.get("is_hot"):
                hot_comments.append(comment_data)
                hot_comments_raw.append({
                    "cid": c.get("cid", ""),
                    "text": text,
                    "digg_count": digg,
                })

        # 按点赞数降序排列
        author_liked_comments.sort(key=lambda x: x["digg_count"], reverse=True)
        hot_comments.sort(key=lambda x: x["digg_count"], reverse=True)
        hot_comments_raw.sort(key=lambda x: x["digg_count"], reverse=True)
        all_comments.sort(key=lambda x: x["digg_count"], reverse=True)

    print(f"[抖音解析] 解析成功: video_id={video_id}, author={author_name}, sec_uid={author_sec_uid[:20] if author_sec_uid else ''}")
    print(f"[抖音解析] 扩展信息: 话题={hashtags}, 城市={city_name}, "
          f"博主点赞评论={len(author_liked_comments)}条, 热门评论={len(hot_comments)}条, 总评论={len(all_comments)}条")

    return {
        "video_id": video_id,
        "title": title,
        "author_id": author_id,
        "author_name": author_name,
        "author_avatar": author_avatar,
        "author_sec_uid": author_sec_uid,
        "hashtags": hashtags,
        "city_name": city_name,
        "author_liked_comments": author_liked_comments,
        "hot_comments": hot_comments,
        "hot_comments_raw": hot_comments_raw,
        "all_comments": all_comments,
    }


def extract_video_id_from_url(url: str) -> str | None:
    """
    从抖音 URL 中提取视频 ID（用于缓存命中检查）。

    支持格式：
    - https://v.douyin.com/xxx/ （短链，需要调用 API 转换）
    - https://www.iesdouyin.com/share/video/123456789/ （直接包含 video_id）
    - 123456789 （纯数字 video_id）
    """
    # 如果是纯数字，直接返回
    if re.match(r'^\d+$', url.strip()):
        return url.strip()

    # 尝试从 URL 中提取 video_id
    match = re.search(r'/video/(\d+)', url)
    if match:
        return match.group(1)

    return None


async def fetch_author_videos(sec_uid: str, max_count: int = 20) -> list[dict]:
    """
    获取博主发布的视频列表（用于批量解析博主所有探店视频）。

    优先使用 v3 接口（v1 容易限流返回 code=301）。
    支持分页，直到达到 max_count 或无更多数据。

    返回格式：[{"video_id": "...", "title": "...", "share_url": "..."}, ...]
    share_url 是可以在抖音中打开的视频链接
    """
    videos = []
    max_cursor = 0  # 分页游标，0 表示第一页

    while len(videos) < max_count:
        result = await _aget(
            "/api/douyin/get-user-video-list/v3",  # v3 比 v1 更稳定
            {"secUid": sec_uid, "maxCursor": max_cursor},
        )

        if result.get("code") != 0:
            print(f"[抖音解析] 获取博主视频列表失败: {result.get('message')} (code={result.get('code')})")
            break

        data = result.get("data", {})
        aweme_list = data.get("aweme_list", []) or []

        if not aweme_list:
            break  # 没有更多视频了

        for v in aweme_list:
            video_id = v.get("aweme_id", "")
            # 提取 share_url（可在抖音中打开的链接）
            share_url = v.get("share_url", "") or v.get("share_info", {}).get("share_url", "")
            # 如果没有 share_url，用 video_id 构造一个基础链接
            if not share_url and video_id:
                share_url = f"https://www.iesdouyin.com/share/video/{video_id}/"

            videos.append({
                "video_id": video_id,
                "title": v.get("desc", ""),
                "share_url": share_url,
            })
            if len(videos) >= max_count:
                break

        # 检查是否还有下一页
        has_more = data.get("has_more", 0)
        if not has_more:
            break
        max_cursor = data.get("max_cursor", 0)

    print(f"[抖音解析] 获取到博主视频 {len(videos)} 条")
    return videos


async def fetch_video_comments(video_id: str, max_count: int = 20) -> list[dict]:
    """
    获取视频评论列表，用于辅助 AI 识别店铺名称。
    评论中往往包含用户提到的具体店名，是识别店铺的关键信息来源。
    返回带点赞数的结构，供 AI 按热度权重判断最可能的店铺。

    返回格式：[{"text": "评论内容", "digg_count": 158}, ...]
    """
    result = await _aget(
        "/api/douyin/get-video-comment/v1",
        {"awemeId": video_id, "page": 1},
    )

    if result.get("code") != 0:
        print(f"[抖音解析] 获取评论失败: {result.get('message')} (code={result.get('code')})")
        return []

    comments_data = (result.get("data") or {}).get("comments", []) or []
    # 保留文本和点赞数，按点赞数降序排列，让高热度评论排在前面
    comments = [
        {"text": c.get("text", ""), "digg_count": c.get("digg_count", 0)}
        for c in comments_data if c.get("text")
    ]
    comments.sort(key=lambda x: x["digg_count"], reverse=True)
    comments = comments[:max_count]

    print(f"[抖音解析] 获取到评论 {len(comments)} 条，最高点赞: {comments[0]['digg_count'] if comments else 0}")
    return comments


async def fetch_video_detail_extra(video_id: str, author_uid: str = "") -> dict:
    """
    获取视频的扩展信息，用于辅助 AI 精准提取店铺名称。

    返回字段：
    - hashtags: 标题中的话题标签列表（如 ["上海火锅去哪吃", "上海火锅店"]）
    - city_code: 城市编码（310000=上海，110000=北京）
    - city_name: 城市名称（通过编码推断的中文城市名）
    - author_liked_comments: 博主点赞的评论列表（最高优先级信息来源）
    - hot_comments: 热门评论列表
    - all_comments: 所有评论列表（按点赞数降序）

    这些信息会按优先级传递给 AI，帮助更精准地识别店铺名称。
    """
    result = await _aget("/api/douyin/get-video-detail/v2", {"videoId": video_id})
    if result.get("code") != 0:
        print(f"[抖音解析] 获取视频详情扩展信息失败: {result.get('message')}")
        return {
            "hashtags": [],
            "city_code": "",
            "city_name": "未知",
            "author_liked_comments": [],
            "hot_comments": [],
            "all_comments": [],
        }

    aweme = result["data"].get("aweme_detail", {})
    # 从 text_extra 中提取话题标签（type=1 表示话题标签）
    text_extras = aweme.get("text_extra", []) or []
    hashtags = [
        t.get("hashtag_name", "")
        for t in text_extras
        if t.get("type") == 1 and t.get("hashtag_name")
    ]

    # 城市编码转中文（扩展到全国主要城市）
    city_code = str(aweme.get("city", ""))
    city_map = {
        # 直辖市
        "110000": "北京", "120000": "天津", "310000": "上海", "500000": "重庆",
        # 省会城市
        "130100": "石家庄", "140100": "太原", "150100": "呼和浩特", "210100": "沈阳",
        "220100": "长春", "230100": "哈尔滨", "320100": "南京", "330100": "杭州",
        "340100": "合肥", "350100": "福州", "360100": "南昌", "370100": "济南",
        "410100": "郑州", "420100": "武汉", "430100": "长沙", "440100": "广州",
        "450100": "南宁", "460100": "海口", "510100": "成都", "520100": "贵阳",
        "530100": "昆明", "540100": "拉萨", "610100": "西安", "620100": "兰州",
        "630100": "西宁", "640100": "银川", "650100": "乌鲁木齐",
        # 重点城市
        "440300": "深圳", "320500": "苏州", "330200": "宁波", "350200": "厦门",
        "370200": "青岛", "440400": "珠海", "440600": "佛山", "441300": "惠州",
        "441900": "东莞", "442000": "中山", "445100": "潮州", "445200": "揭阳",
        "510700": "绵阳", "511100": "乐山", "610200": "铜川", "610300": "宝鸡",
    }
    city_name_from_code = city_map.get(city_code, "未知" if not city_code or city_code == "0" else city_code)

    # 方案 E：从标题和话题标签中提取城市（优先级高于 city_code）
    # 原因：city_code 是博主注册城市，不一定是视频拍摄城市
    CITY_NAMES = [
        # 直辖市
        "北京", "天津", "上海", "重庆",
        # 省会城市
        "石家庄", "太原", "呼和浩特", "沈阳", "长春", "哈尔滨",
        "南京", "杭州", "合肥", "福州", "南昌", "济南",
        "郑州", "武汉", "长沙", "广州", "南宁", "海口",
        "成都", "贵阳", "昆明", "拉萨", "西安", "兰州",
        "西宁", "银川", "乌鲁木齐",
        # 重点城市
        "深圳", "苏州", "宁波", "厦门", "青岛", "珠海",
        "佛山", "惠州", "东莞", "中山", "潮州", "揭阳",
        "绵阳", "乐山", "宝鸡", "常州", "无锡", "温州",
        "嘉兴", "金华", "台州", "泉州", "漳州", "赣州",
        "烟台", "威海", "济宁", "临沂", "洛阳", "南阳",
        "宜昌", "襄阳", "株洲", "湘潭", "衡阳", "汕头",
        "江门", "湛江", "茂名", "肇庆", "清远", "梅州",
        "遵义", "大理", "丽江", "桂林", "柳州", "北海",
        "三亚", "海南", "西双版纳", "德宏",
        "大连", "鞍山", "抚顺", "本溪", "丹东",
        "哈尔滨", "齐齐哈尔", "牡丹江", "佳木斯",
        "包头", "鄂尔多斯", "呼伦贝尔",
        "唐山", "保定", "邯郸", "秦皇岛",
        "运城", "大同", "晋城",
        "徐州", "南通", "连云港", "淮安", "盐城", "扬州", "镇江", "泰州",
        "芜湖", "马鞍山", "安庆", "黄山",
        "郫县", "郫都",  # 成都下辖区，常见于美食视频
    ]
    # 先从标题中查找城市名
    video_title_for_city = aweme.get("desc", "")
    title_city = next((c for c in CITY_NAMES if c in video_title_for_city), None)
    # 再从话题标签中查找城市名（如果标题没找到）
    tag_city = None
    if not title_city:
        for tag in hashtags:
            tag_city = next((c for c in CITY_NAMES if c in tag), None)
            if tag_city:
                break
    # 优先级：标题城市 > 标签城市 > city_code 城市
    city_name = title_city or tag_city or city_name_from_code
    if title_city:
        print(f"[抖音解析] 城市来源：标题（{title_city}），city_code 城市={city_name_from_code}")
    elif tag_city:
        print(f"[抖音解析] 城市来源：话题标签（{tag_city}），city_code 城市={city_name_from_code}")

    # 获取博主点赞的评论（通过评论接口的 is_author_digged 字段）
    author_liked_comments = []
    hot_comments = []
    all_comments = []
    # 热门评论的完整原始数据（含 cid），供后续评论回复轮询使用
    hot_comments_raw = []

    comments_result = await _aget(
        "/api/douyin/get-video-comment/v1",
        {"awemeId": video_id, "page": 1},
    )
    if comments_result.get("code") == 0:
        raw_comments = (comments_result.get("data") or {}).get("comments", []) or []
        for c in raw_comments:
            text = c.get("text", "")
            if not text:
                continue
            digg = c.get("digg_count", 0)
            comment_data = {"text": text, "digg_count": digg}

            # 所有评论都加入列表
            all_comments.append(comment_data)

            # 博主点赞的评论：P1 最高优先级
            if c.get("is_author_digged"):
                author_liked_comments.append(comment_data)

            # 热门评论：P2 次优先级，同时保留 cid 供回复轮询使用
            if c.get("is_hot"):
                hot_comments.append(comment_data)
                hot_comments_raw.append({
                    "cid": c.get("cid", ""),
                    "text": text,
                    "digg_count": digg,
                })

        # 按点赞数降序排列
        author_liked_comments.sort(key=lambda x: x["digg_count"], reverse=True)
        hot_comments.sort(key=lambda x: x["digg_count"], reverse=True)
        hot_comments_raw.sort(key=lambda x: x["digg_count"], reverse=True)
        all_comments.sort(key=lambda x: x["digg_count"], reverse=True)

    print(f"[抖音解析] 视频扩展信息: 话题={hashtags}, 城市={city_name}, "
          f"博主点赞评论={len(author_liked_comments)}条, 热门评论={len(hot_comments)}条, 总评论={len(all_comments)}条")

    return {
        "hashtags": hashtags,
        "city_code": city_code,
        "city_name": city_name,
        "author_liked_comments": author_liked_comments,
        "hot_comments": hot_comments,
        "hot_comments_raw": hot_comments_raw,  # 含 cid，供评论回复轮询使用
        "all_comments": all_comments,
    }


async def fetch_comment_replies(comment_id: str, author_uid: str = "") -> dict:
    """
    获取某条评论的回复列表（评论回复接口）

    返回字段：
    - replies: 回复列表 [{"text": "...", "digg_count": 0, "is_author": False}, ...]
    - has_author_reply: 是否有博主回复
    - author_reply_text: 博主回复内容（如果有）
    """
    result = await _aget(
        "/api/douyin/get-video-sub-comment/v1",
        {"commentId": comment_id, "page": 1},
    )

    if result.get("code") != 0:
        print(f"[评论回复] 获取失败: {result.get('message')} (code={result.get('code')})")
        return {"replies": [], "has_author_reply": False, "author_reply_text": ""}

    raw_replies = (result.get("data") or {}).get("comments", []) or []
    replies = []
    has_author_reply = False
    author_reply_text = ""

    for r in raw_replies:
        text = r.get("text", "")
        if not text:
            continue

        reply_user_uid = str(r.get("user", {}).get("uid", ""))
        is_author = (reply_user_uid == author_uid) if author_uid else False

        replies.append({
            "text": text,
            "digg_count": r.get("digg_count", 0),
            "is_author": is_author,
        })

        if is_author:
            has_author_reply = True
            author_reply_text = text

    print(f"[评论回复] 获取到 {len(replies)} 条回复，博主回复={has_author_reply}")
    return {
        "replies": replies,
        "has_author_reply": has_author_reply,
        "author_reply_text": author_reply_text,
    }


def is_food_related_comment(comment_text: str) -> bool:
    """
    判断评论是否与美食店铺相关

    策略：评论中包含以下关键词之一，认为与店铺相关：
    - 店铺名相关：店、馆、家、坊、轩、阁、楼、居、苑、记、号
    - 地点相关：哪里、在哪、地址、位置、路、街、区、市
    - 询问相关：叫什么、什么店、店名、哪家
    """
    keywords = [
        "店", "馆", "家", "坊", "轩", "阁", "楼", "居", "苑", "记", "号",
        "哪里", "在哪", "地址", "位置", "路", "街", "区", "市",
        "叫什么", "什么店", "店名", "哪家", "名字",
    ]
    return any(kw in comment_text for kw in keywords)


async def poll_comment_replies_for_confidence(
    hot_comments_raw: list[dict],
    author_uid: str,
    max_polls: int = 2,
) -> dict:
    """
    轮询热门评论的回复，直到找到博主确认或置信度提升的信息

    策略：
    1. 只轮询与美食店铺相关的热门评论（通过关键词过滤）
    2. 优先轮询点赞数高的评论
    3. 如果找到博主回复且内容与店铺相关，立即返回
    4. 最多轮询 max_polls 次（默认 2 次），控制成本

    返回：
    - polled_replies: 所有轮询到的回复 [{"comment_text": "...", "replies": [...]}]
    - has_author_confirmation: 是否找到博主确认
    - author_confirmation_text: 博主确认内容
    - polls_used: 实际轮询次数
    """
    polled_replies = []
    has_author_confirmation = False
    author_confirmation_text = ""
    polls_used = 0

    # 过滤出与美食店铺相关的热门评论
    food_related_comments = [
        c for c in hot_comments_raw
        if is_food_related_comment(c.get("text", ""))
    ]

    if not food_related_comments:
        print("[评论回复轮询] 无美食相关评论，跳过轮询")
        return {
            "polled_replies": [],
            "has_author_confirmation": False,
            "author_confirmation_text": "",
            "polls_used": 0,
        }

    print(f"[评论回复轮询] 找到 {len(food_related_comments)} 条美食相关评论，开始轮询（最多 {max_polls} 次）")

    for comment in food_related_comments[:max_polls]:
        cid = comment.get("cid", "")
        comment_text = comment.get("text", "")

        if not cid:
            continue

        # 调用评论回复接口
        reply_data = await fetch_comment_replies(cid, author_uid)
        polls_used += 1

        polled_replies.append({
            "comment_text": comment_text,
            "replies": reply_data.get("replies", []),
        })

        # 检查是否有博主回复
        if reply_data.get("has_author_reply"):
            author_reply = reply_data.get("author_reply_text", "")
            # 博主回复内容与店铺相关（包含店名关键词或肯定表达）
            if is_food_related_comment(author_reply) or any(
                kw in author_reply for kw in ["是的", "对", "没错", "就是", "嗯", "对的"]
            ):
                has_author_confirmation = True
                author_confirmation_text = author_reply
                print(f"[评论回复轮询] 找到博主确认: {author_reply[:50]}")
                break  # 找到博主确认，立即停止轮询

        # 检查回复中是否有高赞确认（网友确认）
        high_digg_replies = [
            r for r in reply_data.get("replies", [])
            if r.get("digg_count", 0) >= 10
        ]
        if high_digg_replies:
            print(f"[评论回复轮询] 找到 {len(high_digg_replies)} 条高赞回复")

    print(f"[评论回复轮询] 完成，轮询次数={polls_used}，博主确认={has_author_confirmation}")

    return {
        "polled_replies": polled_replies,
        "has_author_confirmation": has_author_confirmation,
        "author_confirmation_text": author_confirmation_text,
        "polls_used": polls_used,
    }
