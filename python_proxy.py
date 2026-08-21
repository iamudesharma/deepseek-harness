import asyncio
import json
import os
import shutil
import tempfile
import time
import httpx
from fastapi import FastAPI, Header, HTTPException, Request
from fastapi.responses import JSONResponse, StreamingResponse

app = FastAPI(title="Command Code OpenAI Proxy")

COMMAND_CODE_API_URL = "https://api.commandcode.ai/alpha/generate"
DEFAULT_CLI_VERSION = "0.24.1"

# Map common shorthand names to Command Code internal model identifiers
MODEL_MAP = {
    "deepseek-v4": "deepseek/deepseek-v4-pro",
    "deepseek-v4-pro": "deepseek/deepseek-v4-pro",
    "deepseek-v4-flash": "deepseek/deepseek-v4-flash",
    "minimax-m2.7": "MiniMaxAI/MiniMax-M2.7",
    "glm-5": "zai-org/GLM-5",
    "kimi-k2.5": "moonshotai/Kimi-K2.5",
    "qwen-3.6-plus": "Qwen/Qwen3.6-Plus",
}

# Roles the Command Code API accepts at params.messages[*].role
VALID_ROLES = {"user", "assistant"}

# ---------------------------------------------------------------------------
# Web search — inbuilt (Command Code / opencode Go)
# ---------------------------------------------------------------------------
# Uses the harness' inbuilt web-search provider (port of
# packages/web/web-search-deepseek/src/provider.ts — dsh-web-search-deepseek)
# via ctx.web / tool-web, NOT a bespoke DeepSeek client. When an opencode Go
# binary is available (OPENCODE_BIN / OPENCODE_GO_BIN / PATH `opencode`) the
# request is delegated to `opencode web search` (inbuilt Go provider) first,
# falling back to the Command Code inbuilt DeepSeek provider. Mirrors the
# Image 1 panel: API key, Endpoint, Max searches per request — all stored
# outside the settings file. Leave blank to keep the current key / use
# provider default.
WEB_SEARCH_DEFAULT_BASE_URL = "https://api.deepseek.com/anthropic/v1"
WEB_SEARCH_DEFAULT_MODEL = "deepseek-v4-flash"
WEB_SEARCH_DEFAULT_API_VERSION = "2023-06-01"
WEB_SEARCH_DEFAULT_MAX_TOKENS = 4096
WEB_SEARCH_DEFAULT_MAX_USES = 5  # Max searches per request — Image 1 field


def _resolve_web_search_api_key(
    header_api_key: str | None,
    body_api_key: str | None,
) -> str | None:
    """Resolve DeepSeek search API key: request body > Authorization header > env.

    Returns None when no key is configured; search is unavailable until one is.
    Stored outside the settings file — leave blank to keep the current key.
    """
    if body_api_key and body_api_key.strip():
        return body_api_key.strip()
    if header_api_key and header_api_key.strip():
        return header_api_key.strip()
    env_key = os.getenv("DEEPSEEK_API_KEY", "")
    if env_key.strip():
        return env_key.strip()
    return None


def _resolve_web_search_base_url(body_endpoint: str | None) -> str:
    """Resolve search endpoint: request body > DEEPSEEK_SEARCH_BASE_URL env > default.

    Leave blank to use the provider default.
    """
    if body_endpoint is not None and body_endpoint.strip():
        return body_endpoint.strip().rstrip("/")
    env_url = os.getenv("DEEPSEEK_SEARCH_BASE_URL", "")
    if env_url.strip():
        return env_url.strip().rstrip("/")
    return WEB_SEARCH_DEFAULT_BASE_URL


def _resolve_web_search_max_uses(body_value) -> int:
    """Resolve max searches per request: body > MAX_SEARCHES_PER_REQUEST env > default 5."""
    if body_value is not None:
        try:
            v = int(body_value)
            if v >= 1:
                return v
        except (ValueError, TypeError):
            pass
    env_raw = os.getenv("MAX_SEARCHES_PER_REQUEST", "") or os.getenv(
        "DEEPSEEK_SEARCH_MAX_USES", ""
    )
    if env_raw.strip():
        try:
            v = int(env_raw.strip())
            if v >= 1:
                return v
        except ValueError:
            pass
    return WEB_SEARCH_DEFAULT_MAX_USES


