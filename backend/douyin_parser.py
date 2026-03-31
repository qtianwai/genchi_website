# 抖音链接解析模块
# 负责从抖音分享链接中提取视频信息（标题、描述、评论等）
# 使用非官方方式解析，后期可替换为付费第三方 API

import httpx
import re
import json
from typing import Optional

# 请求头，模拟浏览器访问，避免被抖音拦截
HEADERS = {
    "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
    "Referer": "https://www.douyin.com/",
}


async def resolve_short_url(url: str) -> str:
    """
    将抖音短链接（v.douyin.com/xxx）解析为完整链接
    抖音分享出来的链接通常是短链，需要先跟随重定向获取真实 URL
    """
    async with httpx.AsyncClient(follow_redirects=True, headers=HEADERS, timeout=15) as client:
        resp = await client.get(url)
        return str(resp.url)


def extract_video_id(url: str) -> Optional[str]:
    """
    从抖音链接中提取视频 ID
    支持格式：
    - https://www.douyin.com/video/7123456789
    - https://v.douyin.com/xxxxx/
    """
    # 匹配 /video/数字ID 格式
    match = re.search(r"/video/(\d+)", url)
    if match:
        return match.group(1)
    return None


def extract_user_id(url: str) -> Optional[str]:
    """
    从抖音链接中提取博主用户 ID（sec_uid 或 user 路径）
    """
    match = re.search(r"/user/([^/?]+)", url)
    if match:
        return match.group(1)
    return None


async def fetch_video_info(video_id: str) -> dict:
    """
    通过视频 ID 获取视频基本信息（标题、描述、作者信息）
    使用抖音网页端接口，无需登录
    """
    api_url = f"https://www.douyin.com/aweme/v1/web/aweme/detail/?aweme_id={video_id}&aid=6383&version_name=23.5.0"

    async with httpx.AsyncClient(headers=HEADERS, timeout=15) as client:
        try:
            resp = await client.get(api_url)
            data = resp.json()
            aweme = data.get("aweme_detail", {})

            # 提取博主信息
            author = aweme.get("author", {})

            return {
                "video_id": video_id,
                "title": aweme.get("desc", ""),          # 视频标题/描述
                "author_id": author.get("uid", ""),       # 博主 uid
                "author_name": author.get("nickname", ""), # 博主昵称
                "author_avatar": author.get("avatar_thumb", {}).get("url_list", [""])[0],  # 博主头像
                "author_sec_uid": author.get("sec_uid", ""),  # 博主 sec_uid（唯一标识）
            }
        except Exception as e:
            # 如果接口失败，返回空数据，后续流程会处理
            print(f"[抖音解析] 获取视频信息失败: {e}")
            return {"video_id": video_id, "title": "", "author_id": "", "author_name": "", "author_avatar": "", "author_sec_uid": ""}


async def fetch_video_comments(video_id: str, max_count: int = 20) -> list[str]:
    """
    获取视频评论列表，用于辅助 AI 识别店铺信息
    评论中经常有用户补充的店铺地址、名称等信息
    """
    api_url = f"https://www.douyin.com/aweme/v1/web/comment/list/?aweme_id={video_id}&count={max_count}&cursor=0"

    async with httpx.AsyncClient(headers=HEADERS, timeout=15) as client:
        try:
            resp = await client.get(api_url)
            data = resp.json()
            comments = data.get("comments", []) or []
            # 只提取评论文本内容
            return [c.get("text", "") for c in comments if c.get("text")]
        except Exception as e:
            print(f"[抖音解析] 获取评论失败: {e}")
            return []


async def fetch_author_videos(sec_uid: str, max_count: int = 20) -> list[dict]:
    """
    获取博主的视频列表（用于批量解析博主所有探店视频）
    """
    api_url = f"https://www.douyin.com/aweme/v1/web/aweme/post/?sec_user_id={sec_uid}&count={max_count}&max_cursor=0"

    async with httpx.AsyncClient(headers=HEADERS, timeout=15) as client:
        try:
            resp = await client.get(api_url)
            data = resp.json()
            videos = data.get("aweme_list", []) or []
            return [
                {
                    "video_id": v.get("aweme_id", ""),
                    "title": v.get("desc", ""),
                }
                for v in videos
            ]
        except Exception as e:
            print(f"[抖音解析] 获取博主视频列表失败: {e}")
            return []


async def parse_douyin_link(url: str) -> dict:
    """
    主入口：解析抖音分享链接，返回视频信息 + 评论

    输入：抖音分享链接（短链或完整链接）
    输出：{
        video_id, title, author_id, author_name, author_avatar,
        author_sec_uid, comments: [评论文本列表]
    }
    """
    # 第一步：如果是短链，先解析为完整链接
    if "v.douyin.com" in url or "douyin.com" in url:
        full_url = await resolve_short_url(url)
    else:
        full_url = url

    # 第二步：提取视频 ID
    video_id = extract_video_id(full_url)
    if not video_id:
        raise ValueError(f"无法从链接中提取视频 ID: {url}")

    # 第三步：并发获取视频信息和评论（提高速度）
    import asyncio
    video_info, comments = await asyncio.gather(
        fetch_video_info(video_id),
        fetch_video_comments(video_id),
    )

    video_info["comments"] = comments
    return video_info
