#!/usr/bin/env python3
"""Sync per-subagent token usage and USD cost from agy SQLite/Protobuf DBs."""

import argparse
from datetime import datetime
import json
import math
import os
from pathlib import Path
import re
import shutil
import sqlite3
import tempfile
from typing import Any, Dict, List, Optional, Set, Tuple


DEFAULT_RATE = {"in": 2.0, "cached": 0.5, "out": 10.0}
VALID_ID_RE = re.compile(r"^[A-Za-z0-9_-]+\Z")


def _safe_float(val: Any, default: float) -> float:
    """Convert val to finite float, returning default on invalid/null values."""
    if val is None or isinstance(val, bool):
        return default
    try:
        f = float(val)
    except (TypeError, ValueError):
        return default
    return f if math.isfinite(f) else default


def read_varint(buf: bytes, pos: int) -> Tuple[Optional[int], int]:
    """Decode a protobuf base-128 varint starting at pos."""
    val = 0
    shift = 0
    n = len(buf)
    while pos < n and shift < 70:
        b = buf[pos]
        pos += 1
        val |= (b & 0x7F) << shift
        if not (b & 0x80):
            return val, pos
        shift += 7
    return None, n


def iter_pb_fields(buf: bytes):
    """Yield (field_number, wire_type, value) from a protobuf message buffer."""
    pos = 0
    n = len(buf)
    while pos < n:
        tag, pos = read_varint(buf, pos)
        if tag is None:
            break
        field_num = tag >> 3
        wire_type = tag & 0x07
        if field_num == 0:
            break
        if wire_type == 0:
            val, pos = read_varint(buf, pos)
            if val is None:
                break
            yield field_num, wire_type, val
        elif wire_type == 1:
            if pos + 8 > n:
                break
            yield field_num, wire_type, buf[pos : pos + 8]
            pos += 8
        elif wire_type == 2:
            length, pos = read_varint(buf, pos)
            if length is None or length < 0 or pos + length > n:
                break
            yield field_num, wire_type, buf[pos : pos + length]
            pos += length
        elif wire_type == 5:
            if pos + 4 > n:
                break
            yield field_num, wire_type, buf[pos : pos + 4]
            pos += 4
        else:
            break


def parse_gen_metadata_blob(blob: bytes) -> List[Tuple[str, str, int, int, int]]:
    """Extract (resolved_model, match_text, uncached, cached, output) tuples from a blob."""
    turns: List[Tuple[str, str, int, int, int]] = []
    for fnum, wtype, val in iter_pb_fields(blob):
        if fnum != 1 or wtype != 2 or not isinstance(val, (bytes, bytearray)):
            continue
        uncached = 0
        cached = 0
        output = 0
        model_key = ""
        model_display = ""
        for inf, inw, inval in iter_pb_fields(bytes(val)):
            if inf == 4 and inw == 2 and isinstance(inval, (bytes, bytearray)):
                for uf, uw, uval in iter_pb_fields(bytes(inval)):
                    if uw != 0 or not isinstance(uval, int):
                        continue
                    if uf == 2:
                        uncached = uval
                    elif uf == 5:
                        cached = uval
                    elif uf == 3:
                        output = uval
            elif inf == 19 and inw == 2 and isinstance(inval, (bytes, bytearray)):
                model_key = bytes(inval).decode("utf-8", errors="replace").strip()
            elif inf == 21 and inw == 2 and isinstance(inval, (bytes, bytearray)):
                model_display = bytes(inval).decode("utf-8", errors="replace").strip()

        if uncached > 0 or cached > 0 or output > 0:
            resolved = model_display or model_key or "Unknown"
            match_text = f"{model_key} {model_display}".strip().lower()
            turns.append((resolved, match_text, uncached, cached, output))
    return turns


def load_prices(prices_path: Path) -> Tuple[List[Tuple[str, Dict[str, float]]], Dict[str, float]]:
    """Load and sort model pricing rules longest-key-first."""
    try:
        data = json.loads(prices_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError):
        return [], dict(DEFAULT_RATE)
    if not isinstance(data, dict):
        return [], dict(DEFAULT_RATE)
    models = data.get("models")
    if not isinstance(models, dict):
        return [], dict(DEFAULT_RATE)
    default_rate = models.get("default")
    if not isinstance(default_rate, dict):
        default_rate = dict(DEFAULT_RATE)

    rules: List[Tuple[str, Dict[str, float]]] = []
    for k, v in models.items():
        if k == "default" or not isinstance(k, str) or not isinstance(v, dict):
            continue
        rules.append((k.lower(), v))
    rules.sort(key=lambda item: (-len(item[0]), item[0]))
    return rules, default_rate