def _citation_snippets(blocks: list[dict]) -> dict[str, str]:
    """Build url -> cited_text map from text blocks' citations (first wins)."""
    mapping: dict[str, str] = {}
    for block in blocks:
        if block.get("type") != "text":
            continue
        for cite in block.get("citations") or []:
            url = cite.get("url")
            cited_text = cite.get("cited_text")
            if url and cited_text and url not in mapping:
                mapping[url] = cited_text
    return mapping


def _map_anthropic_response(payload: dict) -> dict:
    """Map DeepSeek Anthropic Messages response to normalized WebSearchResult.

    Raises HTTPException(WEB_PROVIDER_ERROR) when no web_search_tool_result blocks.
    Dedupes by url, joins citation snippet as `snippet`, mirrors provider.ts.
    """
    blocks = payload.get("content") or []
    result_blocks = [b for b in blocks if b.get("type") == "web_search_tool_result"]
    if not result_blocks:
        raise HTTPException(
            status_code=502,
            detail="DeepSeek returned no web_search_tool_result blocks; the request may not have triggered native web search",
        )
    snippets = _citation_snippets(blocks)
    seen: set[str] = set()
    sources: list[dict] = []
    for block in result_blocks:
        for item in block.get("content") or []:
            if item.get("type") != "web_search_result":
                continue
            url = item.get("url") or ""
            if not url or url in seen:
                continue
            seen.add(url)
            source: dict = {"url": url}
            title = item.get("title")
            if title:
                source["title"] = title
            snippet = snippets.get(url)
            if snippet:
                source["snippet"] = snippet
            page_age = item.get("page_age")
            if page_age:
                source["publishedAt"] = page_age
            sources.append(source)
    return {"sources": sources, "truncated": False}


def _inbuilt_search_env(
    api_key: str,
    base_url: str,
    model: str,
    api_version: str,
    max_tokens: int,
    max_uses: int,
) -> dict[str, str]:
    """Environment for the inbuilt search provider.

    Mirrors packages/web/web-search-deepseek/src/provider.ts — the provider
    reads DEEPSEEK_API_KEY (credential), DEEPSEEK_SEARCH_BASE_URL, model and
    max_uses at search time via the launch environment (Settings =
    web-search-deepseek namespace). Exposing them as process env lets the
    harness' inbuilt ctx.web provider resolve without a custom credentials
    plugin.
    """
    env: dict[str, str] = {}
    if api_key:
        env["DEEPSEEK_API_KEY"] = api_key
    if base_url:
        env["DEEPSEEK_SEARCH_BASE_URL"] = base_url
    if model:
        env["DEEPSEEK_SEARCH_MODEL"] = model
    if api_version:
        env["DEEPSEEK_SEARCH_API_VERSION"] = api_version
    env["DEEPSEEK_SEARCH_MAX_TOKENS"] = str(max_tokens)
    # Cordis patch row web-search-deepseek reads maxUses from config;
    # MAX_SEARCHES_PER_REQUEST is the Image 1 panel name.
    env["MAX_SEARCHES_PER_REQUEST"] = str(max_uses)
    return env


def _resolve_opencode_bin() -> str | None:
    """Opencode Go inbuilt search binary, if available.

    Priority: OPENCODE_BIN > OPENCODE_GO_BIN > PATH `opencode` / `opencode-go`.
    Returns None when not installed — caller falls back to the Command Code
    inbuilt provider (packages/web/web-search-deepseek via ctx.web / DeepSeekHarness).
    """
    for key in ("OPENCODE_BIN", "OPENCODE_GO_BIN"):
        cand = os.getenv(key, "").strip()
        if cand:
            return cand
    for name in ("opencode", "opencode-go"):
        found = shutil.which(name)
        if found:
            return found
    return None


