"""
Schemas de Sistema
"""
from __future__ import annotations

from pydantic import BaseModel


class DiskInfo(BaseModel):
    total_gb: float
    used_gb: float
    free_gb: float
    percent: float
    mountpoint: str


class SystemInfo(BaseModel):
    hostname: str
    os: str
    os_version: str
    cpu_percent: float
    cpu_cores: int
    ram_total_gb: float
    ram_used_gb: float
    ram_percent: float
    disks: list[DiskInfo]
    temperature_celsius: float | None
    uptime_seconds: float
    uptime_human: str
