# Baobab iOS — 保單整理原型

SwiftUI iOS 17+ prototype for photographing policy pages, manually confirming policy records, reviewing coverage-record gaps, and estimating a conservative minimum from explicitly verified benefits.

## Three user flows

1. **Photo and policy draft:** take a photo or choose one from Photos; Vision OCR runs on-device. The user reviews the OCR text and manually confirms insurer, product, benefit categories, amounts, clause version, clause reference, and HTTPS source before saving. Raw OCR text and the image are not saved by this prototype.
2. **Coverage review:** compare the user's recorded policies against life, medical, surgery, cancer, accident, disability, long-term-care, and critical-illness categories. An absent record is shown as “not found in the records; confirm whether this is a gap,” not as a definitive finding or recommendation.
3. **Claim estimate:** enter the treatment date, hospital days, and procedure type, then enter and confirm the amount for each policy from its clause/surgery schedule. A policy is included only when its start date is known and it covers the treatment date. Only traceable, user-confirmed fixed benefits are summed. Reimbursement/actual-expense benefits are excluded from the estimate.

Policy records are stored locally in the app's Application Support folder with iOS complete file protection and excluded from device backup. The model intentionally omits policy number, insured name, national ID, address, and source OCR text. This is a prototype storage design, not a security certification.

## Important data limitation

This repository does **not** contain a verified, complete database of all Taiwan insurers' current and discontinued products or their clauses. The official Taiwan Insurance Institute product lookup says its product database began in late 2004 and warns that missing products may be older products or newly sold items not yet submitted by insurers. Records before that period and recent omissions require separate official sourcing and verification.

A separate `Insurance` repository in the same account contains a 3,324-row export spanning only eight life insurers. Those entries have basic names/status/year but no product codes, clause text, clause links, or source lineage. The export is not included as verified production data and must not be used for claim calculations.

## Build

Open `Baobab.xcodeproj` in Xcode 15 or later and run on iOS 17+. The source uses SwiftUI, PhotosUI, UIKit camera picker, and on-device Vision OCR. This coding environment does not include Xcode or an iOS SDK, so a simulator/device build has not been run here.

## Official references

- Taiwan Insurance Institute product database: https://www.tii.org.tw/tii/insurance/insurance4.html
- Taiwan Insurance Bureau public-information portal: https://ins-info.ib.gov.tw/
- Product data schema and verification rules: [`docs/product-data-schema.md`](docs/product-data-schema.md)
