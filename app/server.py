"""Read-only HTTP service over the detected mutashābihāt.

    python -m app.server                  # http://127.0.0.1:8000
    python -m app.server --port 8080 --cors

Endpoints
    GET /                                 the āyah lookup page
    GET /mushaf                           the muṣḥaf, page by page
    GET /official                         the official mutashābihāt, as forks
    GET /api/mutashabih?surah=2&ayah=25   JSON for one āyah
    GET /api/mutashabih/2/25              same, path form
    GET /api/official?shape=all_but_one   the fork list, filtered and paged
    GET /api/official/7060                one fork in full
    GET /api/page/42                      one printed page, line for line
    GET /api/surahs                       sūrah list with āyah counts
    GET /api/scopes                       which analysis scopes are populated
    GET /api/health                       corpus row counts

Standard library only: the pipeline's dependency list stays as it is, and the
service starts with nothing to install.
"""
from __future__ import annotations

import argparse
import json
import re
import sqlite3
import sys
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

from app import lookup as L
from app.forks_page import html as forks_html
from app.mushaf_page import html as mushaf_html
from app.page import html as lookup_html

VERSE_PATH = re.compile(r"^/api/mutashabih/(\d+)[/:](\d+)$")
PHRASE_PATH = re.compile(r"^/api/(?:official|forks)/(\d+)$")
PAGE_PATH = re.compile(r"^/api/page/(\d+)$")

# Sentinels: the router names a page, the handler renders and caches it.
PAGE_LOOKUP = "page:lookup"
PAGE_FORKS = "page:forks"
PAGE_MUSHAF = "page:mushaf"
PAGES = {PAGE_LOOKUP: lookup_html, PAGE_FORKS: forks_html, PAGE_MUSHAF: mushaf_html}


class BadRequest(ValueError):
    """A parameter the caller can fix."""


def _int_param(query: dict[str, list[str]], name: str, default: int | None) -> int | None:
    raw = query.get(name, [None])[0]
    if raw is None or raw == "":
        return default
    try:
        return int(raw)
    except ValueError:
        raise BadRequest(f"{name} must be an integer, got {raw!r}") from None


def _bool_param(query: dict[str, list[str]], name: str, default: bool) -> bool:
    raw = query.get(name, [None])[0]
    if raw is None or raw == "":
        return default
    return raw.lower() not in {"0", "false", "no", "off"}


def build_response(con: sqlite3.Connection, path: str, query: dict) -> tuple[int, object]:
    """Route one GET. Returns (status, payload); a PAGE payload means HTML."""
    if path in {"/", "/index.html"}:
        return HTTPStatus.OK, PAGE_LOOKUP
    if path in {"/official", "/forks"}:
        return HTTPStatus.OK, PAGE_FORKS
    if path == "/mushaf":
        return HTTPStatus.OK, PAGE_MUSHAF

    matched = PAGE_PATH.match(path)
    if matched or path == "/api/page":
        page = int(matched.group(1)) if matched else _int_param(query, "page", None)
        if page is None:
            raise BadRequest("page is required, e.g. /api/page/42")
        return HTTPStatus.OK, L.mushaf_page(
            con, page, scope=query.get("scope", [L.DEFAULT_SCOPE])[0]
        )

    if path == "/api/official" or path == "/api/forks":
        if not L.has_forks(con):
            return HTTPStatus.SERVICE_UNAVAILABLE, {
                "error": "forks not built; run: python -m pipeline.official --rebuild, "
                "python -m pipeline.pegs --rebuild, python -m pipeline.forks --rebuild"
            }
        try:
            return HTTPStatus.OK, L.fork_index(
                con,
                shape=query.get("shape", [None])[0] or None,
                min_positions=_int_param(query, "min_positions", 2) or 2,
                surah=_int_param(query, "surah", None),
                q=query.get("q", [None])[0] or None,
                sort=query.get("sort", ["useful"])[0] or "useful",
                limit=max(1, min(_int_param(query, "limit", 25) or 25, 200)),
                offset=max(0, _int_param(query, "offset", 0) or 0),
            )
        except ValueError as exc:
            raise BadRequest(str(exc)) from None

    matched = PHRASE_PATH.match(path)
    if matched:
        if not L.has_forks(con):
            return HTTPStatus.SERVICE_UNAVAILABLE, {"error": "forks not built"}
        return HTTPStatus.OK, L.fork_detail(con, int(matched.group(1)))

    if path == "/api/surahs":
        return HTTPStatus.OK, L.surahs(con)

    if path == "/api/scopes":
        return HTTPStatus.OK, L.scopes(con)

    if path == "/api/health":
        counts = {
            table: con.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
            for table in ("words", "ayahs", "surahs", "groups", "occurrences", "dawabit")
        }
        return HTTPStatus.OK, {
            "status": "ok",
            "db": str(L.DB),
            "counts": counts,
            "pages": L.page_count(con),
        }

    surah = ayah = None
    matched = VERSE_PATH.match(path)
    if matched:
        surah, ayah = int(matched.group(1)), int(matched.group(2))
    elif path != "/api/mutashabih":
        return HTTPStatus.NOT_FOUND, {"error": f"no route for {path}"}

    if surah is None:
        surah = _int_param(query, "surah", None)
        ayah = _int_param(query, "ayah", None)
        if surah is None or ayah is None:
            raise BadRequest("surah and ayah are required, e.g. ?surah=2&ayah=25")

    scope = query.get("scope", [L.DEFAULT_SCOPE])[0]
    data = L.lookup(
        con,
        surah,
        ayah,
        scope=scope,
        min_len=_int_param(query, "min_len", 0) or 0,
        min_occurrences=_int_param(query, "min_occurrences", 2) or 2,
        limit=_int_param(query, "limit", L.DEFAULT_LIMIT),
        collapse=_bool_param(query, "collapse", True),
    )
    return HTTPStatus.OK, data


