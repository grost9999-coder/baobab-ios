import importlib.util
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "crawl_public_catalog_sources.py"
SPEC = importlib.util.spec_from_file_location("safe_crawler", SCRIPT)
module = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(module)


class FakeCrawler(module.SafeCrawler):
    def __init__(self, page_body, robots_status=200, robots_content_type="text/plain"):
        super().__init__({"userAgent": "UnitTestCrawler", "minDelaySeconds": 0.01, "maxHtmlBytes": 100000}, Path("/tmp/unused-crawler-test.json"))
        self.page_body = page_body
        self.robots_status = robots_status
        self.robots_content_type = robots_content_type
        self.requested = []

    def _open(self, url, max_bytes):
        self.requested.append(url)
        if url.endswith("/robots.txt"):
            if self.robots_status != 200:
                return self.robots_status, url, "", None, f"http_{self.robots_status}"
            return 200, url, self.robots_content_type, b"User-agent: *\nAllow: /\n", None
        return 200, url, "text/html; charset=utf-8", self.page_body, None


class CrawlerSafetyTests(unittest.TestCase):
    def make_seed(self):
        return {
            "sourceId": "test",
            "companyCode": "101",
            "companyName": "測試公司",
            "sourceMode": "test",
            "url": "https://example.invalid/products",
            "sameHostPathPrefixes": ["/products"],
            "maxPages": 1,
            "historicalCandidate": False,
        }

    def test_robots_unavailable_is_fail_closed(self):
        crawler = FakeCrawler(b"<html><title>Should not fetch</title></html>", robots_status=404)
        crawler.crawl_seed(self.make_seed())
        self.assertEqual(len(crawler.requested), 1)
        self.assertTrue(crawler.requested[0].endswith("/robots.txt"))
        self.assertEqual(crawler.records[0]["crawlStatus"], "stopped")
        self.assertIn("robots_unavailable", crawler.records[0]["stopReason"])

    def test_html_interstitial_is_not_accepted_as_robots_txt(self):
        crawler = FakeCrawler(b"<html><title>Access denied</title></html>", robots_content_type="text/html")
        crawler.crawl_seed(self.make_seed())
        self.assertEqual(len(crawler.requested), 1)
        self.assertEqual(crawler.records[0]["crawlStatus"], "stopped")
        self.assertEqual(crawler.records[0]["stopReason"], "robots_not_plain_text_or_interstitial")

    def test_captcha_stops_without_following_or_submitting(self):
        body = '<html><body><h1>圖形驗證碼</h1><a href="/products/next">Next</a></body></html>'.encode("utf-8")
        crawler = FakeCrawler(body)
        crawler.crawl_seed(self.make_seed())
        self.assertEqual(len(crawler.requested), 2)  # robots plus one public page
        self.assertEqual(crawler.records[0]["crawlStatus"], "stopped")
        self.assertIn("captcha_or_human_challenge", crawler.records[0]["stopReason"])

    def test_pdf_is_listed_as_link_but_never_downloaded(self):
        body = b'<html><title>Terms</title><a href="/files/clause.pdf">Clause PDF</a></html>'
        crawler = FakeCrawler(body)
        crawler.crawl_seed(self.make_seed())
        self.assertEqual(crawler.records[0]["crawlStatus"], "metadata_discovered")
        pdf_links = [link for link in crawler.records[0]["links"] if link["kind"] == "document_link"]
        self.assertEqual(len(pdf_links), 1)
        self.assertFalse(any(url.endswith("clause.pdf") for url in crawler.requested))
        self.assertFalse(crawler.records[0]["clauseFilesDownloaded"])

    def test_access_interstitial_does_not_become_a_candidate(self):
        body = "<html><title>網站存取異常</title></html>".encode("utf-8")
        crawler = FakeCrawler(body)
        crawler.crawl_seed(self.make_seed())
        self.assertEqual(crawler.records[0]["crawlStatus"], "stopped")
        self.assertEqual(crawler.records[0]["stopReason"], "access_interstitial_detected")


if __name__ == "__main__":
    unittest.main()