async def _curl_opencode_search(
    query: str,
    max_results: int | None,
    timeout: int = 30,
) -> dict | None:
    """Opencode Go web search via `curl` (inbuilt Go provider, HTTP).

    When `OPENCODE_SEARCH_URL` is set (e.g. `http://127.0.0.1:4096/web/search`),
    curl that endpoint instead of shelling the binary. This keeps the Go
    provider path curl-based as requested for the inbuilt search. Returns None
    when not configured or on failure so the caller falls back to binary exec.
    """
    url = os.getenv("OPENCODE_SEARCH_URL", "").strip() or os.getenv("OPENCODE_API_URL", "").strip()
    if not url:
        return None
    # Normalize: allow bare base URL (e.g. http://127.0.0.1:4096) -> /web/search
    if url.rstrip("/").endswith("/web/search"):
        endpoint = url
    elif url.rstrip("/").endswith("/web"):
        endpoint = url.rstrip("/") + "/search"
    else:
        endpoint = url.rstrip("/") + "/web/search"
    body: dict = {"query": query, "queries": [query]}
    if max_results is not None and max_results > 0:
        body["max_results"] = max_results
        body["limit"] = max_results
    status, data, raw = await _curl_json_post(endpoint, {"accept": "application/json"}, body, timeout=timeout)
    if not (200 <= status < 300) or not isinstance(data, dict):
        return None
    sources = data.get("sources") or data.get("results") or []
    if not isinstance(sources, list):
        return None
    mapped: list[dict] = []
    seen: set[str] = set()
    for item in sources:
        if not isinstance(item, dict):
            continue
        u = item.get("url") or item.get("link") or ""
        if not u or u in seen:
            continue
        seen.add(u)
        src: dict = {"url": u}
        if item.get("title"):
            src["title"] = item["title"]
        if item.get("snippet") or item.get("description"):
            src["snippet"] = item.get("snippet") or item.get("description")
        if item.get("publishedAt") or item.get("page_age"):
            src["publishedAt"] = item.get("publishedAt") or item.get("page_age")
        mapped.append(src)
    return {
        "sources": mapped[: max_results] if max_results else mapped,
        "truncated": bool(data.get("truncated", False)) or (max_results is not None and len(mapped) > max_results),
        **({"content": data["content"]} if data.get("content") else {}),
    }


async def _perform_opencode_search(
    query: str,
    max_results: int | None,
    timeout_ms: int = 30_000,
) -> dict | None:
    """One query via opencode Go inbuilt web-search (preferred when installed).

    Priority is `curl` -> binary, both inbuilt Go provider (no bespoke DeepSeek
    client). First, if `OPENCODE_SEARCH_URL` / `OPENCODE_API_URL` is set, the
    search is `curl`'d to that HTTP endpoint (e.g. opencode's local server);
    otherwise the `opencode web search --json -q <query>` binary is executed via
    subprocess and its JSON is mapped. Returns None on missing binary, non-JSON
    output, or invocation failure so the caller falls back to the Command Code
    inbuilt DeepSeek provider. Never raises on missing opencode.

    Equivalent curl for the HTTP path:
        curl -sS -X POST "$OPENCODE_SEARCH_URL" \\
          -H "content-type: application/json" \\
          --data '{"query":"hello","max_results":8}'

    Equivalent binary path:
        opencode web search --json -q "hello" --limit 8
    """
    # curl-to-HTTP first when configured — keeps opencode path curl-based.
    curled = await _curl_opencode_search(query, max_results, timeout=timeout_ms // 1000 or 30)
    if curled is not None:
        return curled
    bin_path = _resolve_opencode_bin()
    if not bin_path:
        return None
    cmd = [bin_path, "web", "search", "--json", "-q", query]
    if max_results is not None and max_results > 0:
        cmd.extend(["--limit", str(max_results)])
    try:
        proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        try:
            stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=timeout_ms / 1000)
        except asyncio.TimeoutError:
            proc.kill()
            await proc.communicate()
            return None
        if proc.returncode != 0:
            return None
        payload = json.loads(stdout.decode("utf-8", errors="ignore") or "{}")
        sources = payload.get("sources") or payload.get("results") or []
        if not isinstance(sources, list):
            return None
        mapped: list[dict] = []
        seen: set[str] = set()
        for item in sources:
            if not isinstance(item, dict):
                continue
            url = item.get("url") or item.get("link") or ""
            if not url or url in seen:
                continue
            seen.add(url)
            src: dict = {"url": url}
            if item.get("title"):
                src["title"] = item["title"]
            if item.get("snippet") or item.get("description"):
                src["snippet"] = item.get("snippet") or item.get("description")
            if item.get("publishedAt") or item.get("page_age"):
                src["publishedAt"] = item.get("publishedAt") or item.get("page_age")
            mapped.append(src)
        return {
            "sources": mapped[: max_results] if max_results else mapped,
            "truncated": bool(payload.get("truncated", False)) or (max_results is not None and len(mapped) > max_results),
            **({"content": payload["content"]} if payload.get("content") else {}),
        }
    except Exception:
        return None