class Handler(BaseHTTPRequestHandler):
    server_version = "quran-msh/1.0"
    con: sqlite3.Connection
    cors: bool = False
    page_cache: dict[str, str] = {}

    # -- plumbing -------------------------------------------------------------

    def _send(self, status: int, body: bytes, content_type: str) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        # The pages are generated per process, not per request; a cached copy in
        # the browser survives a restart of the server and hides the change.
        self.send_header("Cache-Control", "no-store")
        if self.cors:
            self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def _json(self, status: int, payload: object) -> None:
        body = json.dumps(payload, ensure_ascii=False, indent=1).encode("utf-8")
        self._send(status, body, "application/json; charset=utf-8")

    def log_message(self, fmt: str, *args) -> None:
        sys.stderr.write(f"{self.address_string()} {fmt % args}\n")

    # -- routes ---------------------------------------------------------------

    def do_GET(self) -> None:  # noqa: N802 - stdlib naming
        parsed = urlparse(self.path)
        path = parsed.path.rstrip("/") or "/"
        query = parse_qs(parsed.query)

        try:
            status, payload = build_response(type(self).con, path, query)
        except BadRequest as exc:
            self._json(HTTPStatus.BAD_REQUEST, {"error": str(exc)})
            return
        except (L.AyahNotFound, L.PhraseNotFound, L.PageNotFound) as exc:
            self._json(HTTPStatus.NOT_FOUND, {"error": str(exc)})
            return
        except L.LayoutMissing as exc:
            self._json(HTTPStatus.SERVICE_UNAVAILABLE, {"error": str(exc)})
            return
        except sqlite3.Error as exc:
            self._json(HTTPStatus.INTERNAL_SERVER_ERROR, {"error": f"database error: {exc}"})
            return

        if isinstance(payload, str) and payload in PAGES:
            cache = type(self).page_cache
            if payload not in cache:
                cache[payload] = PAGES[payload]()
            self._send(status, cache[payload].encode("utf-8"), "text/html; charset=utf-8")
            return
        self._json(status, payload)

    do_HEAD = do_GET


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8000)
    parser.add_argument("--db", default=str(L.DB))
    parser.add_argument(
        "--cors",
        action="store_true",
        help="send Access-Control-Allow-Origin: * so other local pages can call the API",
    )
    args = parser.parse_args()

    try:
        con = L.connect(Path(args.db))
    except FileNotFoundError as exc:
        sys.exit(str(exc))

    groups = con.execute("SELECT COUNT(*) FROM groups WHERE scope = 'full'").fetchone()[0]
    if not groups:
        print(
            "warning: no groups at scope 'full'; run "
            "`python -m pipeline.pass_a --scope full --rebuild` "
            "then `python -m pipeline.apply_rules --scope full --rebuild`",
            file=sys.stderr,
        )

    Handler.con = con
    Handler.cors = args.cors
    server = ThreadingHTTPServer((args.host, args.port), Handler)
    print(f"serving {args.db} on http://{args.host}:{args.port}  (ctrl-c to stop)")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nstopped")
    finally:
        server.server_close()
        con.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
