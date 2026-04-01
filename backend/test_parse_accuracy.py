#!/usr/bin/env python3
"""
测试视频解析准确率脚本
基于需求文档&技术方案/测试验证数据中的 16 个示例，验证当前解析算法的准确性
"""

import asyncio
import sys
from douyin_parser import parse_douyin_link, fetch_video_detail_extra, poll_comment_replies_for_confidence
from ai_extractor import extract_restaurants_priority, extract_restaurants_with_replies
from amap_service import batch_search_restaurants

# 测试用例（从测试验证数据文件提取）
TEST_CASES = [
    {
        "id": 1,
        "url": "https://v.douyin.com/8bevYS5PiMs/",
        "expected_name": "思烤家红谷滩店",
        "expected_city": "南昌",
        "note": "博主在底下留言回复了明确的店铺名"
    },
    {
        "id": 2,
        "url": "https://v.douyin.com/h77QH2q2vx4/",
        "expected_name": "南宁二十四味",
        "expected_city": "南宁",
        "note": "留言点赞最多，并且博主回复肯定"
    },
    {
        "id": 3,
        "url": "https://v.douyin.com/7lrNJVGXmxw/",
        "expected_name": "陈记食集",
        "expected_city": "青岛",
        "note": "评论作者有回复陈记食集"
    },
    {
        "id": 4,
        "url": "https://v.douyin.com/PxhxNzZ3Da4/",
        "expected_name": "新北汤逍遥",
        "expected_city": "常州",
        "note": "点赞最多的评论里有新北烫逍遥，并且作者点赞过"
    },
    {
        "id": 5,
        "url": "https://v.douyin.com/4XgxQ-C3vyU/",
        "expected_name": "最山城人民广场店",
        "expected_city": "上海",
        "note": "作者在留言回复里有明确说明是最山城人民广场店"
    },
    {
        "id": 6,
        "url": "https://v.douyin.com/TnOGKY381hc/",
        "expected_name": "周师饭店",
        "expected_city": "郫县",
        "note": "店铺名相关评论较多，网友评论侧面佐证"
    },
    {
        "id": 7,
        "url": "https://v.douyin.com/4Vnf0b8ExPQ/",
        "expected_name": "甘记肥肠粉",
        "expected_city": "成都",
        "note": "评论点赞多，有网友回复是的，侧面佐证"
    },
    {
        "id": 8,
        "url": "https://v.douyin.com/DXayVpcza5k/",
        "expected_name": "戴烤鸭",
        "expected_city": "成都",
        "note": "很难，评论涉及几家店铺，可接受AI识别为空",
        "accept_empty": True  # 识别为空也算成功
    },
    {
        "id": 9,
        "url": "https://v.douyin.com/rGE359B1ixg/",
        "expected_name": "尤兔头",
        "expected_city": "成都",
        "note": "评论中尤兔头点赞数较多，有网友回复就是尤兔头"
    },
    {
        "id": 10,
        "url": "https://v.douyin.com/5s0qR7E5XJU/",
        "expected_name": "鲜椒牛肉面",
        "expected_city": "成都",
        "note": "很难，有人留言看到视频就来了，照片是鲜椒牛肉面，建议就空着",
        "accept_empty": True  # 识别为空也算成功
    },
    {
        "id": 11,
        "url": "https://v.douyin.com/mPGae4N9gNs/",
        "expected_name": "九牛一毛",
        "expected_city": "成都",
        "note": "比较难识别，允许空着",
        "accept_empty": True  # 识别为空也算成功
    },
    {
        "id": 12,
        "url": "https://v.douyin.com/uyrzoLqsypg/",
        "expected_name": "陈桥老饭店",
        "expected_city": "上海",
        "note": "网友留言点赞多出现频率高，相关回复佐证"
    },
    {
        "id": 13,
        "url": "https://v.douyin.com/4z_R2gYcAxQ/",
        "expected_name": None,
        "expected_city": "上海",
        "note": "识别不出来，评论中连像样的店铺名都没有"
    },
    {
        "id": 14,
        "url": "https://v.douyin.com/-cBXgGlsw5U/",
        "expected_name": "悦来芳",
        "expected_city": "上海",
        "note": "比较难，博主回复地址，评论涉及该店铺名"
    },
    {
        "id": 15,
        "url": "https://v.douyin.com/lJ-ZSQhiHGg/",
        "expected_name": None,
        "expected_city": None,
        "note": "非美食视频，关于俄罗斯博物馆，不应入库"
    },
    {
        "id": 16,
        "url": "https://v.douyin.com/lTM-tcHPNCg/",
        "expected_name": None,
        "expected_city": None,
        "note": "非美食视频，关于山姆超市，不应入库"
    },
]


