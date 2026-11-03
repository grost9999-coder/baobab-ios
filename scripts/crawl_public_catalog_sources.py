#!/usr/bin/env python3
"""Low-rate public-page discovery only; never submits forms or downloads clause files."""
import argparse
import hashlib
import json
import re
import sys
import time
from datetime import datetime, timezone
from html.parser import HTMLParser
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import urljoin, urlparse
from urllib.request import HTTPRedirectHandler, Request, build_opener
from urllib.robotparser import RobotFileParser

BLOCKED_STATUS = {401, 403, 429, 503}
CHALLENGE_RE = re.compile(r"captcha|recaptcha|驗證碼|人機驗證|請輸入驗證", re.IGNORECASE)
ACCESS_BLOCK_RE = re.compile(r"網站存取異常|存取異常|拒絕存取|禁止存取|access denied|request blocked|access forbidden|security check", re.IGNORECASE)
SENSITIVE_PATH_RE = re.compile(r"login|sign.?in|member|account|kyc|admin|checkout", re.IGNORECASE)
DOCUMENT_SUFFIXES = (".pdf", ".doc", ".docx", ".xls", ".xlsx", ".zip")


class PublicPageParser(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.title_parts = []
        self.in_title = False
        self.links = []
        self._anchor = None
        self._anchor_parts = []
        self._meta = []
        self._canonical = None

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag.lower() == "title":
            self.in_title = True
        elif tag.lower() == "meta":
            name = (attrs.get("name") or attrs.get("property") or "").lower()
            content = attrs.get("content") or ""
            if name in {"description", "og:title", "og:description"} and content:
                self._meta.append({"name": name, "content": content.strip()[:500]})
        elif tag.lower() == "link" and "canonical" in (attrs.get("rel") or "").lower():
            self._canonical = attrs.get("href")
        elif tag.lower() == "a" and attrs.get("href"):
            self._anchor = attrs.get("href")
            self._anchor_parts = []
            self._anchor_title = attrs.get("title") or attrs.get("aria-label") or ""

    def handle_endtag(self, tag):
        if tag.lower() == "title":
            self.in_title = False
        elif tag.lower() == "a" and self._anchor is not None:
            text = " ".join(" ".join(self._anchor_parts).split())
            self.links.append({
                "href": self._anchor,
                "text": (text or self._anchor_title).strip()[:500],
            })
            self._anchor = None
            self._anchor_parts = []

    def handle_data(self, data):
        if self.in_title:
            self.title_parts.append(data)
        if self._anchor is not None:
            self._anchor_parts.append(data)

    @property
    def title(self):
        return " ".join(" ".join(self.title_parts).split())[:500]


def iso_now():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def digest(text):
    return hashlib.sha256(text.encode("utf-8", errors="replace")).hexdigest()


class _NoRedirectHandler(HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, message, headers, new_url):
        return None


class SafeCrawler:
    def __init__(self, config, output):
        self.config = config
        self.output = output
        self.user_agent = config.get("userAgent", "BaobabPublicCatalogResearch/1.0")
        self.delay = max(float(config.get("minDelaySeconds", 3)), 3.0)
        self.max_html_bytes = min(int(config.get("maxHtmlBytes", 3_000_000)), 3_000_000)
        self.last_request_by_host = {}
        self.robots_cache = {}
        self.host_delays = {}
        self.records = []
        self.blocked_hosts = set()
        self.opener = build_opener(_NoRedirectHandler())

    def _wait(self, host, extra_delay=0):
        now = time.monotonic()
        previous = self.last_request_by_host.get(host)
        wait_for = max(self.delay, self.host_delays.get(host, 0), extra_delay)
        if previous is not None and now - previous < wait_for:
            time.sleep(wait_for - (now - previous))

    def _open(self, url, max_bytes):
        host = urlparse(url).netloc.lower()
        self._wait(host)
        request = Request(url, headers={
            "User-Agent": self.user_agent,
            "Accept": "text/html,application/xhtml+xml,text/plain;q=0.8,*/*;q=0.1",
        })
        try:
            with self.opener.open(request, timeout=15) as response:
                self.last_request_by_host[host] = time.monotonic()
                status = response.getcode()
                content_type = response.headers.get("Content-Type", "").lower()
                body = response.read(max_bytes + 1)
                if len(body) > max_bytes:
                    return status, response.geturl(), content_type, None, "response_too_large"
                return status, response.geturl(), content_type, body, None
        except HTTPError as exc:
            self.last_request_by_host[host] = time.monotonic()
            return exc.code, url, "", None, f"http_{exc.code}"
        except (URLError, TimeoutError, OSError) as exc:
            self.last_request_by_host[host] = time.monotonic()
            return None, url, "", None, f"network_error:{type(exc).__name__}"

    def _robots(self, origin):
        if origin in self.robots_cache:
            return self.robots_cache[origin]
        robots_url = origin + "/robots.txt"
        status, final_url, content_type, body, error = self._open(robots_url, 512_000)
        if status != 200 or body is None:
            result = (None, None, f"robots_unavailable:{error or status}")
            self.robots_cache[origin] = result
            return result
        text = body.decode("utf-8", errors="replace")
        if "text/plain" not in content_type or ACCESS_BLOCK_RE.search(text):
            result = (None, None, "robots_not_plain_text_or_interstitial")
            self.robots_cache[origin] = result
            return result
        parser = RobotFileParser()
        parser.set_url(robots_url)
        parser.parse(text.splitlines())
        crawl_delay = parser.crawl_delay(self.user_agent) or parser.crawl_delay("*") or 0
        self.host_delays[urlparse(origin).netloc.lower()] = max(float(crawl_delay), self.delay)
        result = (parser, self.host_delays[urlparse(origin).netloc.lower()], None)
        self.robots_cache[origin] = result
        return result

    @staticmethod
    def _origin(url):
        parsed = urlparse(url)
        if parsed.scheme not in {"http", "https"} or not parsed.netloc:
            return None
        return f"{parsed.scheme}://{parsed.netloc}"

    def _record_blocked(self, seed, reason, url=None):
        self.records.append({
            "sourceId": seed.get("sourceId"),
            "companyCode": seed.get("companyCode"),
            "companyName": seed.get("companyName"),
            "seedURL": seed.get("url"),
            "pageURL": url or seed.get("url"),
            "crawlStatus": "stopped",
            "stopReason": reason,
            "fetchedAt": iso_now(),
            "contentStored": False,
            "clauseFilesDownloaded": False,
        })

    def _is_document(self, url, text):
        path = urlparse(url).path.lower()
        return path.endswith(DOCUMENT_SUFFIXES) or "pdf" in (text or "").lower()

    def _allowed_follow(self, seed, current_url, candidate_url):
        current_host = urlparse(current_url).netloc.lower()
        parsed = urlparse(candidate_url)
        if parsed.scheme not in {"http", "https"} or parsed.netloc.lower() != current_host:
            return False
        if parsed.query or parsed.fragment or SENSITIVE_PATH_RE.search(parsed.path):
            return False
        prefixes = seed.get("sameHostPathPrefixes", [])
        if prefixes and not any(parsed.path.startswith(prefix) for prefix in prefixes):
            return False
        if self._is_document(candidate_url, ""):
            return False
        return True

    def crawl_seed(self, seed):
        seed_url = seed["url"]
        origin = self._origin(seed_url)
        if origin is None:
            self._record_blocked(seed, "invalid_seed_url")
            return
        host = urlparse(seed_url).netloc.lower()
        if host in self.blocked_hosts:
            self._record_blocked(seed, "host_already_blocked")
            return
        robots, delay, robots_error = self._robots(origin)
        if robots_error:
            self.blocked_hosts.add(host)
            self._record_blocked(seed, robots_error)
            return
        if not robots.can_fetch(self.user_agent, seed_url):
            self._record_blocked(seed, "robots_disallow_seed")
            return

        queue = [(seed_url, 0)]
        visited = set()
        max_pages = max(1, min(int(seed.get("maxPages", 1)), 10))
        prefixes = seed.get("sameHostPathPrefixes", [])
        while queue and len(visited) < max_pages:
            page_url, depth = queue.pop(0)
            if page_url in visited:
                continue
            visited.add(page_url)
            if host in self.blocked_hosts:
                break
            if not robots.can_fetch(self.user_agent, page_url):
                self._record_blocked(seed, "robots_disallow_link", page_url)
                continue
            status, final_url, content_type, body, error = self._open(page_url, self.max_html_bytes)
            if status in BLOCKED_STATUS or status is None or body is None:
                reason = f"access_block_or_error:{error or status}"
                self._record_blocked(seed, reason, page_url)
                self.blocked_hosts.add(host)
                break
            if status < 200 or status >= 300:
                self._record_blocked(seed, f"http_status_{status}", page_url)
                continue
            if "html" not in content_type and "xhtml" not in content_type:
                self._record_blocked(seed, f"not_html:{content_type}", page_url)
                continue
            html = body.decode("utf-8", errors="replace")
            if CHALLENGE_RE.search(html):
                self._record_blocked(seed, "captcha_or_human_challenge_detected_no_submission", page_url)
                self.blocked_hosts.add(host)
                break
            if ACCESS_BLOCK_RE.search(html):
                self._record_blocked(seed, "access_interstitial_detected", page_url)
                self.blocked_hosts.add(host)
                break

            parser = PublicPageParser()
            try:
                parser.feed(html)
            except Exception:
                self._record_blocked(seed, "html_parse_error", page_url)
                continue

            links = []
            for link in parser.links:
                absolute = urljoin(final_url, link["href"])
                if urlparse(absolute).scheme not in {"http", "https"}:
                    continue
                if SENSITIVE_PATH_RE.search(urlparse(absolute).path):
                    continue
                kind = "document_link" if self._is_document(absolute, link["text"]) else "page_link"
                item = {
                    "url": absolute,
                    "label": link["text"],
                    "kind": kind,
                    "sameHost": urlparse(absolute).netloc.lower() == host,
                }
                links.append(item)
                if depth == 0 and kind == "page_link" and len(queue) < max_pages:
                    if self._allowed_follow(seed, final_url, absolute):
                        queue.append((absolute, depth + 1))

            self.records.append({
                "sourceId": seed.get("sourceId"),
                "companyCode": seed.get("companyCode"),
                "companyName": seed.get("companyName"),
                "line": seed.get("line"),
                "sourceMode": seed.get("sourceMode"),
                "historicalCandidate": bool(seed.get("historicalCandidate", False)),
                "seedURL": seed_url,
                "pageURL": final_url,
                "crawlStatus": "metadata_discovered",
                "httpStatus": status,
                "pageTitle": parser.title,
                "canonicalURL": urljoin(final_url, parser._canonical) if parser._canonical else None,
                "meta": parser._meta,
                "links": links,
                "htmlSHA256": digest(html),
                "fetchedAt": iso_now(),
                "robotsURL": origin + "/robots.txt",
                "robotsAllowed": True,
                "crawlDelaySeconds": delay,
                "contentStored": False,
                "clauseFilesDownloaded": False,
                "usageNote": "Candidate metadata only; human review required. No clause content was copied or evaluated.",
            })

    def run(self):
        for seed in self.config.get("seeds", []):
            self.crawl_seed(seed)
        self.output.parent.mkdir(parents=True, exist_ok=True)
        payload = {
            "schemaVersion": 1,
            "runAt": iso_now(),
            "mode": "public_metadata_discovery_only",
            "policy": {
                "robotsRequired": True,
                "minimumDelaySeconds": self.delay,
                "submitsForms": False,
                "bypassesCaptcha": False,
                "downloadsDocuments": False,
                "copiesClauseText": False,
                "importsProductsAutomatically": False,
            },
            "records": self.records,
        }
        temporary = self.output.with_suffix(self.output.suffix + ".tmp")
        temporary.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        temporary.replace(self.output)
        stopped = sum(1 for item in self.records if item.get("crawlStatus") == "stopped")
        discovered = sum(1 for item in self.records if item.get("crawlStatus") == "metadata_discovered")
        print(f"Source pages discovered: {discovered}; stopped/skipped: {stopped}; output: {self.output}")
        print("This is metadata discovery only; it does not create verified product records or download clause files.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", default="Resources/crawl_sources.json")
    parser.add_argument("--output", default="data/crawl_discovery.json")
    args = parser.parse_args()
    config_path = Path(args.config)
    if not config_path.exists():
        print(f"Source config not found: {config_path}", file=sys.stderr)
        return 2
    config = json.loads(config_path.read_text(encoding="utf-8"))
    SafeCrawler(config, Path(args.output)).run()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
