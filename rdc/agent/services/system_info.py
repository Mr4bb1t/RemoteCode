"""
RDC Agent — Serviço de informações do sistema (psutil)
"""
from __future__ import annotations

import platform
import socket
import time
from datetime import timedelta

import psutil

from schemas.system import DiskInfo, SystemInfo

_boot_time = psutil.boot_time()


def _uptime_human(seconds: float) -> str:
    td = timedelta(seconds=int(seconds))
    d = td.days
    h, rem = divmod(td.seconds, 3600)
    m, s = divmod(rem, 60)
    parts = []
    if d:
        parts.append(f"{d}d")
    if h:
        parts.append(f"{h}h")
    if m:
        parts.append(f"{m}m")
    parts.append(f"{s}s")
    return " ".join(parts)


def _get_temperature() -> float | None:
    try:
        temps = psutil.sensors_temperatures()
        if not temps:
            return None
        for key in ("coretemp", "k10temp", "cpu_thermal", "acpitz"):
            if key in temps and temps[key]:
                return round(temps[key][0].current, 1)
        # fallback: primeiro sensor disponível
        for entries in temps.values():
            if entries:
                return round(entries[0].current, 1)
    except (AttributeError, OSError):
        return None
    return None


def get_system_info() -> SystemInfo:
    cpu_percent = psutil.cpu_percent(interval=None)
    cpu_cores = psutil.cpu_count(logical=True)

    ram = psutil.virtual_memory()
    ram_total_gb = round(ram.total / (1024**3), 2)
    ram_used_gb = round(ram.used / (1024**3), 2)
    ram_percent = ram.percent

    disks: list[DiskInfo] = []
    seen = set()
    for part in psutil.disk_partitions(all=False):
        if part.device in seen:
            continue
        seen.add(part.device)
        try:
            usage = psutil.disk_usage(part.mountpoint)
            disks.append(
                DiskInfo(
                    total_gb=round(usage.total / (1024**3), 2),
                    used_gb=round(usage.used / (1024**3), 2),
                    free_gb=round(usage.free / (1024**3), 2),
                    percent=usage.percent,
                    mountpoint=part.mountpoint,
                )
            )
        except PermissionError:
            continue

    uptime = time.time() - _boot_time

    return SystemInfo(
        hostname=socket.gethostname(),
        os=platform.system(),
        os_version=platform.version(),
        cpu_percent=cpu_percent,
        cpu_cores=cpu_cores or 0,
        ram_total_gb=ram_total_gb,
        ram_used_gb=ram_used_gb,
        ram_percent=ram_percent,
        disks=disks,
        temperature_celsius=_get_temperature(),
        uptime_seconds=uptime,
        uptime_human=_uptime_human(uptime),
    )
