# 通义千问 AI 模块
# 负责调用阿里云通义千问 API，从视频标题+评论中提取店铺信息
# 使用 OpenAI 兼容接口，通义千问支持该格式

import os
import re
import json
from openai import AsyncOpenAI
from dotenv import load_dotenv

load_dotenv()

# 初始化通义千问客户端（使用 OpenAI 兼容接口）
client = AsyncOpenAI(
    api_key=os.getenv("DASHSCOPE_API_KEY"),
    base_url="https://dashscope.aliyuncs.com/compatible-mode/v1",
)


async def extract_restaurants_from_video(
    video_title: str,
    comments: list,  # 支持 list[str] 或 list[dict{"text","digg_count"}] 两种格式
    author_name: str = "",
) -> list[dict]:
    """
    调用通义千问，从视频标题和评论中识别最可能的那一家店铺。

    评论支持两种格式：
    - list[str]：纯文本评论
    - list[dict]：带点赞数的评论，格式 {"text": "...", "digg_count": 158}

    输出：最多一个店铺的列表，包含：
    - name: 店铺名称
    - city: 所在城市
    - category: 美食分类
    - confidence: 置信度（high/medium/low）
    """

    # 将评论格式化为带点赞数的文本，让 AI 感知热度权重
    if comments and isinstance(comments[0], dict):
        # 带点赞数格式：显示点赞数，让 AI 知道哪条评论更有代表性
        comments_text = "\n".join(
            f"- [{c['digg_count']}赞] {c['text']}" for c in comments[:15]
        )
    else:
        # 纯文本格式兼容
        comments_text = "\n".join(f"- {c}" for c in comments[:15]) if comments else "（无评论）"

    if not comments:
        comments_text = "（无评论）"

    prompt = f"""你是一个美食信息提取助手。请从以下抖音探店视频的标题和评论中，判断博主这条视频探访的是哪一家具体店铺。

视频标题：{video_title}

视频评论（格式：[点赞数] 评论内容，点赞数越高代表该评论越有代表性）：
{comments_text}

分析要求：
1. 视频通常只探访一家店，请综合标题和评论判断最可能的那一家
2. 优先参考点赞数高的评论，它们更能代表大众对店铺的认知
3. 如果评论中有人直接说出店名（如"最山城火锅"），且点赞数较高，优先采信
4. 只输出一个最可能的店铺

以 JSON 对象格式返回（不是数组），包含以下字段：
- name: 店铺名称（尽量完整）
- city: 所在城市（如"上海"，无法判断则填"未知"）
- category: 美食分类（如：火锅、烤肉、咖啡等）
- confidence: 置信度，high=非常确定，medium=比较确定，low=不确定

只返回 JSON 对象，不要有其他文字。如果完全无法判断，返回 null。

示例格式：
{{"name": "最山城不改良重庆火锅", "city": "上海", "category": "火锅", "confidence": "high"}}"""

    try:
        response = await client.chat.completions.create(
            model="qwen-plus",
            messages=[
                {"role": "system", "content": "你是专业的美食信息提取助手，擅长从中文文本中识别餐厅店铺信息。"},
                {"role": "user", "content": prompt},
            ],
            temperature=0.1,
            max_tokens=300,
        )

        result_text = response.choices[0].message.content.strip()

        # 清理可能的 markdown 代码块格式
        if result_text.startswith("```"):
            result_text = re.sub(r"```(?:json)?\n?", "", result_text).strip("` \n")

        if result_text.lower() == "null" or not result_text:
            print(f"[AI解析] 未识别到店铺")
            return []

        restaurant = json.loads(result_text)

        # 过滤低置信度结果
        if restaurant.get("confidence") == "low":
            print(f"[AI解析] 置信度过低，跳过: {restaurant.get('name')}")
            return []

        print(f"[AI解析] 识别到店铺: {restaurant.get('name')} ({restaurant.get('city')}) 置信度={restaurant.get('confidence')}")
        return [restaurant]

    except json.JSONDecodeError as e:
        print(f"[AI解析] JSON 解析失败: {e}, 原始内容: {result_text}")
        return []
    except Exception as e:
        print(f"[AI解析] 调用通义千问失败: {e}")
        return []
