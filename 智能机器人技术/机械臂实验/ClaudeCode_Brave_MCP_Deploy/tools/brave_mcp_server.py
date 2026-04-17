import json
import os
import subprocess
from typing import Any
from urllib.parse import urlencode
from pathlib import Path

import httpx
from mcp.server.fastmcp import FastMCP


DEFAULT_BRAVE_BASE_URL = "https://api.search.brave.com/res/v1"
PROJECT_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_CONFIG_FILE = PROJECT_ROOT / "brave api.txt"

mcp = FastMCP("brave-search")


def _load_config_file() -> tuple[str, list[str]]:
    config_path = Path(os.environ.get("BRAVE_CONFIG_FILE", str(DEFAULT_CONFIG_FILE)))
    if not config_path.exists():
        return DEFAULT_BRAVE_BASE_URL, []
    lines = [line.strip() for line in config_path.read_text(encoding="utf-8").splitlines() if line.strip()]
    if not lines:
        return DEFAULT_BRAVE_BASE_URL, []
    base_url = lines[0]
    keys = lines[1:]
    return base_url, keys


def _load_brave_credentials() -> tuple[str, list[str]]:
    env_base_url = os.environ.get("BRAVE_BASE_URL")
    env_api_key = os.environ.get("BRAVE_API_KEY")
    file_base_url, file_keys = _load_config_file()

    base_url = env_base_url or file_base_url or DEFAULT_BRAVE_BASE_URL
    keys: list[str] = []
    if env_api_key:
        keys.append(env_api_key)
    keys.extend([key for key in file_keys if key and key not in keys])
    if not keys:
        raise RuntimeError("No Brave API key found. Set BRAVE_API_KEY or provide brave api.txt")
    return base_url, keys


def _http_get_json(url: str, headers: dict[str, str]) -> dict[str, Any]:
    try:
        with httpx.Client(timeout=30.0) as client:
            resp = client.get(url, headers=headers)
            resp.raise_for_status()
            return resp.json()
    except httpx.HTTPStatusError as exc:
        raise RuntimeError(
            f"Brave API HTTP {exc.response.status_code}: {exc.response.text}"
        ) from exc
    except httpx.HTTPError as exc:
        try:
            return _powershell_get_json(url, headers)
        except RuntimeError:
            raise RuntimeError(f"Brave API connection failed: {exc}") from exc


def _powershell_get_json(url: str, headers: dict[str, str]) -> dict[str, Any]:
    env = os.environ.copy()
    env["BRAVE_URL"] = url
    env["BRAVE_HEADER_ACCEPT"] = headers.get("Accept", "application/json")
    env["BRAVE_HEADER_TOKEN"] = headers.get("X-Subscription-Token", "")
    cmd = [
        "powershell",
        "-NoProfile",
        "-Command",
        (
            "$headers = @{ "
            "'Accept' = $env:BRAVE_HEADER_ACCEPT; "
            "'X-Subscription-Token' = $env:BRAVE_HEADER_TOKEN "
            "}; "
            "$resp = Invoke-WebRequest -Uri $env:BRAVE_URL -Headers $headers -Method Get -TimeoutSec 30; "
            "Write-Output $resp.Content"
        ),
    ]
    result = subprocess.run(cmd, capture_output=True, text=True, env=env, timeout=40)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip() or "PowerShell request failed")
    return json.loads(result.stdout)


@mcp.tool()
def brave_web_search(
    query: str,
    count: int = 5,
    country: str = "US",
    search_lang: str = "zh-hans",
) -> dict[str, Any]:
    """Search the web with Brave Search and return concise structured results."""
    base_url, api_keys = _load_brave_credentials()
    params = urlencode(
        {
            "q": query,
            "count": max(1, min(count, 20)),
            "country": country,
            "search_lang": search_lang,
        }
    )
    url = f"{base_url}/web/search?{params}"
    last_error: Exception | None = None
    data: dict[str, Any] | None = None
    for api_key in api_keys:
        try:
            data = _http_get_json(
                url,
                headers={
                    "Accept": "application/json",
                    "X-Subscription-Token": api_key,
                },
            )
            break
        except Exception as exc:
            last_error = exc
            continue
    if data is None:
        raise RuntimeError(f"All Brave API keys failed. Last error: {last_error}")

    results = []
    for item in data.get("web", {}).get("results", []):
        results.append(
            {
                "title": item.get("title", ""),
                "url": item.get("url", ""),
                "description": item.get("description", ""),
                "age": item.get("age", ""),
                "language": item.get("language", ""),
            }
        )

    return {
        "query": query,
        "count": len(results),
        "results": results,
    }


if __name__ == "__main__":
    mcp.run()
