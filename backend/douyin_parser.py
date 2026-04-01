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


async def _aget(path: str, params: dict) -> dict:
    """
    异步调用 JustOneAPI GET 接口（供 async 函数使用）。
    """
    params["token"] = JUSTONEAPI_TOKEN
    params = {k: v for k, v in params.items() if v is not None}
    async with httpx.AsyncClient(timeout=30, follow_redirects=True) as client:
        resp = await client.get(f"{JUSTONEAPI_BASE}{path}", params=params)
        return resp.json()


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
    主入口：解析抖音分享链接，返回视频信息。

    两步流程：
    1. share-url-transfer/v1：将分享短链转换为 redirect_url，从中提取视频 ID
    2. get-video-detail/v2：用视频 ID 获取完整的视频和博主信息

    输入：抖音分享链接或包含链接的分享文字
    输出：{
        video_id, title, author_id, author_name, author_avatar,
        author_sec_uid, comments: []
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
    match = re.search(r'/video/(\d+)/', redirect_url)
    if not match:
        raise ValueError(f"无法从 redirect_url 提取视频 ID: {redirect_url}")
    video_id = match.group(1)
    print(f"[抖音解析] 提取到视频 ID: {video_id}")

    # 第三步：调用 get-video-detail/v2 获取完整视频和博主信息
    detail_result = await _aget("/api/douyin/get-video-detail/v2", {"videoId": video_id})
    print(f"[抖音解析] get-video-detail 返回 code={detail_result.get('code')}")

    if detail_result.get("code") != 0 or not detail_result.get("data"):
        raise ValueError(f"获取视频详情失败: {detail_result.get('message', '未知错误')}")

    # 数据结构：data.aweme_detail.author
    aweme = detail_result["data"].get("aweme_detail", {})
    author = aweme.get("author", {})

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

    print(f"[抖音解析] 解析成功: video_id={video_id}, author={author_name}, sec_uid={author_sec_uid[:20] if author_sec_uid else ''}")

    return {
        "video_id": video_id,
        "title": title,
        "author_id": author_id,
        "author_name": author_name,
        "author_avatar": author_avatar,
        "author_sec_uid": author_sec_uid,
        "comments": [],  # 评论通过单独接口获取，此处不获取
    }


async def fetch_author_videos(sec_uid: str, max_count: int = 20) -> list[dict]:
    """
    获取博主发布的视频列表（用于批量解析博主所有探店视频）。

    优先使用 v3 接口（v1 容易限流返回 code=301）。
    支持分页，直到达到 max_count 或无更多数据。

    返回格式：[{"video_id": "...", "title": "..."}, ...]
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
            videos.append({
                "video_id": v.get("aweme_id", ""),
                "title": v.get("desc", ""),
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
