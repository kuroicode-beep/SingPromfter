#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""SingPromfter MCP 서버 — stdio JSON-RPC ↔ 로컬 제어 API(127.0.0.1:8772).

AI 에이전트가 프롬프트만으로 SingPromfter를 조작한다:
곡 추가(유튜브 링크) · 키(피치) 조절 · 곡 수정/삭제 · 예약 큐 · 재생 제어.

안전 장치:
- 앱이 켜져 있어야 동작한다(제어 API는 앱 프로세스 안에서만 뜬다).
- 파괴적 도구(sp_delete_song, sp_queue_clear)는 confirm=true 필수.
- 유튜브 저작권 최초 확인(ack)은 앱 화면에서만 가능 — API로 우회 불가.
  ack 전에는 sp_add_song이 안내 메시지와 함께 거절된다.

등록: 저장소 루트의 .mcp.json 참조. 실행: python tool/mcp/singprompter_mcp.py
"""

import json
import os
import sys
import urllib.error
import urllib.request

BASE_URL = os.environ.get("SINGPROMPTER_API_URL", "http://127.0.0.1:8772")
TIMEOUT_SEC = 15

JSONRPC_PARSE_ERROR = -32700
JSONRPC_INVALID_PARAMS = -32602
JSONRPC_INTERNAL = -32603


class McpError(Exception):
    def __init__(self, code: int, message: str):
        super().__init__(message)
        self.code = code
        self.message = message


# ── HTTP 브리지 ──────────────────────────────────────────────────────────────


def _http(method: str, path: str, body: dict | None = None) -> dict:
    url = BASE_URL + path
    data = None
    headers = {"Accept": "application/json"}
    if body is not None:
        data = json.dumps(body, ensure_ascii=False).encode("utf-8")
        headers["Content-Type"] = "application/json; charset=utf-8"
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT_SEC) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as ex:
        # 제어 API는 오류도 JSON으로 준다 — 그대로 전달한다.
        try:
            return json.loads(ex.read().decode("utf-8"))
        except Exception:
            raise McpError(JSONRPC_INTERNAL, f"API 오류(HTTP {ex.code})") from ex
    except (urllib.error.URLError, TimeoutError) as ex:
        raise McpError(
            JSONRPC_INTERNAL,
            "SingPromfter 앱에 연결하지 못했습니다. 앱이 실행 중인지 확인해 주세요. "
            f"({BASE_URL})",
        ) from ex


def _require_confirm(args: dict, what: str) -> None:
    if args.get("confirm") is not True:
        raise McpError(
            JSONRPC_INVALID_PARAMS,
            f"{what}은(는) 되돌릴 수 없습니다. 정말 실행하려면 confirm=true를 함께 보내세요.",
        )


def _song_id(args: dict) -> str:
    song_id = str(args.get("song_id", "")).strip()
    if not song_id:
        raise McpError(JSONRPC_INVALID_PARAMS, "song_id가 필요합니다.")
    return song_id


# ── 도구 핸들러 ──────────────────────────────────────────────────────────────


def _state(args):
    return _http("GET", "/api/state")


def _list_songs(args):
    query = str(args.get("query", "")).strip()
    path = "/api/songs"
    if query:
        path += "?query=" + urllib.request.quote(query)
    return _http("GET", path)


def _get_song(args):
    return _http("GET", f"/api/songs/{_song_id(args)}")


def _add_song(args):
    url = str(args.get("url", "")).strip()
    if not url:
        raise McpError(JSONRPC_INVALID_PARAMS, "url(유튜브 링크)이 필요합니다.")
    mode = str(args.get("mode", "asIs"))
    if mode not in ("asIs", "original", "reduceVocal", "aiSeparate"):
        raise McpError(
            JSONRPC_INVALID_PARAMS,
            "mode는 asIs/original/reduceVocal/aiSeparate 중 하나여야 합니다.",
        )
    body = {
        "url": url,
        "mode": mode,
        "fetchLyrics": bool(args.get("fetch_lyrics", True)),
    }
    # 셋 중 하나라도 지정하면 다중 슬롯 계획으로 본다. 아니면 기존 동작.
    plan_keys = ("make_original", "make_instrumental", "pitch_semitones")
    if any(k in args for k in plan_keys):
        body["plan"] = {
            "makeOriginal": bool(args.get("make_original", False)),
            "makeInstrumental": bool(args.get("make_instrumental", True)),
            "pitchSemitones": args.get("pitch_semitones"),
        }
    return _http("POST", "/api/songs", body)


def _edit_song(args):
    song_id = _song_id(args)
    body = {}
    for key in ("title", "artist", "lyrics"):
        if key in args and args[key] is not None:
            body[key] = str(args[key])
    if not body:
        raise McpError(JSONRPC_INVALID_PARAMS, "title/artist/lyrics 중 하나는 필요합니다.")
    return _http("PATCH", f"/api/songs/{song_id}", body)


def _delete_song(args):
    _require_confirm(args, "곡 삭제(파일 포함)")
    return _http("DELETE", f"/api/songs/{_song_id(args)}")


def _set_pitch(args):
    song_id = _song_id(args)
    semitones = args.get("semitones")
    if not isinstance(semitones, int):
        raise McpError(JSONRPC_INVALID_PARAMS, "semitones(정수, 원곡 대비 반음 −6~+6)가 필요합니다.")
    body = {"semitones": semitones}
    if isinstance(args.get("slot"), int):
        body["slot"] = args["slot"]
    return _http("POST", f"/api/songs/{song_id}/pitch", body)


def _fetch_lyrics(args):
    return _http("POST", f"/api/songs/{_song_id(args)}/lyrics/fetch")


def _add_track(args):
    song_id = _song_id(args)
    url = str(args.get("url", "")).strip()
    if not url:
        raise McpError(JSONRPC_INVALID_PARAMS, "url(유튜브 링크)이 필요합니다.")
    body = {"url": url, "mode": str(args.get("mode", "asIs"))}
    if isinstance(args.get("slot"), int):
        body["slot"] = args["slot"]
    if args.get("label"):
        body["label"] = str(args["label"])
    return _http("POST", f"/api/songs/{song_id}/tracks", body)


def _remove_track(args):
    _require_confirm(args, "반주 삭제(파일 포함)")
    slot = args.get("slot")
    if not isinstance(slot, int):
        raise McpError(JSONRPC_INVALID_PARAMS, "slot(정수)이 필요합니다.")
    return _http("DELETE", f"/api/songs/{_song_id(args)}/tracks/{slot}")


def _queue_list(args):
    return _http("GET", "/api/queue")


def _queue_add(args):
    return _http("POST", "/api/queue", {"songId": _song_id(args)})


def _queue_remove(args):
    index = args.get("index")
    if not isinstance(index, int):
        raise McpError(JSONRPC_INVALID_PARAMS, "index(정수)가 필요합니다.")
    return _http("DELETE", f"/api/queue/{index}")


def _queue_clear(args):
    _require_confirm(args, "예약 큐 전체 비우기")
    return _http("POST", "/api/queue/clear")


def _queue_reorder(args):
    frm, to = args.get("from_index"), args.get("to_index")
    if not isinstance(frm, int) or not isinstance(to, int):
        raise McpError(JSONRPC_INVALID_PARAMS, "from_index/to_index(정수)가 필요합니다.")
    return _http("POST", "/api/queue/reorder", {"from": frm, "to": to})


def _select(args):
    body = {"songId": _song_id(args)}
    if isinstance(args.get("slot"), int):
        body["slot"] = args["slot"]
    return _http("POST", "/api/playback/select", body)


def _play(args):
    return _http("POST", "/api/playback/play")


def _pause(args):
    return _http("POST", "/api/playback/pause")


def _stop(args):
    return _http("POST", "/api/playback/stop")


def _restart(args):
    return _http("POST", "/api/playback/restart")


def _seek(args):
    sec = args.get("position_sec")
    if not isinstance(sec, (int, float)) or sec < 0:
        raise McpError(JSONRPC_INVALID_PARAMS, "position_sec(0 이상 숫자)가 필요합니다.")
    return _http("POST", "/api/playback/seek", {"positionMs": int(sec * 1000)})


def _set_volume(args):
    value = args.get("value")
    if not isinstance(value, (int, float)):
        raise McpError(JSONRPC_INVALID_PARAMS, "value(0.0~1.0)가 필요합니다.")
    return _http("POST", "/api/playback/volume", {"value": value})


def _set_rate(args):
    value = args.get("value")
    if not isinstance(value, (int, float)):
        raise McpError(JSONRPC_INVALID_PARAMS, "value(0.5~1.5)가 필요합니다.")
    return _http("POST", "/api/playback/rate", {"value": value})


def _jobs(args):
    return _http("GET", "/api/jobs")


def _job_cancel(args):
    job_id = str(args.get("job_id", "")).strip()
    if not job_id:
        raise McpError(JSONRPC_INVALID_PARAMS, "job_id가 필요합니다.")
    return _http("POST", f"/api/jobs/{job_id}/cancel")


def _job_retry(args):
    job_id = str(args.get("job_id", "")).strip()
    if not job_id:
        raise McpError(JSONRPC_INVALID_PARAMS, "job_id가 필요합니다.")
    return _http("POST", f"/api/jobs/{job_id}/retry")


# ── 도구 명세 ────────────────────────────────────────────────────────────────

def _schema(props: dict, required: list[str] | None = None) -> dict:
    return {
        "type": "object",
        "properties": props,
        "required": required or [],
        "additionalProperties": False,
    }


_SONG_ID_PROP = {"song_id": {"type": "string", "description": "곡 id (sp_list_songs로 확인)"}}

TOOLS = {
    "sp_state": {
        "description": "SingPromfter 현재 상태 — 선택 곡·재생 여부·위치·큐 길이·도구 상태.",
        "schema": _schema({}),
        "handler": _state,
    },
    "sp_list_songs": {
        "description": "곡 목록. query로 제목·가수를 부분 검색할 수 있다.",
        "schema": _schema({"query": {"type": "string", "description": "검색어(선택)"}}),
        "handler": _list_songs,
    },
    "sp_get_song": {
        "description": "곡 상세(가사 포함).",
        "schema": _schema(dict(_SONG_ID_PROP), ["song_id"]),
        "handler": _get_song,
    },
    "sp_add_song": {
        "description": (
            "유튜브 링크로 곡을 추가한다 — 내려받기→(선택)보컬 분리→가사 자동 부착→목록 등록. "
            "개인이 저작권을 소유한 링크만 사용해야 하며, 최초 1회 확인은 앱 화면에서만 가능하다."
        ),
        "schema": _schema({
            "url": {"type": "string", "description": "유튜브 링크"},
            "mode": {
                "type": "string",
                "enum": ["asIs", "original", "reduceVocal", "aiSeparate"],
                "description": "반주 처리: asIs=그대로(기본), aiSeparate=AI 보컬 분리",
            },
            "fetch_lyrics": {"type": "boolean", "description": "싱크 가사 자동 검색(기본 true)"},
            "make_original": {
                "type": "boolean",
                "description": "원곡(가이드 보컬 포함)도 슬롯으로 남길지",
            },
            "make_instrumental": {
                "type": "boolean",
                "description": "AI 분리 반주를 슬롯으로 남길지 (mode=aiSeparate 필요)",
            },
            "pitch_semitones": {
                "type": "integer",
                "minimum": -6,
                "maximum": 6,
                "description": "키조절본을 만들 반음. 생략하면 만들지 않는다",
            },
        }, ["url"]),
        "handler": _add_song,
    },
    "sp_edit_song": {
        "description": "곡 제목·가수·가사를 수정한다(반주 파일은 유지).",
        "schema": _schema({
            **_SONG_ID_PROP,
            "title": {"type": "string"},
            "artist": {"type": "string"},
            "lyrics": {"type": "string"},
        }, ["song_id"]),
        "handler": _edit_song,
    },
    "sp_delete_song": {
        "description": "⚠ 곡을 파일까지 완전히 삭제한다(되돌릴 수 없음). confirm=true 필수.",
        "schema": _schema({
            **_SONG_ID_PROP,
            "confirm": {"type": "boolean", "description": "true여야 실제로 삭제한다"},
        }, ["song_id", "confirm"]),
        "handler": _delete_song,
    },
    "sp_set_pitch": {
        "description": "곡 키를 절대값으로 지정한다(원곡 대비 반음 −6~+6, 0=원키). 처음 쓰는 키는 렌더링에 수십 초 걸릴 수 있다.",
        "schema": _schema({
            **_SONG_ID_PROP,
            "semitones": {"type": "integer", "minimum": -6, "maximum": 6},
            "slot": {"type": "integer", "description": "반주 슬롯(선택, 기본=현재/저장 슬롯)"},
        }, ["song_id", "semitones"]),
        "handler": _set_pitch,
    },
    "sp_fetch_lyrics": {
        "description": "곡의 싱크 가사를 LRCLIB에서 다시 검색해 붙인다.",
        "schema": _schema(dict(_SONG_ID_PROP), ["song_id"]),
        "handler": _fetch_lyrics,
    },
    "sp_add_track": {
        "description": (
            "기존 곡에 반주를 하나 더 붙인다(노래방 버전 등, 별도 링크). "
            "slot을 생략하면 빈 슬롯에 넣고, 지정하면 그 슬롯을 덮어쓴다."
        ),
        "schema": _schema({
            **_SONG_ID_PROP,
            "url": {"type": "string", "description": "유튜브 링크"},
            "mode": {
                "type": "string",
                "enum": ["asIs", "original", "reduceVocal", "aiSeparate"],
                "description": "반주 처리 (기본 asIs)",
            },
            "slot": {"type": "integer", "minimum": 1, "maximum": 4},
            "label": {"type": "string", "description": "반주 이름 (기본 '노래방')"},
        }, ["song_id", "url"]),
        "handler": _add_track,
    },
    "sp_remove_track": {
        "description": "⚠ 곡의 반주 하나를 파일까지 지운다(되돌릴 수 없음). confirm=true 필수.",
        "schema": _schema({
            **_SONG_ID_PROP,
            "slot": {"type": "integer", "minimum": 1, "maximum": 4},
            "confirm": {"type": "boolean", "description": "true여야 실제로 삭제한다"},
        }, ["song_id", "slot", "confirm"]),
        "handler": _remove_track,
    },
    "sp_queue_list": {
        "description": "예약 큐 목록.",
        "schema": _schema({}),
        "handler": _queue_list,
    },
    "sp_queue_add": {
        "description": "곡을 예약 큐에 추가한다.",
        "schema": _schema(dict(_SONG_ID_PROP), ["song_id"]),
        "handler": _queue_add,
    },
    "sp_queue_remove": {
        "description": "예약 큐에서 해당 인덱스 항목을 뺀다.",
        "schema": _schema({"index": {"type": "integer"}}, ["index"]),
        "handler": _queue_remove,
    },
    "sp_queue_clear": {
        "description": "⚠ 예약 큐를 전부 비운다. confirm=true 필수.",
        "schema": _schema({"confirm": {"type": "boolean"}}, ["confirm"]),
        "handler": _queue_clear,
    },
    "sp_queue_reorder": {
        "description": "예약 큐 순서를 바꾼다.",
        "schema": _schema({
            "from_index": {"type": "integer"},
            "to_index": {"type": "integer"},
        }, ["from_index", "to_index"]),
        "handler": _queue_reorder,
    },
    "sp_select": {
        "description": "곡을 선택(로드)한다. slot으로 반주 슬롯 지정 가능.",
        "schema": _schema({
            **_SONG_ID_PROP,
            "slot": {"type": "integer"},
        }, ["song_id"]),
        "handler": _select,
    },
    "sp_play": {"description": "재생(이미 재생 중이면 무동작).", "schema": _schema({}), "handler": _play},
    "sp_pause": {"description": "일시정지(정지 상태면 무동작).", "schema": _schema({}), "handler": _pause},
    "sp_stop": {"description": "정지하고 처음으로 되감는다.", "schema": _schema({}), "handler": _stop},
    "sp_restart": {"description": "처음부터 다시 재생한다.", "schema": _schema({}), "handler": _restart},
    "sp_seek": {
        "description": "재생 위치를 초 단위로 이동한다.",
        "schema": _schema({"position_sec": {"type": "number", "minimum": 0}}, ["position_sec"]),
        "handler": _seek,
    },
    "sp_set_volume": {
        "description": "볼륨(0.0~1.0).",
        "schema": _schema({"value": {"type": "number", "minimum": 0, "maximum": 1}}, ["value"]),
        "handler": _set_volume,
    },
    "sp_set_rate": {
        "description": "재생 속도(0.5~1.5).",
        "schema": _schema({"value": {"type": "number", "minimum": 0.5, "maximum": 1.5}}, ["value"]),
        "handler": _set_rate,
    },
    "sp_jobs": {"description": "가져오기 작업 목록·진행 상황.", "schema": _schema({}), "handler": _jobs},
    "sp_job_cancel": {
        "description": "가져오기 작업을 취소한다.",
        "schema": _schema({"job_id": {"type": "string"}}, ["job_id"]),
        "handler": _job_cancel,
    },
    "sp_job_retry": {
        "description": "실패한 가져오기 작업을 다시 시도한다.",
        "schema": _schema({"job_id": {"type": "string"}}, ["job_id"]),
        "handler": _job_retry,
    },
}


# ── JSON-RPC over stdio ─────────────────────────────────────────────────────


def _write(payload: dict) -> None:
    sys.stdout.write(json.dumps(payload, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def _result_text(request_id, payload: dict) -> None:
    _write({
        "jsonrpc": "2.0",
        "id": request_id,
        "result": {
            "content": [{
                "type": "text",
                "text": json.dumps(payload, ensure_ascii=False, indent=2),
            }],
        },
    })


def _tool_specs() -> list[dict]:
    return [
        {"name": name, "description": spec["description"], "inputSchema": spec["schema"]}
        for name, spec in TOOLS.items()
    ]


def _handle_request(msg: dict) -> None:
    method = msg.get("method", "")
    request_id = msg.get("id")

    if method == "initialize":
        _write({
            "jsonrpc": "2.0",
            "id": request_id,
            "result": {
                "protocolVersion": "2024-11-05",
                "capabilities": {"tools": {}},
                "serverInfo": {"name": "singprompter", "version": "1.0.0"},
            },
        })
        return
    if method == "notifications/initialized":
        return
    if method == "tools/list":
        _write({"jsonrpc": "2.0", "id": request_id, "result": {"tools": _tool_specs()}})
        return
    if method == "tools/call":
        params = msg.get("params") or {}
        name = params.get("name", "")
        args = params.get("arguments") or {}
        spec = TOOLS.get(name)
        if spec is None:
            _write({"jsonrpc": "2.0", "id": request_id,
                    "error": {"code": JSONRPC_INVALID_PARAMS, "message": f"알 수 없는 도구: {name}"}})
            return
        try:
            _result_text(request_id, spec["handler"](args))
        except McpError as ex:
            _write({"jsonrpc": "2.0", "id": request_id,
                    "error": {"code": ex.code, "message": ex.message}})
        except Exception as ex:  # noqa: BLE001 — 사유를 그대로 전달한다
            _write({"jsonrpc": "2.0", "id": request_id,
                    "error": {"code": JSONRPC_INTERNAL, "message": str(ex)}})
        return

    if request_id is not None:
        _write({"jsonrpc": "2.0", "id": request_id,
                "error": {"code": -32601, "message": f"지원하지 않는 메서드: {method}"}})


def run_stdio() -> None:
    # Windows 콘솔 기본 인코딩(cp949)에서 한국어 설명이 깨지지 않게 UTF-8 고정.
    sys.stdin.reconfigure(encoding="utf-8")
    sys.stdout.reconfigure(encoding="utf-8")
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            _write({"jsonrpc": "2.0", "id": None,
                    "error": {"code": JSONRPC_PARSE_ERROR, "message": "JSON 파싱 실패"}})
            continue
        _handle_request(msg)


if __name__ == "__main__":
    run_stdio()
