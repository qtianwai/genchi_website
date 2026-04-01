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


async def fetch_video_info_from_page(video_id: str, full_url: str) -> dict:
    """
    从抖音视频页面 HTML 提取视频标题和博主信息
    抖音内部 API 有反爬限制，改为直接解析页面 meta 标签
    """
    # 先尝试从 URL 参数中提取博主 ID（重定向后的 URL 通常含有 share_author_id）
    author_id_from_url = ""
    sec_uid_from_url = ""
    match_author = re.search(r'share_author_id=([^&]+)', full_url)
    if match_author:
        author_id_from_url = match_author.group(1)
    match_sec = re.search(r'sec_uid=([^&]+)', full_url)
    if match_sec:
        sec_uid_from_url = match_sec.group(1)

    # 请求视频页面，从 HTML meta 标签提取标题和博主名
    try:
        async with httpx.AsyncClient(headers=HEADERS, timeout=20, follow_redirects=True) as client:
            resp = await client.get(f"https://www.douyin.com/video/{video_id}")
            html = resp.text

        # 从 og:title 提取视频标题
        title = ""
        title_match = re.search(r'<meta[^>]+property=["\']og:title["\'][^>]+content=["\']([^"\']+)["\']', html)
        if title_match:
            title = title_match.group(1)
        else:
            # 备用：从 <title> 标签提取
            title_match2 = re.search(r'<title>([^<]+)</title>', html)
            if title_match2:
                title = title_match2.group(1).split('-')[0].strip()

        # 从 og:description 或页面内容提取博主名
        author_name = ""
        desc_match = re.search(r'<meta[^>]+name=["\']description["\'][^>]+content=["\']([^"\']+)["\']', html)
        if desc_match:
            # description 通常格式为 "博主名 - 视频标题"
            author_name = desc_match.group(1).split('-')[0].strip()

        # 从页面 JSON 数据中提取更完整的博主信息（抖音会在页面内嵌入 __NEXT_DATA__）
        json_match = re.search(r'<script id="__NEXT_DATA__"[^>]*>(.*?)</script>', html, re.DOTALL)
        if json_match:
            try:
                next_data = json.loads(json_match.group(1))
                # 尝试从嵌入数据中找博主信息
                video_detail = next_data.get("props", {}).get("pageProps", {}).get("videoInfoRes", {})
                item_list = video_detail.get("item_list", [])
                if item_list:
                    item = item_list[0]
                    author = item.get("author", {})
                    return {
                        "video_id": video_id,
                        "title": item.get("desc", title),
                        "author_id": author.get("uid", author_id_from_url),
                        "author_name": author.get("nickname", author_name),
                        "author_avatar": author.get("avatar_thumb", {}).get("url_list", [""])[0],
                        "author_sec_uid": author.get("sec_uid", sec_uid_from_url),
                    }
            except Exception:
                pass  # JSON 解析失败则继续用 meta 标签数据

        print(f"[抖音解析] 从页面提取: title={title}, author={author_name}, author_id={author_id_from_url}")
        return {
            "video_id": video_id,
            "title": title,
            "author_id": author_id_from_url,
            "author_name": author_name,
            "author_avatar": "",
            "author_sec_uid": sec_uid_from_url,
        }
    except Exception as e:
        print(f"[抖音解析] 获取视频信息失败: {e}")
        return {
            "video_id": video_id,
            "title": "",
            "author_id": author_id_from_url,
            "author_name": "",
            "author_avatar": "",
            "author_sec_uid": sec_uid_from_url,
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