async def _perform_inbuilt_search(
    query: str,
    api_key: str,
    base_url: str,
    model: str,
    api_version: str,
    max_tokens: int,
    max_uses: int,
    max_results: int | None = None,
) -> dict:
    """Run one query through the inbuilt web-search provider via `curl`.

    Preference (curl-based, inbuilt providers — no bespoke httpx client):
      1) opencode Go `web search` — `curl` to $OPENCODE_SEARCH_URL (HTTP) or
         `opencode web search` binary via subprocess when HTTP not configured
      2) Command Code `ctx.web` (packages/web/web-search-deepseek) — `curl`
         to the provider's Anthropic Messages endpoint with
         `web_search_20250305` (same wire as provider.ts)

    Curl equivalents (copy-paste):

      # opencode Go (inbuilt, HTTP)
      curl -sS -X POST "$OPENCODE_SEARCH_URL" \\
        -H "content-type: application/json" \\
        --data '{"query":"hello","max_results":8}'

      # opencode Go (inbuilt, binary — when no HTTP server)
      opencode web search --json -q "hello" --limit 8

      # Command Code (inbuilt DeepSeek provider via curl — same as provider.ts)
      curl -sS -X POST "$DEEPSEEK_SEARCH_BASE_URL/messages" \\
        -H "x-api-key: $DEEPSEEK_API_KEY" -H "authorization: Bearer $DEEPSEEK_API_KEY" \\
        -H "anthropic-version: 2023-06-01" -H "content-type: application/json" \\
        --data '{"model":"deepseek-v4-flash","max_tokens":4096,"messages":[{"role":"user","content":[{"type":"text","text":"Perform a web search for the query: hello"}]}],"tools":[{"type":"web_search_20250305","name":"web_search","max_uses":5}]}'

    The harness' `deepseek_harness` SDK is not used here — web search goes
    through curl to the inbuilt providers per taste (ctx.web / opencode Go).
    """
    # 1) opencode Go inbuilt provider (curl → HTTP, else binary)
    oc = await _perform_opencode_search(query, max_results)
    if oc is not None:
        return oc

    # 2) Command Code inbuilt DeepSeek provider via curl — same wire request
    #    packages/web/web-search-deepseek/src/provider.ts sends
    #    (web_search_20250305). This is the curl equivalent of ctx.web search
    #    and reuses DEEPSEEK_API_KEY via headers, not via SDK import.
    return await _perform_anthropic_search_fallback(query, api_key, base_url, model, api_version, max_tokens, max_uses)


async def _curl_json_post(
    url: str,
    headers: dict[str, str],
    body: dict,
    timeout: int = 60,
) -> tuple[int, dict | None, str]:
    """POST JSON via `curl` and return (status, json_or_none, raw_text).

    Uses `curl -sS --max-time` with a temp file for the body so no shell
    quoting is needed. No `-L` — redirects are not followed (credentials
    not forwarded, same as the httpx fallback). Returns raw text for error
    diagnostics when JSON parsing fails.
    """
    tmp_path = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False) as tmp:
            json.dump(body, tmp)
            tmp_path = tmp.name
        args = [
            "curl",
            "-sS",
            "-X", "POST",
            url,
            "--max-time", str(timeout),
            "-w", "\n%{http_code}",
        ]
        for k, v in headers.items():
            args.extend(["-H", f"{k}: {v}"])
        args.extend(["-H", "Content-Type: application/json", "--data", f"@{tmp_path}"])
        proc = await asyncio.create_subprocess_exec(
            *args,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        try:
            stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=timeout + 5)
        except asyncio.TimeoutError:
            proc.kill()
            await proc.communicate()
            raise HTTPException(status_code=502, detail="DeepSeek search request timed out (curl)")
        text = stdout.decode("utf-8", errors="ignore")
        if proc.returncode != 0 and not text.strip():
            err = stderr.decode("utf-8", errors="ignore").strip() or f"curl exited {proc.returncode}"
            raise HTTPException(status_code=502, detail=f"DeepSeek search request failed: {err}")
        # Last line is http_code from -w
        *body_lines, code_line = text.rsplit("\n", 1) if "\n" in text else (text, "")
        raw = "\n".join(body_lines) if body_lines else ""
        try:
            status = int(code_line.strip()) if code_line.strip().isdigit() else 0
        except ValueError:
            status = 0
            raw = text
        if raw.strip():
            try:
                data: dict | None = json.loads(raw)
            except Exception:
                data = None
        else:
            data = None
        return status, data, raw
    finally:
        if tmp_path:
            try:
                os.unlink(tmp_path)
            except Exception:
                pass


