import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import validate_product_catalog as validator  # noqa: E402


def catalog(products):
    return {
        "schemaVersion": 1,
        "companies": [{"code": "206", "name": "南山人壽保險股份有限公司", "line": "壽險", "rosterStatus": "x"}],
        "products": products,
        "source": {
            "url": "https://example.org/catalog",
            "rightsStatus": "authorized",
            "rightsEvidenceURL": "https://example.org/license",
            "rightsCheckedOn": "2026-11-13",
        },
    }


def product(**overrides):
    base = {
        "id": "p1", "company": "南山人壽保險股份有限公司", "companyCode": "206", "name": "範例住院醫療附約",
        "line": "壽險", "salesStatus": "停售", "provenance": "test", "dataQuality": "needsReview", "benefits": [],
    }
    base.update(overrides)
    return base


class ValidatorTests(unittest.TestCase):
    def run_validator(self, payload):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "catalog.json"
            path.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
            return validator.validate(path)[1]

    def test_role_and_new_benefit_kinds_are_accepted(self):
        benefits = [
            {"kind": "住院日額", "label": "住院日額", "limitMinNTD": 500, "limitMaxNTD": 5000, "verifiedEligible": False},
            {"kind": "意外身故", "label": "意外身故", "verifiedEligible": False},
            {"kind": "骨折未住院", "label": "骨折未住院", "verifiedEligible": False},
        ]
        self.assertEqual(self.run_validator(catalog([product(role="附約", benefits=benefits)])), [])

    def test_invalid_role_is_rejected(self):
        errors = self.run_validator(catalog([product(role="subsidiary")]))
        self.assertTrue(any("invalid role" in e for e in errors))

    def test_inverted_limit_range_is_rejected(self):
        benefits = [{"kind": "住院日額", "label": "x", "limitMinNTD": 5000, "limitMaxNTD": 500, "verifiedEligible": False}]
        errors = self.run_validator(catalog([product(benefits=benefits)]))
        self.assertTrue(any("exceeds" in e for e in errors))

    def test_products_without_rights_record_are_rejected(self):
        payload = catalog([product()])
        payload["source"].pop("rightsStatus")
        self.assertTrue(self.run_validator(payload))


if __name__ == "__main__":
    unittest.main()