async def test_single_video(case: dict) -> dict:
    """测试单个视频的解析准确性"""
    print(f"\n{'='*80}")
    print(f"测试示例 {case['id']}: {case['note']}")
    print(f"URL: {case['url']}")
    print(f"期望店铺: {case['expected_name'] or '无'} ({case['expected_city'] or '无'})")
    print(f"{'='*80}")

    result = {
        "id": case["id"],
        "url": case["url"],
        "expected_name": case["expected_name"],
        "expected_city": case["expected_city"],
        "note": case["note"],
        "parsed_name": None,
        "parsed_city": None,
        "confidence": None,
        "success": False,
        "error": None,
    }

    try:
        # 第一步：解析视频基本信息
        video_info = await parse_douyin_link(case["url"])
        video_id = video_info["video_id"]
        title = video_info["title"]
        author_name = video_info["author_name"]
        author_id = video_info["author_id"]

        print(f"\n[视频信息]")
        print(f"  标题: {title}")
        print(f"  博主: {author_name}")

        # 第二步：获取扩展信息（话题标签、城市、评论）
        extra = await fetch_video_detail_extra(video_id, author_id)
        hashtags = extra.get("hashtags", [])
        city_name = extra.get("city_name", "未知")
        author_liked_comments = extra.get("author_liked_comments", [])
        hot_comments = extra.get("hot_comments", [])
        all_comments = extra.get("all_comments", [])
        hot_comments_raw = extra.get("hot_comments_raw", [])

        print(f"\n[扩展信息]")
        print(f"  话题标签: {hashtags}")
        print(f"  城市: {city_name}")
        print(f"  博主点赞评论: {len(author_liked_comments)} 条")
        print(f"  热门评论: {len(hot_comments)} 条")
        print(f"  总评论: {len(all_comments)} 条")

        # 第三步：AI 提取店铺信息（优先级算法）
        # v2.3：废弃降级算法，优先级算法返回空时直接返回空
        restaurants = await extract_restaurants_priority(
            video_title=title,
            author_name=author_name,
            hashtags=hashtags,
            city_name=city_name,
            author_liked_comments=author_liked_comments,
            hot_comments=hot_comments,
            all_comments=all_comments,
        )

        # 第四步（v2.4）：置信度 medium 或未识别到时，调用评论回复接口补充信息
        # 与 main.py 保持一致，但测试脚本不做每日限额控制
        # v2.6 优化：识别出店铺但缺分店信息时（high 但缺分店），也调用评论回复获取分店
        confidence = restaurants[0].get("confidence") if restaurants else "none"
        should_call_replies = confidence in ("medium", "none")
        if not should_call_replies and confidence == "high" and restaurants:
            # v2.6：high 置信度但缺分店信息时，也调用评论回复获取分店
            parsed_name = restaurants[0].get("name", "")
            if not any(keyword in parsed_name for keyword in ["店", "广场", "分店", "路", "街"]):
                should_call_replies = True
        if should_call_replies:
            print(f"\n[评论回复] 置信度={confidence}，尝试获取评论回复补充信息...")
            reply_data = await poll_comment_replies_for_confidence(
                hot_comments_raw=hot_comments_raw,
                author_uid=author_id,
                max_polls=2,
            )
            if reply_data.get("polled_replies"):
                print(f"[评论回复] 获取到回复，重新调用 AI 提取...")
                restaurants_with_replies = await extract_restaurants_with_replies(
                    video_title=title,
                    author_name=author_name,
                    hashtags=hashtags,
                    city_name=city_name,
                    author_liked_comments=author_liked_comments,
                    hot_comments=hot_comments,
                    all_comments=all_comments,
                    polled_replies=reply_data.get("polled_replies", []),
                )
                # 带回复的结果优先（无论置信度，只要有结果就采用）
                if restaurants_with_replies:
                    print(f"[评论回复] 带回复算法识别到店铺，采用新结果")
                    restaurants = restaurants_with_replies
                elif not restaurants:
                    # 带回复也没识别到，保持空
                    pass
            else:
                print(f"[评论回复] 未获取到有效回复")

        if not restaurants:
            print(f"\n[AI 提取] 未识别到店铺")
            result["parsed_name"] = None
            result["parsed_city"] = None
            result["confidence"] = "none"
        else:
            restaurant = restaurants[0]
            result["parsed_name"] = restaurant.get("name")
            result["parsed_city"] = restaurant.get("city")
            result["confidence"] = restaurant.get("confidence")

            print(f"\n[AI 提取] 识别到店铺:")
            print(f"  名称: {result['parsed_name']}")
            print(f"  城市: {result['parsed_city']}")
            print(f"  置信度: {result['confidence']}")

            # 第五步：高德地图搜索验证
            amap_results = await batch_search_restaurants(restaurants)
            if amap_results:
                amap_result = amap_results[0]
                print(f"\n[高德验证] 找到店铺:")
                print(f"  名称: {amap_result.get('name')}")
                print(f"  地址: {amap_result.get('address')}")
                print(f"  城市: {amap_result.get('city')}")
                print(f"  高德ID: {amap_result.get('amap_id')}")
            else:
                print(f"\n[高德验证] 未找到匹配的店铺")

        # 判断是否成功
        accept_empty = case.get("accept_empty", False)
        if case["expected_name"] is None:
            # 期望识别不出来或非美食视频
            result["success"] = (result["parsed_name"] is None)
        elif accept_empty and result["parsed_name"] is None:
            # 允许识别为空的情况（很难识别的用例）
            result["success"] = True
        else:
            # 期望识别出店铺，检查名称是否匹配（模糊匹配）
            if result["parsed_name"]:
                expected_core = case["expected_name"].replace("（", "").replace("）", "").replace("(", "").replace(")", "")
                parsed_core = result["parsed_name"].replace("（", "").replace("）", "").replace("(", "").replace(")", "")
                # 同音字/同义字替换（将同音字统一映射到同一个字，方便比较）
                HOMOPHONES = {"烫": "汤"}  # 统一替换
                expected_normalized = "".join(HOMOPHONES.get(c, c) for c in expected_core)
                parsed_normalized = "".join(HOMOPHONES.get(c, c) for c in parsed_core)
                # 检查核心名称是否包含或被包含（原始 + 同音字替换后）
                name_match = (
                    expected_core in parsed_core or parsed_core in expected_core
                    or expected_normalized == parsed_normalized
                    or expected_normalized in parsed_normalized or parsed_normalized in expected_normalized
                )
                # 品牌前缀匹配：取前2个字符，用于处理同品牌不同叫法（如"戴烤鸭"vs"戴鸭子"）
                prefix_match = (
                    len(expected_core) >= 2 and len(parsed_core) >= 2
                    and expected_core[:2] == parsed_core[:2]
                    and accept_empty  # 只在允许空的宽松用例中启用前缀匹配
                )
                result["success"] = name_match or prefix_match
            else:
                result["success"] = False

        print(f"\n[测试结果] {'✓ 成功' if result['success'] else '✗ 失败'}")

    except Exception as e:
        print(f"\n[错误] {e}")
        result["error"] = str(e)
        result["success"] = False

    return result