async def _perform_anthropic_search_fallback(
    query: str,
    api_key: str,
    base_url: str,
    model: str,
    api_version: str,
    max_tokens: int,
    max_uses: int,
) -> dict:
    """Fallback when the harness runtime is unavailable — direct Anthropic Messages search via `curl`.

    Uses the same native `web_search_20250305` server-tool request the inbuilt
    DeepSeekSearchProvider would send, but via `curl` (not bespoke httpx).
    This vector is private fallback only; when the inbuilt provider is available
    the code above returns first. Mirrors `curl` examples below:

        curl -sS -X POST "$BASE/messages" \\
          -H "x-api-key: $DEEPSEEK_API_KEY" -H "authorization: Bearer $DEEPSEEK_API_KEY" \\
          -H "anthropic-version: 2023-06-01" -H "content-type: application/json" \\
          --data '{"model":"deepseek-v4-flash","max_tokens":4096,"messages":[{"role":"user","content":[{"type":"text","text":"Perform a web search for the query: hello"}]}],"tools":[{"type":"web_search_20250305","name":"web_search","max_uses":5}]}'
    """
    endpoint = f"{base_url}/messages"
    body = {
        "model": model,
        "max_tokens": max_tokens,
        "messages": [
            {
                "role": "user",
                "content": [{"type": "text", "text": f"Perform a web search for the query: {query}"}],
            }
        ],
        "tools": [{"type": "web_search_20250305", "name": "web_search", "max_uses": max_uses}],
    }
    headers = {
        "x-api-key": api_key,
        "authorization": f"Bearer {api_key}",
        "anthropic-version": api_version,
        "accept": "application/json",
        "user-agent": "deepseek-harness/0.0.1",
    }
    status, data, raw = await _curl_json_post(endpoint, headers, body, timeout=60)

    if status in (301, 302, 303, 307, 308):
        raise HTTPException(status_code=502, detail="DeepSeek search rejected redirect (credentials not forwarded)")

    if status == 0 or status >= 400:
        detail = f"DeepSeek API error (HTTP {status or 'curl'})"
        if isinstance(data, dict):
            msg = data.get("error", {}).get("message") if isinstance(data.get("error"), dict) else data.get("error") or data.get("message")
            if msg:
                detail = msg
        elif raw:
            detail = raw[:500]
        raise HTTPException(status_code=502, detail=detail)

    if not isinstance(data, dict):
        raise HTTPException(status_code=502, detail=f"DeepSeek returned an unprocessable response body: {raw[:500]}")

    result = _map_anthropic_response(data)
    return result


def _to_text_parts(content) -> list:
    """Normalize a message content value into a list of text content parts."""
    if content is None:
        return [{"type": "text", "text": ""}]
    if isinstance(content, str):
        return [{"type": "text", "text": content}]
    if isinstance(content, list):
        parts = []
        for part in content:
            if isinstance(part, str):
                parts.append({"type": "text", "text": part})
            elif isinstance(part, dict):
                if part.get("type") == "text":
                    parts.append({"type": "text", "text": part.get("text", "")})
                elif part.get("type") == "tool-result":
                    parts.append(part)
        if not parts:
            parts = [{"type": "text", "text": ""}]
        return parts
    return [{"type": "text", "text": json.dumps(content, ensure_ascii=False)}]


