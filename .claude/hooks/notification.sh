#!/bin/bash
# Claude Code 任务完成通知脚本
# 当 Claude 完成响应时发送桌面通知

# 读取会话信息
SESSION_ID=$(jq -r '.session_id // "unknown"' < /dev/stdin 2>/dev/null || echo "unknown")

# 获取当前时间
CURRENT_TIME=$(date "+%H:%M:%S")

# 检查是否有实际完成的工作（检查 transcript 文件中最近的工具调用）
TRANSCRIPT_PATH=$(jq -r '.transcript_path // ""' < /dev/stdin 2>/dev/null || echo "")

# 简单通知：告知 Claude Code 已完成本次响应
osascript -e "display notification \"Claude Code 已完成响应\n时间: $CURRENT_TIME\n会话: ${SESSION_ID:0:8}...\" with title \"Claude Code 助手\" sound name \"Glass\""

exit 0
