#!/usr/bin/env python3
"""Validate Baobab's provenance-first product catalog JSON before bundling it into iOS."""
import json
import sys
from datetime import datetime
from pathlib import Path
from urllib.parse import urlparse

ALLOWED_STATUS = {"現售", "停售", "未確認"}
ALLOWED_QUALITY = {"verified", "needsReview", "demo", "unavailable"}
ALLOWED_ROLES = {"主約", "附約", "未確認"}
ALLOWED_BENEFIT_KINDS = {
    "住院日額", "手術定額", "手術表定額", "門診手術", "實支實付",
    "一般身故", "意外身故", "意外住院日額", "骨折未住院", "其他",
}
REQUIRED_PRODUCT_KEYS = {
    "id", "company", "companyCode", "name", "line", "salesStatus", "provenance", "dataQuality", "benefits"
}


def is_https(value):
    return isinstance(value, str) and urlparse(value).scheme == "https" and bool(urlparse(value).netloc)


def validate(path: Path):
    payload = json.loads(path.read_text(encoding="utf-8"))
    errors = []
    if payload.get("schemaVersion") != 1:
        errors.append("schemaVersion must be 1")
    companies = payload.get("companies")
    products = payload.get("products")
    if not isinstance(companies, list) or not isinstance(products, list):
        raise ValueError("companies and products must be arrays")
    company_codes = set()
    for company in companies:
        code = str(company.get("code", ""))
        if not code or not company.get("name"):
            errors.append(f"company row missing code/name: {company}")
        if code in company_codes:
            errors.append(f"duplicate company code: {code}")
        company_codes.add(code)

    product_ids = set()
    for index, product in enumerate(products):
        prefix = f"products[{index}]"
        missing = REQUIRED_PRODUCT_KEYS - product.keys()
        if missing:
            errors.append(f"{prefix} missing keys: {sorted(missing)}")
            continue
        if product["id"] in product_ids:
            errors.append(f"{prefix} duplicate id: {product['id']}")
        product_ids.add(product["id"])
        if str(product["companyCode"]) not in company_codes:
            errors.append(f"{prefix} references unknown companyCode {product['companyCode']}")
        if product.get("role") is not None and product["role"] not in ALLOWED_ROLES:
            errors.append(f"{prefix} invalid role {product['role']}")
        if product["salesStatus"] not in ALLOWED_STATUS:
            errors.append(f"{prefix} invalid salesStatus {product['salesStatus']}")
        if product["dataQuality"] not in ALLOWED_QUALITY:
            errors.append(f"{prefix} invalid dataQuality {product['dataQuality']}")
        if not isinstance(product["benefits"], list):
            errors.append(f"{prefix}.benefits must be an array")
        else:
            for bindex, benefit in enumerate(product["benefits"]):
                if benefit.get("kind") not in ALLOWED_BENEFIT_KINDS:
                    errors.append(f"{prefix}.benefits[{bindex}] invalid kind")
                low, high = benefit.get("limitMinNTD"), benefit.get("limitMaxNTD")
                for key, value in (("limitMinNTD", low), ("limitMaxNTD", high)):
                    if value is not None and (not isinstance(value, int) or isinstance(value, bool) or value <= 0):
                        errors.append(f"{prefix}.benefits[{bindex}].{key} must be a positive integer")
                if isinstance(low, int) and isinstance(high, int) and low > high:
                    errors.append(f"{prefix}.benefits[{bindex}] limitMinNTD exceeds limitMaxNTD")
                if benefit.get("verifiedEligible") and product["dataQuality"] != "verified":
                    errors.append(f"{prefix}.benefits[{bindex}] verifiedEligible requires dataQuality=verified")
        if product["dataQuality"] == "verified":
            for key in ("clauseVersion", "clauseVerifiedAt", "sourceURL", "sourceRetrievedAt"):
                if not product.get(key):
                    errors.append(f"{prefix} verified record requires {key}")
            if not is_https(product.get("clauseURL")):
                errors.append(f"{prefix} verified record requires an HTTPS clauseURL")
            if not is_https(product.get("sourceURL")):
                errors.append(f"{prefix} verified record requires an HTTPS sourceURL")
        for key in ("effectiveFrom", "salesEnd", "clauseVerifiedAt", "sourceRetrievedAt"):
            value = product.get(key)
            if value:
                try:
                    datetime.fromisoformat(value.replace("Z", "+00:00"))
                except (AttributeError, ValueError):
                    errors.append(f"{prefix}.{key} must be an ISO-8601 datetime")

    source = payload.get("source", {})
    if products and not source.get("url"):
        errors.append("non-empty product catalog requires source.url")
    if products and not source.get("rightsStatus"):
        errors.append("non-empty product catalog requires source.rightsStatus")
    if products and source.get("rightsStatus") not in {"authorized", "public_open_license", "index_links_only"}:
        errors.append("product records cannot be bundled until redistribution rights are recorded")
    if products and source.get("rightsStatus") == "index_links_only":
        # 索引模式：只收商品名稱、銷售期間與連到公司官網的連結，不收條款全文或給付內容。
        for index, product in enumerate(products):
            prefix = f"products[{index}]"
            if product.get("benefits"):
                errors.append(f"{prefix} index_links_only catalogs must not carry benefit details")
            if product.get("dataQuality") == "verified":
                errors.append(f"{prefix} index_links_only records cannot be dataQuality=verified")
            if not is_https(product.get("sourceURL")):
                errors.append(f"{prefix} index_links_only records require an HTTPS sourceURL to the official page")
    if products and not is_https(source.get("rightsEvidenceURL")):
        errors.append("non-empty product catalog requires HTTPS rightsEvidenceURL")
    if products and not source.get("rightsCheckedOn"):
        errors.append("non-empty product catalog requires rightsCheckedOn")

    return payload, errors


def main():
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("Resources/product_catalog.json")
    try:
        payload, errors = validate(path)
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2
    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1
    print(f"Valid catalog: {len(payload['companies'])} company index rows; {len(payload['products'])} products")
    print("Note: validation checks format/provenance fields; it does not verify coverage or legal rights independently.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