def sanitize_message(msg: dict) -> dict:
    """Convert an OpenAI-format message into the Command Code accepted shape."""
    role = msg.get("role", "user")
    content = msg.get("content")

    if role == "tool":
        tool_call_id = msg.get("tool_call_id") or msg.get("toolCallId") or msg.get("id") or "tool-unknown"
        tool_name = msg.get("name") or msg.get("toolName") or msg.get("tool_name") or "tool"
        inner = _to_text_parts(content)
        return {
            "role": "user",
            "content": [
                {
                    "type": "tool-result",
                    "toolCallId": tool_call_id,
                    "toolName": tool_name,
                    "content": inner,
                }
            ],
        }

    if role == "system":
        prefix = "[System] "
        if isinstance(content, str):
            content = prefix + content
        elif isinstance(content, list):
            content = [{"type": "text", "text": prefix}] + [
                part
                for part in content
                if isinstance(part, dict) and part.get("type") == "text"
            ]
        else:
            content = prefix + json.dumps(content, ensure_ascii=False)
        role = "user"
    elif role not in VALID_ROLES:
        role = "user"

    if role == "assistant" and msg.get("tool_calls"):
        parts = []
        if content is not None and content != "":
            parts.extend(_to_text_parts(content))
        for tc in msg.get("tool_calls") or []:
            tc_id = tc.get("id") or tc.get("toolCallId") or ""
            fn = tc.get("function") or {}
            name = fn.get("name") or tc.get("name") or "unknown"
            args = fn.get("arguments") or tc.get("arguments") or "{}"
            if isinstance(args, dict):
                args = json.dumps(args, ensure_ascii=False)
            parts.append({"type": "tool-call", "id": tc_id, "name": name, "arguments": args})
        if parts:
            return {"role": "assistant", "content": parts}

    return {"role": role, "content": _to_text_parts(content)}


def build_command_code_payload(body: dict) -> dict:
    model_name = body.get("model", "deepseek-v4-pro")
    target_model = MODEL_MAP.get(model_name, model_name)

    raw_messages = body.get("messages", [])
    # Coalesce consecutive system-role prefixes? Keep simple: sanitize each.
    messages = [sanitize_message(m) if isinstance(m, dict) else m for m in raw_messages]

    return {
        "params": {
            "messages": messages,
            "model": target_model,
            "temperature": body.get("temperature", 0.7),
            "max_tokens": body.get("max_tokens", 4096),
        },
        "config": {
            "workingDir": "/tmp",
            "date": time.strftime("%Y-%m-%d"),
            "environment": "terminal",
            "isGitRepo": False,
            "structure": [],
            "currentBranch": "main",
            "mainBranch": "main",
            "gitStatus": "",
            "recentCommits": [],
        },
        "memory": "",
        "taste": "",
        "skills": None,
        "permissionMode": "standard",
    }


@app.get("/v1/models")
async def list_models():
    models_data = [
        {"id": k, "object": "model", "owned_by": "commandcode"}
        for k in MODEL_MAP.keys()
    ]
    return {"object": "list", "data": models_data}


# ---------------------------------------------------------------------------
# Web search endpoints — mirrors Image 1 panel: API key, Endpoint,
# Max searches per request. Available at both /v1/search and /v1/web/search
# for OpenAI compatibility.
# ---------------------------------------------------------------------------

@app.get("/v1/web/search/config")
@app.get("/v1/search/config")
async def web_search_config():
    """Return current web search provider config (secret-free) to render the panel."""
    api_key_configured = bool(os.getenv("DEEPSEEK_API_KEY", "").strip())
    base_url = os.getenv("DEEPSEEK_SEARCH_BASE_URL", "")
    return {
        "provider": "deepseek-official",
        "description": "The DeepSeek search provider.",
        "apiKeyConfigured": api_key_configured,
        "apiKeyStatus": "Key is configured" if api_key_configured else "No key is configured; search is unavailable until one is.",
        "endpoint": base_url,
        "endpointHint": "Leave blank to use the provider default.",
        "endpointDefault": WEB_SEARCH_DEFAULT_BASE_URL,
        "maxSearchesPerRequest": _resolve_web_search_max_uses(None),
        "maxSearchesPerRequestHint": "How many times one request may search before it must answer.",
    }


