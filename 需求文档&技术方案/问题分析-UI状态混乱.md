# 问题分析：解析完成后 UI 状态混乱

## 问题描述

用户提交视频链接后，出现以下异常现象：
1. 解析完成后，下方仍显示"开始解析"按钮（应该显示解析结果）
2. 后台解析进度显示"已处理6个"后一直不更新
3. 后台服务一直在运行（不知道是什么服务）

## 根本原因分析

### 原因1：解析按钮状态管理问题

**代码位置**：`ParseLinkSheet.swift:120-138`

```swift
Button(action: parseLink) {
    HStack {
        if isLoading {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(0.8)
        }
        Text(isLoading ? "正在解析..." : "开始解析")
            .fontWeight(.semibold)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 14)
    .background(linkText.isEmpty || isLoading ? Color.gray.opacity(0.4) : Color.orange)
    .foregroundColor(.white)
    .clipShape(RoundedRectangle(cornerRadius: 14))
}
.disabled(linkText.isEmpty || isLoading)
```

**问题**：
- 按钮文本由 `isLoading` 状态控制
- `isLoading` 在 `parseLink()` 函数中设置为 `true`，在 API 返回后设置为 `false`
- 但解析完成后，按钮仍然显示"开始解析"，说明 `isLoading` 正确变为 `false`
- **真正的问题**：解析完成后，按钮应该隐藏或禁用，而不是继续显示"开始解析"

**设计缺陷**：
- 当前设计：解析完成后，按钮恢复为"开始解析"，用户可以再次点击
- 预期设计：解析完成后，应该隐藏按钮或改为"重新解析"，避免用户误以为解析未完成

### 原因2：后台进度卡住不更新

**代码位置**：`ParseLinkSheet.swift:208-242`

```swift
func startBgProgressPolling(authorId: String) {
    bgProgressTimer?.invalidate()
    bgProgressTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
        Task {
            do {
                let status = try await APIService.shared.getParseStatus(authorId: authorId)
                await MainActor.run {
                    if status.status == "completed" {
                        bgProgressTimer?.invalidate()
                        showBgProgress = false
                        if let newCount = status.new_restaurants_found, newCount > 0 {
                            bgCompletedMessage = "博主其他视频解析完成，发现 \(newCount) 家新店铺！"
                        } else {
                            bgCompletedMessage = "博主其他视频解析完成"
                        }
                    } else if status.status == "running" {
                        if let total = status.total_videos, total > 0,
                           let processed = status.processed_videos {
                            bgStatusMessage = "正在解析博主其他探店视频（\(processed)/\(total)）..."
                        } else if let processed = status.processed_videos {
                            bgStatusMessage = "正在解析博主历史视频（已处理 \(processed) 个）..."
                        }
                    } else if status.status == "failed" {
                        bgProgressTimer?.invalidate()
                        showBgProgress = false
                        bgStatusMessage = "后台解析遇到问题，请稍后刷新地图查看"
                    }
                }
            } catch {
                // 查询失败时静默忽略，下次继续轮询
            }
        }
    }
}
```

**可能的问题**：
1. **后台任务未正确启动**：`/api/parse-link` 返回 `is_background_running=true`，但实际后台任务未启动
2. **后台任务卡住**：后台任务在处理某个视频时卡住，导致进度不更新
3. **轮询接口返回错误**：`/api/parse-status` 接口返回错误，但前端静默忽略了
4. **Timer 失效**：Timer 在某些情况下可能失效（如 App 进入后台）

### 原因3：后台服务一直在运行

**后台任务逻辑**：`backend/main.py:245-366`

```python
def parse_author_all_videos_background(author_id: str, sec_uid: str, current_video_id: str):
    """
    后台任务：解析博主所有历史探店视频（异步执行，不阻塞主流程）
    在独立的事件循环中运行，支持分批处理和错误恢复
    """
    try:
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
        loop.run_until_complete(_parse_author_videos_async(author_id, sec_uid, current_video_id))
    except Exception as e:
        print(f"[后台任务] 博主全量解析出错 author_id={author_id}: {e}")
        try:
            task = create_bg_task(author_id, "full_scan")
            fail_bg_task(task["id"], str(e))
        except Exception:
            pass
    finally:
        loop.close()
```