def match_rate(
    match_text: str,
    rules: List[Tuple[str, Dict[str, float]]],
    default_rate: Dict[str, float],
) -> Dict[str, float]:
    """Match model text against sorted pricing rules."""
    for key_lower, rate in rules:
        if key_lower in match_text:
            return rate
    return default_rate


def discover_subagents(brain_dir: Path, root_sid: str, max_depth: int = 5) -> List[Tuple[str, str, Path]]:
    """Recursively discover subagents up to max_depth, avoiding cycles and path traversal."""
    if not VALID_ID_RE.match(root_sid):
        return []
    discovered: List[Tuple[str, str, Path]] = []
    visited: Set[str] = {root_sid}
    queue: List[Tuple[str, int]] = [(root_sid, 0)]

    while queue:
        cur_id, depth = queue.pop(0)
        if depth >= max_depth:
            continue
        sub_dir = brain_dir / cur_id / ".system_generated" / "subagents"
        if not sub_dir.is_dir():
            continue
        try:
            json_files = sorted(sub_dir.glob("*.json"))
        except (OSError, ValueError, OverflowError):
            continue
        for jf in json_files:
            try:
                meta = json.loads(jf.read_text(encoding="utf-8"))
            except (OSError, UnicodeDecodeError, json.JSONDecodeError):
                meta = {}
            if not isinstance(meta, dict):
                meta = {}
            raw_id = str(meta.get("conversationId") or "").strip()
            if raw_id and VALID_ID_RE.match(raw_id):
                sub_id = raw_id
            elif VALID_ID_RE.match(jf.stem):
                sub_id = jf.stem
            else:
                continue
            if sub_id in visited:
                continue
            visited.add(sub_id)
            desc = meta.get("subagentDescriptor")
            name = "subagent"
            if isinstance(desc, dict) and desc.get("typeName"):
                name = str(desc["typeName"]).strip() or "subagent"
            discovered.append((sub_id, name, jf))
            queue.append((sub_id, depth + 1))

    return discovered


def read_gen_metadata_rows(db_path: Path) -> List[bytes]:
    """Read gen_metadata BLOBs from SQLite DB with WAL-safe temp copy fallback."""
    wal_path = Path(f"{db_path}-wal")
    shm_path = Path(f"{db_path}-shm")

    def _query_db(target_db: Path, readonly: bool) -> List[bytes]:
        if readonly:
            conn = sqlite3.connect(f"{target_db.resolve().as_uri()}?mode=ro", uri=True, timeout=0.5)
        else:
            conn = sqlite3.connect(str(target_db), timeout=0.5)
        try:
            cur = conn.cursor()
            cur.execute("SELECT * FROM gen_metadata")
            col_names = [d[0].lower() for d in (cur.description or [])]
            has_bytes_col = "bytes" in col_names
            bytes_idx = col_names.index("bytes") if has_bytes_col else -1
            blobs: List[bytes] = []
            for row in cur.fetchall():
                if has_bytes_col:
                    if bytes_idx < len(row):
                        val = row[bytes_idx]
                        if isinstance(val, (bytes, bytearray, memoryview)):
                            blobs.append(bytes(val))
                else:
                    for val in row:
                        if isinstance(val, (bytes, bytearray, memoryview)):
                            blobs.append(bytes(val))
                            break
            return blobs
        finally:
            conn.close()

    if not wal_path.exists():
        try:
            return _query_db(db_path, readonly=True)
        except (sqlite3.Error, OSError):
            pass

    with tempfile.TemporaryDirectory() as tmpdir:
        tmp_dir = Path(tmpdir)
        tmp_db = tmp_dir / db_path.name
        shutil.copy2(db_path, tmp_db)
        if wal_path.exists():
            try:
                shutil.copy2(wal_path, tmp_dir / wal_path.name)
            except OSError:
                pass
        if shm_path.exists():
            try:
                shutil.copy2(shm_path, tmp_dir / shm_path.name)
            except OSError:
                pass
        return _query_db(tmp_db, readonly=False)