async def _handle_web_search(request: Request, authorization: str | None) -> JSONResponse:
    body: dict = {}
    try:
        body = await request.json()
    except Exception:
        body = {}

    # Accept multiple shapes: {query}, {q}, {queries: []}, OpenAI tool style {queries}
    queries: list[str] = []
    if isinstance(body.get("queries"), list):
        queries = [str(q).strip() for q in body["queries"] if str(q).strip()]
    elif isinstance(body.get("query"), str) and body["query"].strip():
        queries = [body["query"].strip()]
    elif isinstance(body.get("q"), str) and body["q"].strip():
        queries = [body["q"].strip()]
    elif isinstance(body.get("text"), str) and body["text"].strip():
        queries = [body["text"].strip()]

    if not queries:
        raise HTTPException(status_code=400, detail="Missing required field: query or queries[] (1+ non-empty strings)")

    # Resolve API key — header Bearer wins for per-request override, else env
    header_key = None
    if authorization and authorization.startswith("Bearer "):
        header_key = authorization.split("Bearer ", 1)[1].strip()
    body_key = body.get("api_key") or body.get("apiKey")
    api_key = _resolve_web_search_api_key(header_key, body_key)
    if not api_key:
        raise HTTPException(
            status_code=503,
            detail='No key is configured; search is unavailable until one is. Set DEEPSEEK_API_KEY env or pass Authorization: Bearer <key> / body.api_key. Stored outside the settings file. Leave blank to keep the current key.',
        )

    base_url = _resolve_web_search_base_url(body.get("endpoint") or body.get("baseURL") or body.get("base_url"))
    try:
        parsed_max_uses = _resolve_web_search_max_uses(body.get("max_searches_per_request") or body.get("maxUses") or body.get("max_uses"))
    except Exception:
        parsed_max_uses = WEB_SEARCH_DEFAULT_MAX_USES

    # Enforce Max searches per request — mirrors panel field
    if len(queries) > parsed_max_uses:
        raise HTTPException(
            status_code=400,
            detail=f"queries must contain at most {parsed_max_uses} queries (Max searches per request)",
        )

    # Also validate URL
    from urllib.parse import urlparse

    parsed = urlparse(base_url)
    if parsed.scheme not in ("http", "https") or not parsed.netloc:
        raise HTTPException(status_code=400, detail=f"Invalid endpoint URL: {base_url}")

    model = (body.get("model") or os.getenv("DEEPSEEK_SEARCH_MODEL") or WEB_SEARCH_DEFAULT_MODEL).strip()
    api_version = (body.get("api_version") or os.getenv("DEEPSEEK_SEARCH_API_VERSION") or WEB_SEARCH_DEFAULT_API_VERSION).strip()
    max_tokens_raw = body.get("max_tokens") or os.getenv("DEEPSEEK_SEARCH_MAX_TOKENS") or WEB_SEARCH_DEFAULT_MAX_TOKENS
    try:
        max_tokens = int(max_tokens_raw)
        if max_tokens < 1:
            max_tokens = WEB_SEARCH_DEFAULT_MAX_TOKENS
    except (ValueError, TypeError):
        max_tokens = WEB_SEARCH_DEFAULT_MAX_TOKENS

    max_results_raw = body.get("max_results") or body.get("maxResults")
    max_results: int | None = None
    if max_results_raw is not None:
        try:
            max_results = int(max_results_raw)
            if max_results < 1:
                max_results = None
        except (ValueError, TypeError):
            max_results = None

    # Execute searches via the harness' inbuilt provider:
    #  1) opencode Go `web search` (OPENCODE_BIN / PATH `opencode`) when installed
    #  2) Command Code inbuilt `ctx.web` search (packages/web/web-search-deepseek via DeepSeekHarness)
    #  3) Anthropic Messages fallback — same wire request the inbuilt DeepSeekSearchProvider sends
    #     (port of provider.ts:mapAnthropicResponse / citationSnippets), used only when
    #     the bundled harness runtime is unavailable.
    results: list[dict] = []
    for q in queries:
        r = await _perform_inbuilt_search(q, api_key, base_url, model, api_version, max_tokens, parsed_max_uses, max_results)
        results.append(r)

    if len(results) == 1:
        merged = results[0]
    else:
        # Merge round-robin, dedupe by url, cap to max_results
        seen: set[str] = set()
        merged_sources: list[dict] = []
        # Determine source ranks for round-robin
        max_rank = max(len(r["sources"]) for r in results) if results else 0
        dropped = False
        for rank in range(max_rank):
            for r in results:
                src = r["sources"][rank] if rank < len(r["sources"]) else None
                if src and src["url"] not in seen:
                    seen.add(src["url"])
                    if max_results is not None and len(merged_sources) >= max_results:
                        dropped = True
                        break
                    merged_sources.append(src)
            if dropped:
                break
        # Truncate if needed after loop
        if max_results is not None and len(merged_sources) > max_results:
            merged_sources = merged_sources[:max_results]
            dropped = True
        contents = []
        for idx, r in enumerate(results):
            c = r.get("content")
            if c:
                contents.append(f"### {queries[idx]}\n\n{c}")
        merged = {
            "sources": merged_sources,
            "truncated": any(r.get("truncated") for r in results) or dropped,
        }
        if contents:
            merged["content"] = "\n\n".join(contents)

    # Apply max_results cap for single-query case as well (seam truncates)
    if max_results is not None and len(merged["sources"]) > max_results:
        merged = {**merged, "sources": merged["sources"][:max_results], "truncated": True}

    # Build response — compatible with both dsh-web and simple {results: []} consumers
    return JSONResponse(
        {
            "object": "web_search_result",
            "provider": "deepseek-official",
            "model": model,
            "endpoint": f"{base_url}/messages",
            "query": queries[0] if len(queries) == 1 else None,
            "queries": queries,
            "max_searches_per_request": parsed_max_uses,
            **merged,
        }
    )


