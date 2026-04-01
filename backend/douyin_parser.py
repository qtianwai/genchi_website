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
    - https://www.iesdouyin.com/share/video/7123456789/
    - https://v.douyin.com/xxxxx/
    """
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


def extract_json_object(text: str, start: int) -> Optional[str]:
    """
    从 start 位置开始，用括号匹配方式提取完整 JSON 对象。
    比正则更可靠，不会因为嵌套括号而截断。
    """
    depth = 0
    i = start
    in_string = False
    escape = False
    while i < len(text):
        c = text[i]
        if escape:
            escape = False
        elif c == '\\' and in_string:
            escape = True
        elif c == '"':
            in_string = not in_string
        elif not in_string:
            if c == '{':
                depth += 1
            elif c == '}':
                depth -= 1
                if depth == 0:
                    return text[start:i + 1]
        i += 1
    return None


def extract_info_from_url(full_url: str) -> dict:
    """
    直接从重定向后的 URL 参数中提取博主 ID。
    抖音分享链接重定向到 iesdouyin.com，URL 参数中已包含 social_author_id 等信息。
    """
    author_id = ""
    # 从 activity_info JSON 参数中提取 social_author_id
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
    从 iesdouyin.com 分享页提取视频完整信息。

    策略：
    1. 请求分享页 HTML
    2. 提取页面内嵌的 window._ROUTER_DATA JSON（含完整视频信息）
    3. 从中读取视频标题（desc）、博主昵称、sec_uid、头像等
    4. 若 _ROUTER_DATA 解析失败，降级为从 URL 参数提取博主 ID
    """
    # 先从 URL 参数提取博主 ID（作为兜底）
    url_info = extract_info_from_url(full_url)
    author_id_fallback = url_info.get("author_id", "")

    title = ""
    author_name = ""
    author_id = author_id_fallback
    author_sec_uid = ""
    author_avatar = ""

    try:
        async with httpx.AsyncClient(headers=HEADERS, timeout=20, follow_redirects=True) as client:
            resp = await client.get(full_url)
            html = resp.text

        # 用括号匹配方式提取完整 _ROUTER_DATA JSON，避免正则截断
        router_match = re.search(r"window\._ROUTER_DATA\s*=\s*\{", html)
        if router_match:
            start = router_match.start() + html[router_match.start():].index('{')
            raw_json = extract_json_object(html, start)
            if raw_json:
                try:
                    page_data = json.loads(raw_json)
                    item_list = (
                        page_data.get("loaderData", {})
                        .get("video_(id)/page", {})
                        .get("videoInfoRes", {})
                        .get("item_list", [])
                    )
                    if item_list:
                        item = item_list[0]
                        author = item.get("author", {})
                        # desc 是完整视频标题（含话题标签），信息量最大
                        title = item.get("desc", "")
                        author_name = author.get("nickname", "")
                        author_id = author.get("uid", "") or author_id_fallback
                        author_sec_uid = author.get("sec_uid", "")
                        author_avatar = (
                            author.get("avatar_thumb", {})
                            .get("url_list", [""])[0]
                        )
                        print(f"[抖音解析] _ROUTER_DATA 解析成功: title={title[:40]}, author={author_name}")
                        return {
                            "video_id": video_id,
                            "title": title,
                            "author_id": author_id,
                            "author_name": author_name,
                            "author_avatar": author_avatar,
                            "author_sec_uid": author_sec_uid,
                        }
                except Exception as e:
                    print(f"[抖音解析] _ROUTER_DATA JSON 解析失败: {e}")

        # 降级：从 og:title / og:description 提取（JS 渲染页面可能没有）
        title_match = re.search(r'<meta[^>]+property=["\']og:title["\'][^>]+content=["\']([^"\']+)["\']', html)
        if title_match:
            title = title_match.group(1)

        desc_match = re.search(r'<meta[^>]+property=["\']og:description["\'][^>]+content=["\']([^"\']+)["\']', html)
        if desc_match:
            author_name = desc_match.group(1).split('发布')[0].split('：')[0].strip()

    except Exception as e:
        print(f"[抖音解析] 请求分享页失败: {e}")

    print(f"[抖音解析] 降级提取结果: video_id={video_id}, author_id={author_id}, title={title[:30] if title else ''}, author={author_name}")
    return {
        "video_id": video_id,
        "title": title,
        "author_id": author_id,
        "author_name": author_name,
        "author_avatar": author_avatar,
        "author_sec_uid": author_sec_uid,
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
    match = re.search(r'https?://\S+', text)
    if match:
        # 去掉末尾可能粘连的标点符号
        url = match.group(0).rstrip('.,;:!?，。；：！？')
        return url
    return text.strip()


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

    # 第四步：从分享页 HTML 的 _ROUTER_DATA 提取完整视频信息
    video_info = await fetch_video_info_from_page(video_id, full_url)

    # 评论 API 有反爬限制，暂不获取
    video_info["comments"] = []
    return video_info