def format_timestamp(db_path: Path, json_path: Path, fallback_now: str) -> str:
    """Format local mtime from db_path, else json_path, else fallback_now."""
    for candidate in (db_path, json_path):
        try:
            if candidate.exists():
                mtime = candidate.stat().st_mtime
                return datetime.fromtimestamp(mtime).strftime("%Y-%m-%d %H:%M")
        except (OSError, ValueError, OverflowError):
            continue
    return fallback_now


def sync_subagents(
    sid: str,
    brain_dir: Path,
    conv_dir: Path,
    prices_path: Path,
    out_path: Path,
    now_str: str,
) -> Dict[str, Any]:
    """Discover subagents, parse their DBs, price usage, and write sidecar JSON."""
    rules, default_rate = load_prices(prices_path)
    discovered = discover_subagents(brain_dir, sid, max_depth=5)

    records: List[Dict[str, Any]] = []
    for sub_id, name, json_path in discovered:
        db_path = conv_dir / f"{sub_id}.db"
        if not db_path.is_file():
            continue
        try:
            blobs = read_gen_metadata_rows(db_path)
        except (sqlite3.Error, OSError):
            continue

        ts = format_timestamp(db_path, json_path, now_str)
        grouped: Dict[str, Dict[str, Any]] = {}
        for blob in blobs:
            for resolved_model, match_text, u_tok, c_tok, o_tok in parse_gen_metadata_blob(blob):
                rate = match_rate(match_text, rules, default_rate)
                r_in = _safe_float(rate.get("in"), 2.0)
                r_cached = _safe_float(rate.get("cached"), 0.5)
                r_out = _safe_float(rate.get("out"), 10.0)
                turn_cost = (u_tok * r_in + c_tok * r_cached + o_tok * r_out) / 1_000_000.0

                entry = grouped.get(resolved_model)
                if entry is None:
                    entry = {
                        "session_id": sub_id,
                        "timestamp": ts,
                        "model": resolved_model,
                        "name": name,
                        "uncached_tokens": 0,
                        "cache_tokens": 0,
                        "output_tokens": 0,
                        "cost_usd": 0.0,
                    }
                    grouped[resolved_model] = entry
                entry["uncached_tokens"] += u_tok
                entry["cache_tokens"] += c_tok
                entry["output_tokens"] += o_tok
                entry["cost_usd"] += turn_cost

        for entry in grouped.values():
            entry["cost_usd"] = round(entry["cost_usd"], 10)
            records.append(entry)

    records.sort(key=lambda r: (r["timestamp"], r["session_id"], r["model"]))
    unique_sids = {r["session_id"] for r in records}

    payload = {
        "sid": sid,
        "synced_at": int(datetime.now().timestamp()),
        "subagent_count": len(unique_sids),
        "uncached_tokens": sum(r["uncached_tokens"] for r in records),
        "cache_tokens": sum(r["cache_tokens"] for r in records),
        "output_tokens": sum(r["output_tokens"] for r in records),
        "cost_usd": round(sum(r["cost_usd"] for r in records), 10),
        "records": records,
    }

    out_path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(prefix=f".{out_path.name}.", dir=str(out_path.parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(payload, f, separators=(",", ":"))
            f.write("\n")
        os.replace(tmp_name, out_path)
    except Exception:
        try:
            os.unlink(tmp_name)
        except OSError:
            pass
        raise

    return payload


def main() -> int:
    parser = argparse.ArgumentParser(description="Sync Jenbach subagent usage from agy SQLite DBs.")
    parser.add_argument("--sid", required=True, help="Root session ID")
    parser.add_argument("--brain-dir", required=True, help="Path to agy brain directory")
    parser.add_argument("--conv-dir", required=True, help="Path to agy conversations directory")
    parser.add_argument("--prices", required=True, help="Path to prices.json")
    parser.add_argument("--out", required=True, help="Output sidecar JSON path")
    parser.add_argument("--now", default="", help="Fallback timestamp YYYY-MM-DD HH:MM")
    args = parser.parse_args()

    now_str = args.now.strip() or datetime.now().strftime("%Y-%m-%d %H:%M")
    sync_subagents(
        sid=args.sid,
        brain_dir=Path(args.brain_dir),
        conv_dir=Path(args.conv_dir),
        prices_path=Path(args.prices),
        out_path=Path(args.out),
        now_str=now_str,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
