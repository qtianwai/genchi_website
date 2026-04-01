#!/bin/bash
# Claude Code 完整任务完成通知脚本
# 分析会话输出，判断是否有实际工作完成，发送详细通知

# 读取 JSON 输入
INPUT=$(cat /dev/stdin)

# 提取信息
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null || echo "unknown")
CWD=$(echo "$INPUT" | jq -r '.cwd // ""' 2>/dev/null || echo "")
OUTPUT=$(echo "$INPUT" | jq -r '.tool_input.output // ""' 2>/dev/null || echo "")

# 获取当前时间
CURRENT_TIME=$(date "+%Y-%m-%d %H:%M:%S")

# 分析输出内容，判断任务类型
TASK_TYPE="响应完成"
if echo "$OUTPUT" | grep -q -i "完成\|创建\|修改\|新增\|更新\|删除"; then
    TASK_TYPE="任务完成"
fi

if echo "$OUTPUT" | grep -q -i "错误\|失败\|error\|fail"; then
    TASK_TYPE="处理完成(含警告)"
fi

if echo "$OUTPUT" | grep -q -i "会话总结"; then
    TASK_TYPE="会话已总结"
fi

# 发送桌面通知
osascript <<EOF
display notification "任务类型: $TASK_TYPE\n工作目录: $(basename "$CWD")\n时间: $CURRENT_TIME" with title "Claude Code - $TASK_TYPE" sound name "Glass"
EOF

exit 0
