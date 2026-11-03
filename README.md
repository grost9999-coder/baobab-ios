# Baobab iOS — 保單整理原型

SwiftUI iOS 17+ prototype for photographing policy pages, manually confirming policy records, reviewing coverage-record gaps, and estimating a conservative minimum from explicitly verified benefits.

## Four user flows

1. **Photo and policy draft:** take a photo or choose one from Photos; Vision OCR runs on-device. The user reviews the OCR text and manually confirms insurer, product, benefit categories, amounts, clause version, clause reference, and HTTPS source before saving. Raw OCR text and the image are not saved by this prototype.
2. **Coverage review:** compare the user's recorded policies against life, medical, surgery, cancer, accident, disability, long-term-care, and critical-illness categories. An absent record is shown as “not found in the records; confirm whether this is a gap,” not as a definitive finding or recommendation.
3. **Claim estimate:** enter the treatment date, hospital days, and procedure type, then enter and confirm the amount for each policy from its clause/surgery schedule. A policy is included only when its start date is known and it covers the treatment date. Only traceable, user-confirmed fixed benefits are summed. Reimbursement/actual-expense benefits are excluded from the estimate.
4. **Product lookup:** search the insurer-index entries and, when rights-cleared product records are bundled, filter on-sale/discontinued products and open the source clause. The current catalog shows zero products rather than inventing records.

Policy records are stored locally in the app's Application Support folder with iOS complete file protection and excluded from device backup. The model intentionally omits policy number, insured name, national ID, address, and source OCR text. This is a prototype storage design, not a security certification.

## Important data limitation

This repository does **not** contain a verified, complete database of all Taiwan insurers' current and discontinued products or their clauses. `Resources/product_catalog.json` contains 61 insurer/company filter entries copied as displayed by the official TII query page, but includes historical, pre-merger and status-unconfirmed entries; it is not a current insurer license roster. It currently contains **0 product records**.

The TII search page supports company/type/product keyword and sales/stop-sale date filters, but presents CAPTCHA and paginated results. We did not find a public bulk export/API or a verified commercial redistribution grant for the TII product documents. The official product database says it began in late 2004 and may omit earlier or newly submitted products. Do not bypass the CAPTCHA, guess private endpoints, or repackage terms without documented rights. Add records only from an authorized, traceable source and verify every clause version.

A separate `Insurance` repository in the same account contains a 3,324-row export spanning only eight life insurers. Those entries have basic names/status/year but no product codes, clause text, clause links, or source lineage. The export is not included as verified production data and must not be used for claim calculations.

## Safe crawler prototype

The read-only crawler checks robots.txt first and stops on CAPTCHA, access interstitials, non-plain robots responses, or HTTP blocking. It does not submit forms, follow redirects, download clause files, or import candidate links as products. Run it with `python3 scripts/crawl_public_catalog_sources.py`; it is source discovery only, not a full-catalog importer. Five safety tests pass with `python3 -m unittest discover -s tests -v`. The first official-source pilot found that some public pages expose only navigation/JavaScript-loaded content, while TII robots.txt and one insurer site's access response require stopping rather than bypassing. See [`docs/crawler-pilot-2026-11-03.md`](docs/crawler-pilot-2026-11-03.md).

## Build

Open `Baobab.xcodeproj` in Xcode 15 or later and run on iOS 17+. The source uses SwiftUI, PhotosUI, UIKit camera picker, and on-device Vision OCR. This coding environment does not include Xcode or an iOS SDK, so a simulator/device build has not been run here.

## Official references

- Taiwan Insurance Institute product database: https://www.tii.org.tw/tii/insurance/insurance4.html
- TII public product query: https://insprod.tii.org.tw/Query.aspx
- Taiwan Insurance Bureau public-information portal: https://ins-info.ib.gov.tw/
- Product data schema and verification rules: [`docs/product-data-schema.md`](docs/product-data-schema.md)
- Three-track data acquisition plan and unsent request drafts: [`docs/data-acquisition-plan-and-requests.md`](docs/data-acquisition-plan-and-requests.md)
- Catalog format checker: `python3 scripts/validate_product_catalog.py`
- Crawler source settings: `Resources/crawl_sources.json`