@app.post("/v1/web/search")
@app.post("/v1/search")
async def web_search(request: Request, authorization: str = Header(None)):
    return await _handle_web_search(request, authorization)


@app.post("/v1/chat/completions")
async def chat_completions(
    request: Request, authorization: str = Header(None)
):
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(
            status_code=401,
            detail="Missing or invalid Authorization Bearer header",
        )

    api_key = authorization.split("Bearer ")[1].strip()
    body = await request.json()
    is_stream = body.get("stream", False)
    payload = build_command_code_payload(body)

    upstream_headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
        "x-command-code-version": DEFAULT_CLI_VERSION,
        "Accept": "text/event-stream, application/x-ndjson",
    }

    client = httpx.AsyncClient(timeout=120.0)

    if is_stream:

        async def event_generator():
            try:
                async with client.stream(
                    "POST",
                    COMMAND_CODE_API_URL,
                    json=payload,
                    headers=upstream_headers,
                ) as response:
                    if response.status_code != 200:
                        err_text = await response.aread()
                        yield f"data: {json.dumps({'error': err_text.decode('utf-8', errors='ignore')})}\n\n"
                        return

                    async for line in response.aiter_lines():
                        if not line or not line.strip():
                            continue

                        raw = line.replace("data: ", "").strip()
                        if raw == "[DONE]":
                            yield "data: [DONE]\n\n"
                            break

                        try:
                            event = json.loads(raw)
                            # Handle standard Command Code event types
                            delta_content = event.get("text", "") or event.get(
                                "delta", ""
                            )
                            chunk = {
                                "id": f"chatcmpl-{int(time.time()*1000)}",
                                "object": "chat.completion.chunk",
                                "created": int(time.time()),
                                "model": body.get("model"),
                                "choices": [
                                    {
                                        "index": 0,
                                        "delta": {"content": delta_content},
                                        "finish_reason": (
                                            "stop"
                                            if event.get("type") == "finish"
                                            else None
                                        ),
                                    }
                                ],
                            }
                            yield f"data: {json.dumps(chunk)}\n\n"
                        except json.JSONDecodeError:
                            continue

                    yield "data: [DONE]\n\n"
            finally:
                await client.aclose()

        return StreamingResponse(
            event_generator(), media_type="text/event-stream"
        )

    # Non-streaming request handling
    try:
        response = await client.post(
            COMMAND_CODE_API_URL, json=payload, headers=upstream_headers
        )
        await client.aclose()

        if response.status_code != 200:
            raise HTTPException(
                status_code=response.status_code, detail=response.text
            )

        # Accumulate streaming lines into a single response
        full_text = ""
        for line in response.text.splitlines():
            line = line.replace("data: ", "").strip()
            if line and line != "[DONE]":
                try:
                    data = json.loads(line)
                    full_text += data.get("text", "") or data.get("delta", "")
                except json.JSONDecodeError:
                    pass

        return JSONResponse(
            {
                "id": f"chatcmpl-{int(time.time()*1000)}",
                "object": "chat.completion",
                "created": int(time.time()),
                "model": body.get("model"),
                "choices": [
                    {
                        "index": 0,
                        "message": {"role": "assistant", "content": full_text},
                        "finish_reason": "stop",
                    }
                ],
                "usage": {
                    "prompt_tokens": 0,
                    "completion_tokens": 0,
                    "total_tokens": 0,
                },
            }
        )
    except Exception as e:
        await client.aclose()
        raise HTTPException(status_code=500, detail=str(e))


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="127.0.0.1", port=55990)
