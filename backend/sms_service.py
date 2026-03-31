# 阿里云短信服务模块
# 负责发送验证码短信，替代 Supabase Auth 的短信功能

import os
import random
import time
import hashlib
import hmac
import base64
import urllib.parse
import uuid
from datetime import datetime
import httpx
from dotenv import load_dotenv

load_dotenv()

# 阿里云短信配置（从环境变量读取）
ALIYUN_ACCESS_KEY_ID = os.getenv("ALIYUN_ACCESS_KEY_ID", "")
ALIYUN_ACCESS_KEY_SECRET = os.getenv("ALIYUN_ACCESS_KEY_SECRET", "")
SMS_SIGN_NAME = os.getenv("SMS_SIGN_NAME", "跟吃")          # 短信签名
SMS_TEMPLATE_CODE = os.getenv("SMS_TEMPLATE_CODE", "")      # 短信模板 Code

# 内存存储验证码（key: 手机号, value: {code, expire_at}）
# 生产环境建议换成 Redis，但对于小应用内存存储足够
_otp_store: dict[str, dict] = {}

OTP_EXPIRE_SECONDS = 300  # 验证码有效期 5 分钟


def generate_otp() -> str:
    """生成 6 位随机数字验证码"""
    return str(random.randint(100000, 999999))


def store_otp(phone: str, code: str):
    """将验证码存入内存，设置过期时间"""
    _otp_store[phone] = {
        "code": code,
        "expire_at": time.time() + OTP_EXPIRE_SECONDS,
    }


def verify_otp(phone: str, code: str) -> bool:
    """
    验证用户输入的验证码是否正确
    验证成功后立即删除，防止重复使用
    """
    record = _otp_store.get(phone)
    if not record:
        return False
    if time.time() > record["expire_at"]:
        # 已过期，清除记录
        del _otp_store[phone]
        return False
    if record["code"] != code:
        return False
    # 验证成功，删除记录
    del _otp_store[phone]
    return True


def phone_to_user_id(phone: str) -> str:
    """
    将手机号转换为固定的 UUID 格式 user_id
    同一手机号永远对应同一 user_id，无需数据库存储用户表
    使用 UUID v5（基于命名空间的确定性 UUID）
    """
    # 使用固定命名空间，确保同一手机号每次生成相同的 UUID
    namespace = uuid.UUID("6ba7b810-9dad-11d1-80b4-00c04fd430c8")
    return str(uuid.uuid5(namespace, f"phone:{phone}"))


async def send_sms(phone: str, code: str) -> bool:
    """
    调用阿里云短信 API 发送验证码
    使用阿里云 SMS API v2017-05-25
    返回 True 表示发送成功，False 表示失败
    """
    if not ALIYUN_ACCESS_KEY_ID or not ALIYUN_ACCESS_KEY_SECRET:
        # 未配置阿里云密钥时，打印验证码到日志（仅用于开发调试）
        print(f"[短信调试] 手机号 {phone} 的验证码：{code}（未配置阿里云，仅打印日志）")
        return True

    # 构造阿里云 API 请求参数
    params = {
        "Action": "SendSms",
        "Version": "2017-05-25",
        "Format": "JSON",
        "AccessKeyId": ALIYUN_ACCESS_KEY_ID,
        "SignatureMethod": "HMAC-SHA1",
        "SignatureVersion": "1.0",
        "SignatureNonce": str(uuid.uuid4()),
        "Timestamp": datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
        "PhoneNumbers": phone,
        "SignName": SMS_SIGN_NAME,
        "TemplateCode": SMS_TEMPLATE_CODE,
        "TemplateParam": f'{{"code":"{code}"}}',
    }

    # 生成签名
    signature = _sign_request(params)
    params["Signature"] = signature

    # 发送请求
    try:
        async with httpx.AsyncClient() as client:
            resp = await client.get(
                "https://dysmsapi.aliyuncs.com",
                params=params,
                timeout=10,
            )
        result = resp.json()
        if result.get("Code") == "OK":
            return True
        else:
            print(f"[短信发送失败] Code={result.get('Code')}, Message={result.get('Message')}")
            return False
    except Exception as e:
        print(f"[短信发送异常] {e}")
        return False


def _sign_request(params: dict) -> str:
    """
    生成阿里云 API 请求签名
    签名算法：HMAC-SHA1，参考阿里云文档
    """
    # 1. 参数按字典序排序并 URL 编码
    sorted_params = sorted(params.items())
    query_string = "&".join(
        f"{_percent_encode(k)}={_percent_encode(str(v))}"
        for k, v in sorted_params
    )

    # 2. 构造待签名字符串
    string_to_sign = f"GET&{_percent_encode('/')}&{_percent_encode(query_string)}"

    # 3. HMAC-SHA1 签名
    key = (ALIYUN_ACCESS_KEY_SECRET + "&").encode("utf-8")
    msg = string_to_sign.encode("utf-8")
    signature = base64.b64encode(hmac.new(key, msg, hashlib.sha1).digest()).decode("utf-8")
    return signature


def _percent_encode(s: str) -> str:
    """URL 编码，阿里云要求特殊字符也要编码"""
    return urllib.parse.quote(s, safe="")