async def main():
    """运行所有测试用例"""
    print("开始测试视频解析准确率...")
    print(f"共 {len(TEST_CASES)} 个测试用例\n")

    results = []
    for case in TEST_CASES:
        result = await test_single_video(case)
        results.append(result)
        # 每个测试之间暂停 2 秒，避免 API 限流
        await asyncio.sleep(2)

    # 统计结果
    print(f"\n\n{'='*80}")
    print("测试结果汇总")
    print(f"{'='*80}\n")

    success_count = sum(1 for r in results if r["success"])
    total_count = len(results)
    accuracy = success_count / total_count * 100

    print(f"总测试数: {total_count}")
    print(f"成功数: {success_count}")
    print(f"失败数: {total_count - success_count}")
    print(f"准确率: {accuracy:.1f}%\n")

    # 详细结果表格
    print(f"{'ID':<4} {'期望店铺':<20} {'识别店铺':<20} {'置信度':<10} {'结果':<6}")
    print(f"{'-'*80}")
    for r in results:
        expected = r["expected_name"] or "无"
        parsed = r["parsed_name"] or "无"
        confidence = r["confidence"] or "-"
        status = "✓" if r["success"] else "✗"
        print(f"{r['id']:<4} {expected:<20} {parsed:<20} {confidence:<10} {status:<6}")

    # 失败案例分析
    failed_cases = [r for r in results if not r["success"]]
    if failed_cases:
        print(f"\n\n失败案例详细分析:")
        print(f"{'='*80}\n")
        for r in failed_cases:
            print(f"示例 {r['id']}: {r['note']}")
            print(f"  期望: {r['expected_name'] or '无'} ({r['expected_city'] or '无'})")
            print(f"  识别: {r['parsed_name'] or '无'} ({r['parsed_city'] or '无'})")
            if r["error"]:
                print(f"  错误: {r['error']}")
            print()

    return results


if __name__ == "__main__":
    asyncio.run(main())