**可能的问题**：
1. **任务未正确完成**：后台任务在处理过程中遇到错误，但未正确更新任务状态
2. **任务状态未持久化**：任务进度更新到数据库失败，导致前端查询到的进度不变
3. **API 调用失败**：JustOneAPI 调用失败，导致任务卡住

## 解决方案

### 方案1：优化解析按钮 UI 逻辑

**目标**：解析完成后，按钮应该明确表示"已完成"或"重新解析"

**实现**：
```swift
// 新增状态变量
@State private var parseCompleted = false

// 修改按钮逻辑
Button(action: parseLink) {
    HStack {
        if isLoading {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(0.8)
        }
        Text(buttonText)
            .fontWeight(.semibold)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 14)
    .background(buttonBackground)
    .foregroundColor(.white)
    .clipShape(RoundedRectangle(cornerRadius: 14))
}
.disabled(linkText.isEmpty || isLoading)

var buttonText: String {
    if isLoading {
        return "正在解析..."
    } else if parseCompleted {
        return "重新解析"
    } else {
        return "开始解析"
    }
}

var buttonBackground: Color {
    if linkText.isEmpty || isLoading {
        return Color.gray.opacity(0.4)
    } else if parseCompleted {
        return Color.blue
    } else {
        return Color.orange
    }
}

// 在 parseLink() 函数中设置状态
func parseLink() {
    guard !linkText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
    isLoading = true
    parseCompleted = false  // 重置状态
    errorMessage = nil
    result = nil
    bgCompletedMessage = nil
    showBgProgress = false
    bgProgressTimer?.invalidate()

    Task {
        do {
            let response = try await APIService.shared.parseDouyinLink(
                url: linkText.trimmingCharacters(in: .whitespaces),
                userId: authState.userId
            )
            result = response
            parseCompleted = true  // 标记完成
            onSuccess()

            // 如果有后台任务正在运行，启动轮询
            if response.is_background_running, let authorId = response.author_id ?? response.author?.id {
                showBgProgress = true
                bgStatusMessage = "正在解析博主其他探店视频..."
                startBgProgressPolling(authorId: authorId)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
```

### 方案2：增强后台进度轮询的错误处理

**目标**：当轮询失败时，显示错误提示而不是静默忽略

**实现**：
```swift
func startBgProgressPolling(authorId: String) {
    bgProgressTimer?.invalidate()
    var failureCount = 0  // 记录连续失败次数
    
    bgProgressTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
        Task {
            do {
                let status = try await APIService.shared.getParseStatus(authorId: authorId)
                failureCount = 0  // 成功后重置失败计数
                
                await MainActor.run {
                    if status.status == "completed" {
                        bgProgressTimer?.invalidate()
                        showBgProgress = false
                        if let newCount = status.new_restaurants_found, newCount > 0 {
                            bgCompletedMessage = "博主其他视频解析完成，发现 \(newCount) 家新店铺！"
                        } else {
                            bgCompletedMessage = "博主其他视频解析完成"
                        }
                    } else if status.status == "running" {
                        if let total = status.total_videos, total > 0,
                           let processed = status.processed_videos {
                            bgStatusMessage = "正在解析博主其他探店视频（\(processed)/\(total)）..."
                        } else if let processed = status.processed_videos {
                            bgStatusMessage = "正在解析博主历史视频（已处理 \(processed) 个）..."
                        }
                    } else if status.status == "failed" {
                        bgProgressTimer?.invalidate()
                        showBgProgress = false
                        errorMessage = "后台解析遇到问题：\(status.message)"
                    }
                }
            } catch {
                failureCount += 1
                print("[轮询错误] 查询后台任务状态失败: \(error)")
                
                // 连续失败 3 次后停止轮询并提示用户
                if failureCount >= 3 {
                    await MainActor.run {
                        bgProgressTimer?.invalidate()
                        showBgProgress = false
                        errorMessage = "无法获取后台解析进度，请稍后刷新地图查看"
                    }
                }
            }
        }
    }
}
```

### 方案3：后台任务增加超时和日志

**目标**：防止后台任务无限期运行，增加详细日志便于排查问题

