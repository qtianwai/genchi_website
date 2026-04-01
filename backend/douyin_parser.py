# 抖音链接解析模块
# 负责从抖音分享链接中提取视频信息（标题、描述、评论等）
# 使用非官方方式解析，后期可替换为付费第三方 API

import httpx
import re
import json
import urllib.parse
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


def extract_info_from_url(full_url: str) -> dict:
    """
    直接从重定向后的 URL 参数中提取博主 ID 和视频标题相关信息。
    抖音分享链接重定向到 iesdouyin.com，URL 参数中已包含 social_author_id 等信息，
    无需再请求页面 HTML，避免反爬问题。
    """
    # 从 activity_info JSON 参数中提取 social_author_id
    author_id = ""
    activity_match = re.search(r'activity_info=([^&]+)', full_url)
    if activity_match:
        try:
            activity_info = json.loads(urllib.parse.unquote(activity_match.group(1)))
            author_id = activity_info.get("social_author_id", "")
        except Exception:
            pass

    # 备用：直接从 URL 参数 share_author_id 提取
    if not author_id:
        m = re.search(r'share_author_id=([^&]+)', full_url)
        if m:
            author_id = m.group(1)

    return {"author_id": author_id}


async def fetch_video_info_from_page(video_id: str, full_url: str) -> dict:
    """
    提取视频信息：
    1. 优先从 URL 参数直接提取博主 ID（iesdouyin.com 分享页 URL 含 social_author_id）
    2. 再请求 iesdouyin.com 分享页 HTML，提取视频标题和博主昵称
    """
    # 第一步：从 URL 参数提取博主 ID
    url_info = extract_info_from_url(full_url)
    author_id = url_info.get("author_id", "")

    # 第二步：请求分享页 HTML，提取标题和博主名
    title = ""
    author_name = ""
    try:
        async with httpx.AsyncClient(headers=HEADERS, timeout=20, follow_redirects=True) as client:
            resp = await client.get(full_url)
            html = resp.text

        # iesdouyin.com 分享页的 og:title 通常是视频标题
        title_match = re.search(r'<meta[^>]+property=["\']og:title["\'][^>]+content=["\']([^"\']+)["\']', html)
        if title_match:
            title = title_match.group(1)

        # og:description 通常格式为 "博主名发布了一个抖音视频" 或直接是博主名
        desc_match = re.search(r'<meta[^>]+property=["\']og:description["\'][^>]+content=["\']([^"\']+)["\']', html)
        if desc_match:
            author_name = desc_match.group(1).split('发布')[0].split('：')[0].strip()

        # 尝试从页面内嵌 JSON 提取更完整信息
        json_match = re.search(r'window\._ROUTER_DATA\s*=\s*(\{.*?\});?\s*</script>', html, re.DOTALL)
        if not json_match:
            json_match = re.search(r'<script[^>]*>\s*window\.__INIT_PROPS__\s*=\s*(\{.*?\})\s*</script>', html, re.DOTALL)
        if json_match:
            try:
                page_data = json.loads(json_match.group(1))
                # 尝试找 aweme/item_list 结构
                item_list = (page_data.get("loaderData", {})
                             .get("video_(id)/page", {})
                             .get("videoInfoRes", {})
                             .get("item_list", []))
                if item_list:
                    item = item_list[0]
                    author = item.get("author", {})
                    return {
                        "video_id": video_id,
                        "title": item.get("desc", title),
                        "author_id": author.get("uid", author_id),
                        "author_name": author.get("nickname", author_name),
                        "author_avatar": author.get("avatar_thumb", {}).get("url_list", [""])[0],
                        "author_sec_uid": author.get("sec_uid", ""),
                    }
            except Exception:
                pass

    except Exception as e:
        print(f"[抖音解析] 请求分享页失败: {e}")

    print(f"[抖音解析] 提取结果: video_id={video_id}, author_id={author_id}, title={title[:30] if title else ''}, author={author_name}")
    return {
        "video_id": video_id,
        "title": title,
        "author_id": author_id,
        "author_name": author_name,
        "author_avatar": "",
        "author_sec_uid": "",
    }


async def fetch_author_videos(sec_uid: str, max_count: int = 20) -> list[dict]:
    """
    获取博主的视频列表（用于批量解析博主所有探店视频）
    抖音 API 有反爬，失败时返回空列表，调用方会降级为只处理当前视频
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
            print(f"[抖音解析] 获取博主视频列表失败（将只处理当前视频）: {e}")
            return []


def extract_url_from_text(text: str) -> str:
    """
    从分享文字中提取抖音链接
    用户粘贴的通常是整段分享文字，如：
    "5.82 复制打开抖音，看看【xxx】... https://v.douyin.com/xxx/ 04/09 ..."
    需要从中提取出 https:// 开头的链接
    """
    # 匹配 http:// 或 https:// 开头的 URL（到空格或换行为止）
    match = re.search(r'https?://\S+', text)
    if match:
        # 去掉末尾可能粘连的标点符号
        url = match.group(0).rstrip('.,;:!?，。；：！？')
        return url
    return text.strip()  # 没找到则原样返回（可能本身就是纯链接）


async def parse_douyin_link(url: str) -> dict:
    """
    主入口：解析抖音分享链接，返回视频信息

    输入：抖音分享链接或包含链接的分享文字（兼容整段分享文字）
    输出：{
        video_id, title, author_id, author_name, author_avatar,
        author_sec_uid, comments: []
    }
    """
    # 第一步：从文本中提取纯链接（兼容用户粘贴整段分享文字的情况）
    url = extract_url_from_text(url)

    # 第二步：跟随重定向，将短链解析为完整链接（含视频 ID）
    if "v.douyin.com" in url or "douyin.com" in url:
        full_url = await resolve_short_url(url)
    else:
        full_url = url

    print(f"[抖音解析] 重定向后 URL: {full_url}")

    # 第三步：从完整 URL 中提取视频 ID
    video_id = extract_video_id(full_url)
    if not video_id:
        raise ValueError(f"无法从链接中提取视频 ID: {full_url}")

    # 第四步：从页面 HTML 提取视频标题和博主信息（不调用内部 API，避免反爬）
    video_info = await fetch_video_info_from_page(video_id, full_url)

    # 评论 API 同样有反爬限制，暂不获取，AI 仅根据视频标题提取店铺
    video_info["comments"] = []
    return video_info
