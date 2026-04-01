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

    使用 JustOneAPI share-url-transfer/v1 接口，直接将分享短链转换为结构化数据。
    相比自行爬取，稳定性大幅提升，且能获取完整的博主 sec_uid。

    输入：抖音分享链接或包含链接的分享文字
    输出：{
        video_id, title, author_id, author_name, author_avatar,
        author_sec_uid, comments: []
    }
    """
    # 第一步：从文本中提取纯链接（兼容用户粘贴整段分享文字的情况）
    share_url = extract_url_from_text(url)
    print(f"[抖音解析] 提取到链接: {share_url}")

    # 第二步：调用 JustOneAPI 分享链接解析接口
    result = await _aget("/api/douyin/share-url-transfer/v1", {"shareUrl": share_url})
    print(f"[抖音解析] share-url-transfer 返回 code={result.get('code')}")

    if result.get("code") != 0 or not result.get("data"):
        raise ValueError(f"JustOneAPI 解析失败: {result.get('message', '未知错误')} (code={result.get('code')})")

    data = result["data"]

    # 第三步：从返回数据中提取视频和博主信息
    # JustOneAPI 返回的数据结构与抖音原始 aweme 结构一致
    aweme = data.get("aweme_detail") or data  # 兼容不同版本的返回结构
    author = aweme.get("author", {})

    video_id = aweme.get("aweme_id", "")
    title = aweme.get("desc", "")
    author_id = author.get("uid", "")
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

    使用 JustOneAPI get-user-video-list/v1 接口，支持分页，
    相比直接调用抖音 API 稳定得多。

    返回格式：[{"video_id": "...", "title": "..."}, ...]
    """
    videos = []
    max_cursor = 0  # 分页游标，0 表示第一页

    while len(videos) < max_count:
        result = await _aget(
            "/api/douyin/get-user-video-list/v1",
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