**实现**：
```python
async def _parse_author_videos_async(author_id: str, sec_uid: str, current_video_id: str):
    """
    异步执行：获取博主视频列表并逐一解析（排除当前视频）
    每次只解析视频标题（不获取评论），节省 API 调用
    """
    if not sec_uid:
        print(f"[后台解析] 博主无 sec_uid，跳过历史视频解析: {author_id}")
        return

    # 获取博主视频列表（最多 30 个，排除当前视频）
    videos = await fetch_author_videos(sec_uid, max_count=30)
    video_list = [{"video_id": v.get("video_id", ""), "title": v.get("title", "")}
                  for v in videos if v.get("video_id") != current_video_id]

    if not video_list:
        print(f"[后台解析] 博主 {author_id} 无历史视频")
        return

    # 创建后台任务记录
    task = create_bg_task(author_id, "full_scan")
    task_id = task.get("id", "")
    update_bg_task_started(task_id)

    print(f"[后台解析] 开始解析博主 {author_id} 的 {len(video_list)} 个历史视频...")

    saved_count = 0
    start_time = time.time()  # 记录开始时间
    
    for i, video in enumerate(video_list):
        # 超时检查：单个博主解析不超过 10 分钟
        if time.time() - start_time > 600:
            print(f"[后台解析] 博主 {author_id} 解析超时（10分钟），已处理 {i}/{len(video_list)} 个视频")
            fail_bg_task(task_id, "解析超时（10分钟）")
            return
        
        vid = video.get("video_id", "")
        title = video.get("title", "")

        # 检查视频是否已在缓存（已有成功结果的跳过）
        existing_cache = get_video_cache_by_id(vid)
        if existing_cache and existing_cache.get("status") == "completed":
            print(f"[后台解析] 视频 {vid} 已解析过，跳过")
            update_bg_task_progress(task_id, i + 1, saved_count)
            continue

        # 创建该视频的缓存记录
        video_url = f"bg://{vid}"  # 后台任务用特殊 URL
        upsert_video_cache({
            "video_url": video_url,
            "video_id": vid,
            "author_id": author_id,
            "status": "parsing",
        })

        try:
            # 获取视频扩展信息（P1：标签+城市）
            extra = await fetch_video_detail_extra(vid, author_id)
            comments = await fetch_video_comments(vid, max_count=10) if vid else []

            # AI 提取
            extracted = await extract_restaurants_priority(
                video_title=title,
                author_name="",
                hashtags=extra.get("hashtags", []),
                city_name=extra.get("city_name", "未知"),
                author_liked_comments=extra.get("author_liked_comments", []),
                hot_comments=extra.get("hot_comments", []),
                all_comments=comments,
            )
            if not extracted:
                extracted = await extract_restaurants_from_video(
                    video_title=title,
                    comments=comments,
                    author_name="",
                )

            if extracted:
                # 高德搜索
                search_results = await batch_search_restaurants([extracted[0]])
                if search_results:
                    amap_result = search_results[0]
                    extracted[0].update({
                        "address": amap_result.get("address", ""),
                        "latitude": amap_result.get("latitude"),
                        "longitude": amap_result.get("longitude"),
                        "amap_id": amap_result.get("amap_id"),
                    })
                    result = _save_video_restaurant(video_url, vid, author_id, extracted[0])
                    if result["status"] == "saved":
                        saved_count += 1
                        print(f"[后台解析] 视频 {vid} 解析成功，店铺：{extracted[0].get('name')}")

            # 更新缓存状态
            if existing_cache := get_video_cache_by_id(vid):
                if existing_cache.get("status") != "completed":
                    upsert_video_cache({
                        "video_url": existing_cache["video_url"],
                        "video_id": vid,
                        "author_id": author_id,
                        "status": "completed" if saved_count > 0 else "failed",
                    })
        except Exception as e:
            print(f"[后台解析] 视频 {vid} 解析失败: {e}")
            update_video_cache_failed(video_url, str(e))

        update_bg_task_progress(task_id, i + 1, saved_count)

    complete_bg_task(task_id, saved_count)
    elapsed = time.time() - start_time
    print(f"[后台解析] 博主 {author_id} 后台解析完成，新增 {saved_count} 家店铺，耗时 {elapsed:.1f} 秒")
```

## 总结

问题3的根本原因是：
1. **UI 状态管理不清晰**：解析完成后按钮状态不明确，用户误以为解析未完成
2. **错误处理不足**：轮询失败时静默忽略，导致用户无法感知问题
3. **后台任务缺乏超时机制**：可能导致任务无限期运行

建议优先实现方案1和方案2，提升用户体验。方案3可以作为后续优化项。
