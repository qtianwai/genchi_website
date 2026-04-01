#!/bin/bash
# Claude Code 任务完成通知脚本
# 当 Claude 完成响应时发送桌面通知

# 获取会话信息
session_id=$(jq -r '.session_id' < /dev/stdin 2>/dev/null || echo "unknown")
cwd=$(jq -r '.cwd' < /dev/stdin 2>/dev/null || echo "")

# 构建通知内容
TITLE="Claude Code 任务完成"
MESSAGE="✅ 已完成当前任务，继续提问请直接输入"

# 检测操作系统发送通知
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    osascript -e "display notification \"$MESSAGE\" with title \"$TITLE\""
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    # Linux (需要 notify-send)
    notify-send "$TITLE" "$MESSAGE" 2>/dev/null || echo "通知发送失败"
fi

exit 0
