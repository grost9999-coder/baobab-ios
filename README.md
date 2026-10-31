# Baobab iOS — 保單整理與理賠估算

SwiftUI iOS app starter for organizing insurance policies from photos, reviewing coverage gaps, and calculating a conservative minimum from explicitly verified policy benefits.

## Product safety rules

- OCR output is an untrusted draft and requires user confirmation.
- A product is estimate-eligible only when the exact clause version, source URL, and verification date are recorded.
- Unknown, unverified, or ambiguous terms never become a zero-coverage conclusion or a numeric estimate.
- Reimbursement benefits are not added to a minimum estimate without receipts, limits, exclusions, coordination of benefits, and claim review.
- Results are estimates, not an insurer's claim decision or a promise of payment.
- Policy images contain sensitive personal data. Do not upload them to a third party without explicit consent and a documented retention/security design.

## Data coverage and current limitation

The official Taiwan Insurance Institute product lookup says its product database began in late 2004. It warns that missing products may predate the database or may be newly sold products not yet provided by insurers. Therefore 1995–2003 products require insurer/archive sourcing, and every record needs an explicit source and retrieval date.

A separate `Insurance` repository in the same account contains a 3,324-row JSON export with eight life insurers and basic product labels/status/year only. It has no clause text, clause links, product codes, or source lineage. It is not included as verified production data and must not be used to calculate benefits.

## Build

Open `Baobab.xcodeproj` in Xcode 15 or later and run on iOS 17+. The source uses SwiftUI, PhotosUI, and on-device Vision OCR.

## Data model and ingestion contract

See [`docs/product-data-schema.md`](docs/product-data-schema.md). Production ingestion should retain the original document, source URL, retrieval timestamp, insurer, product code, clause version/date, sales start/end dates, review status, and field-level citations. Keep revisions append-only so a policy always resolves against the wording in force when issued.

## Official sources

- Taiwan Insurance Institute product database: https://www.tii.org.tw/tii/insurance/insurance4.html
- Taiwan Insurance Bureau public-information portal: https://ins-info.ib.gov.tw/
- Insurance Bureau portal links consumers to the Insurance Institute's product lookup.
