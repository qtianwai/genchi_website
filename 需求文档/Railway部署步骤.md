# Railway 后端部署步骤

## 第一步：在 Railway 创建项目

1. 打开 [https://railway.app](https://railway.app)，用 GitHub 账号登录
2. 点击「**New Project**」→「**Deploy from GitHub repo**」
3. 选择仓库 `qtianwai/claude_test`
4. Railway 会自动检测到 `backend/Procfile`，点击「**Deploy**」

## 第二步：设置根目录

Railway 默认从仓库根目录部署，但我们的后端在 `backend/` 子目录：

1. 进入项目 → 点击服务 → 「**Settings**」
2. 找到「**Root Directory**」，填入：`backend`
3. 点击「**Save**」，Railway 会重新部署

## 第三步：添加环境变量

1. 点击「**Variables**」标签
2. 点击「**Raw Editor**」，粘贴以下内容：

```
DASHSCOPE_API_KEY=sk-2c6e706e26524eb696026f1b4c9a57ad
AMAP_API_KEY=ed74b2610dc920e300ae8e54838e659c
SUPABASE_URL=https://ygsxhvsmivcckmjmjmhr.supabase.co
SUPABASE_ANON_KEY=sb_publishable_gQdKpwmrgSIQOV2G45mghg_uWiIRnrd
SUPABASE_SERVICE_ROLE_KEY=sb_secret_dZmLQbc1r3vmHMt7k770eA_90VW8JtN
ALIYUN_ACCESS_KEY_ID=（阿里云 AccessKey ID，审核通过后填入）
ALIYUN_ACCESS_KEY_SECRET=（阿里云 AccessKey Secret，审核通过后填入）
SMS_SIGN_NAME=跟吃
SMS_TEMPLATE_CODE=（短信模板 Code，审核通过后填入，格式如 SMS_xxxxxxxxx）
```

3. 点击「**Update Variables**」

## 第四步：获取部署地址

部署完成后（约 2-3 分钟），在「**Settings**」→「**Networking**」中：
- 点击「**Generate Domain**」
- 复制生成的域名，格式如：`https://claude-test-production-xxxx.railway.app`

## 第五步：验证部署

在浏览器访问：`https://你的域名.railway.app/`

应该看到：
```json
{"status": "ok", "service": "跟吃后端"}
```

访问 API 文档：`https://你的域名.railway.app/docs`

---

**部署完成后，把域名告诉我，我来更新 iOS 代码中的 BASE_URL。**

域名为：claudetest-production-c925.up
