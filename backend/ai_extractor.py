# 通义千问 AI 模块
# 负责调用阿里云通义千问 API，从视频标题+评论中提取店铺信息
# 使用 OpenAI 兼容接口，通义千问支持该格式

import os
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
    comments: list[str],
    author_name: str = "",
) -> list[dict]:
    """
    调用通义千问，从视频标题和评论中提取店铺信息

    输入：
    - video_title: 视频标题/描述
    - comments: 评论列表
    - author_name: 博主名称（辅助信息）

    输出：店铺列表，每个店铺包含：
    - name: 店铺名称
    - city: 所在城市
    - category: 美食分类（如：火锅、烤肉、咖啡等）
    - confidence: 置信度（high/medium/low）
    """

    # 将评论拼接为文本，最多取前 15 条避免 token 过多
    comments_text = "\n".join(f"- {c}" for c in comments[:15]) if comments else "（无评论）"

    prompt = f"""你是一个美食信息提取助手。请从以下抖音探店视频的标题和评论中，提取所有提到的餐厅/店铺信息。

视频标题：{video_title}

视频评论：
{comments_text}

请提取所有出现的餐厅/店铺，以 JSON 数组格式返回，每个店铺包含以下字段：
- name: 店铺名称（尽量完整，如"海底捞火锅"而不是"海底捞"）
- city: 所在城市（如"上海"、"北京"，如果无法判断则填"未知"）
- category: 美食分类（如：火锅、烤肉、咖啡、甜品、日料、川菜等）
- confidence: 置信度，high=明确提到店名，medium=可能是店名，low=不确定

只返回 JSON 数组，不要有其他文字。如果没有找到任何店铺信息，返回空数组 []。

示例格式：
[
  {{"name": "老四川火锅", "city": "成都", "category": "火锅", "confidence": "high"}},
  {{"name": "星巴克", "city": "上海", "category": "咖啡", "confidence": "medium"}}
]"""

    try:
        response = await client.chat.completions.create(
            model="qwen-plus",  # 通义千问 Plus 版本，性价比高
            messages=[
                {"role": "system", "content": "你是专业的美食信息提取助手，擅长从中文文本中识别餐厅店铺信息。"},
                {"role": "user", "content": prompt},
            ],
            temperature=0.1,  # 低温度，让输出更稳定
            max_tokens=1000,
        )

        result_text = response.choices[0].message.content.strip()

        # 清理可能的 markdown 代码块格式
        if result_text.startswith("```"):
            result_text = re.sub(r"```(?:json)?\n?", "", result_text).strip("` \n")

        restaurants = json.loads(result_text)

        # 只保留置信度为 high 或 medium 的结果
        filtered = [r for r in restaurants if r.get("confidence") in ("high", "medium")]
        return filtered

    except json.JSONDecodeError as e:
        print(f"[AI解析] JSON 解析失败: {e}, 原始内容: {result_text}")
        return []
    except Exception as e:
        print(f"[AI解析] 调用通义千问失败: {e}")
        return []


# 补充缺少的 re 模块导入
import re
