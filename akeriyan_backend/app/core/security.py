from fastapi import Header, HTTPException
from app.config import settings


async def verify_token(authorization: str = Header(default="")):
    """Every protected endpoint requires: Authorization: Bearer <device_token>"""
    expected = f"Bearer {settings.device_token}"
    if authorization != expected:
        raise HTTPException(status_code=401, detail="Invalid or missing device token")
    return True