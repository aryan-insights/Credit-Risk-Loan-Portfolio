# Credit Risk & Loan Portfolio Dashboard

An end-to-end credit risk analysis project simulating the role of a Risk/Portfolio Analytics team at a bank or NBFC — segmenting a loan portfolio by risk, identifying which borrower characteristics drive default, and delivering a dashboard a portfolio manager could use to monitor exposure and prioritize underwriting criteria.

---

## 1. Business Problem

Every lender has to answer one core question: **who gets a loan, and how risky is it if we say yes?**

This project simulates that decision using real, anonymized loan application data. Rather than building a black-box prediction model, the focus is on **explainable risk segmentation** — identifying which borrower characteristics are associated with higher default rates, quantifying how strong each signal is, and translating that into concrete underwriting recommendations.

---

## 2. Tech Stack

| Layer | Tool |
|---|---|
| Database | PostgreSQL |
| Data Cleaning & Transformation | SQL |
| Analysis | SQL (window functions, CTEs, conditional aggregation) |
| Dashboard | Power BI (DAX measures, calculated columns) |

---

## 3. Dataset

**Source:** [Home Credit Default Risk](https://www.kaggle.com/competitions/home-credit-default-risk/data) (Kaggle) — real, anonymized loan application data from an actual lending competition. Of the many files in this competition, this project uses only two:

Two files were used:

| File | Rows | Description |
|---|---|---|
| `application_train.csv` | 307,511 | One row per loan application — demographics, income, employment, loan details, and the outcome (`TARGET`: did they default) |
| `bureau.csv` | ~1.7M | Each applicant's credit history with *other* lenders, reported by an external credit bureau. Many rows per applicant. |

The two tables join on `SK_ID_CURR` (applicant ID).

Out of 122 raw columns in `application_train.csv`, the project deliberately kept ~26 — demographics, income, employment, loan terms, housing, and external credit scores — and excluded columns with no real risk relevance (document-submission flags, building/apartment metadata, region-mismatch flags). This was a judgment call made explicit in the pipeline rather than left implicit.

---

## 4. Data Pipeline

The project follows a **raw → clean** two-layer pattern, standard practice for keeping original data intact while iterating on transformation logic. All of it lives in a single script, [`01_Database.sql`](./01_Database.sql), structured in three parts:

1. **`raw_applicants`, `raw_bureau`** — mirror the source CSVs exactly (all columns, loose `TEXT` types), loaded via PostgreSQL import.
2. **`applicants`, `bureau_history`** — built via `CREATE TABLE ... AS SELECT`, applying type casting, unit conversion, and the cleaning rules below.
3. **`bureau_summary`** — a `VIEW` aggregating `bureau_history` down to one row per applicant (credit line count, total external debt, worst overdue history), enabling a clean join back to `applicants` for both SQL analysis and the Power BI relationship model.

### Data Cleaning Decisions

| Issue | Fix | Reasoning |
|---|---|---|
| `DAYS_BIRTH`, `DAYS_EMPLOYED`, `DAYS_CREDIT`, etc. stored as negative day counts | Converted to positive years via `ABS(x)/365` | These are negative by design (days before application date) — sign-flipping makes them human-readable |
| `DAYS_EMPLOYED` placeholder bug (`365243` = ~1,000 years, used for unemployed/retired applicants) | Converted to `NULL` before sign-flipping | Prevents an impossible tenure value from corrupting averages |
| `DAYS_CREDIT_ENDDATE` (can be positive *or* negative — future or past end date) | Sign preserved, only unit-converted to years | Unlike other DAYS columns, the sign here carries real meaning (loan still active vs. already ended) |
| Negative `AMT_CREDIT_SUM_DEBT` (a data entry error — debt can't be negative) | Floored to `0` via `GREATEST(x, 0)` | Treated as a data quality issue, not a sign convention |
| Blank/empty string values in numeric columns | Converted via `NULLIF(x, '')` before casting | Postgres cannot cast an empty string directly to a numeric type |
| Missing `occupation_type` (31.3% of applicants) | Labeled `'Unknown'` | Frequent enough to be a real analytical category, not noise |
| Missing `ext_source_1/2/3`, `years_since_credit_closed`, `credit_sum_limit` | Left as `NULL` | These are *structurally* missing (e.g., a credit card limit doesn't exist for a mortgage) — filling them would misrepresent the data |

---

## 5. SQL Analysis — Key Findings

Ten queries tested whether default rate varies by different borrower and credit-history characteristics. Each finding below includes sample size context, since small segments were explicitly flagged rather than reported as reliable.

### Ranked by strength of signal (highest-risk bracket ÷ lowest-risk bracket)

| Rank | Factor | Spread | Headline Finding |
|---|---|---|---|
| 1 | External credit score (`ext_source_2`) | **10.7x** | Default rate falls from 18.84% (lowest score band) to 1.76% (highest), perfectly monotonic across all 5 bands. By far the strongest predictor tested. |
| 2 | Education | 4.9x | Academic degree holders default at 1.83% vs. 8.94% for Secondary education — though the top band has only 164 applicants, so this exact figure is directional. |
| 3 | Age | 3.3x | Perfectly monotonic: 12.36% (Under 25) down to 3.79% (65+). Every bracket has 8,000+ applicants — fully reliable. |
| 4 | Overdue payment history | 2.0x | Applicants with a prior overdue elsewhere default at 15.90% vs. 7.99% for those without — one of the most intuitive, high-confidence findings, though it applies to only ~1.1% of applicants. |
| 5 | Housing type | 1.9x | Renters (12.31%) and those living with parents (11.70%) default notably more than homeowners (7.80%). |
| 6 | Family status | 1.7x | Widowed applicants default least (5.82%), Civil-marriage/Single applicants highest (~9.9%) — likely intertwined with the age effect. |
| 7 | Number of external credit lines | 1.4x (non-linear) | Not a straight line — a U-shape. Zero credit history (10.12%) and 10+ lines (8.18%) are both riskier than a moderate 3–5 lines (7.40%), suggesting both "no track record" and "overextended" are risk signals. |
| 8 | Total external debt | 1.25x | A mild, consistent upward trend (7.27% → 9.09%) — real, but the weakest signal tested. |

### Combined risk finding (two factors together)

Applicants who fall into **both** the lowest external credit score band **and** have prior overdue history make up just **0.13% of the portfolio (394 applicants)**, but default at **29.95%** — nearly **4x the portfolio-wide baseline of 8.07%**. This shows portfolio risk is not evenly distributed — it's concentrated in a small, identifiable segment that could be flagged for automatic manual review, independent of any single factor alone.

*(Note: with n=394, this exact percentage carries more statistical noise than the larger single-factor findings above — the direction and scale of the effect are reliable, the precise decimal is not.)*

### Full query log

All 10 underlying queries, their SQL, and per-query findings are documented with inline comments in [`02_Analysis.sql`](./02_Analysis.sql).

---

## 6. Power BI Dashboard

Three pages, each with a distinct purpose:

### Page 1 — Portfolio Overview
*"How big is this loan book, and what's it made of?"*
- KPI cards: Total Applicants (307,511), Default Rate (8.07%), Total Exposure, Defaulted Exposure (with % of total shown as a subtitle), Average Credit-to-Income Ratio (4.0x, median 3.27x — flagged as right-skewed, pulled up by a tail of high-multiple borrowers)
- Applicant volume by income type and contract type (Cash vs. Revolving loans)

### Page 2 — Risk Deep-Dive
*"Which specific groups default more, and by how much?"*
- Default rate by external credit score band
- Default rate by age bracket
- Default rate by overdue payment history
- Default rate by housing type

### Page 3 — Risk Drivers Ranked
*"Out of everything tested, what matters most — and what should we do about it?"*
- Horizontal bar chart ranking all 8 factors by spread (external credit score at the top, total external debt at the bottom)
- Combined high-risk segment callout (0.13% of applicants, 29.95% default rate)
- Written recommendations for a portfolio/risk team

Dashboard screenshots (`page1_portfolio_overview.png`, `page2_risk_deep_dive.png`, `page3_risk_drivers_ranked.png`) are included in this repo. The live `.pbix` file is too large for GitHub's browser upload and is hosted externally: **[Download Portfolio_Overview.pbix (Google Drive)](https://drive.google.com/file/d/168hx1WrxrIhwezvyd3VDz3oE-sbRyIKC/view?usp=sharing)** — open it in Power BI Desktop to interact with the report directly.

---

## 7. Key Recommendations

1. **Prioritize external credit score as the primary underwriting signal** — it outperforms every demographic factor tested by a wide margin.
2. **Flag applicants with prior overdue payment history for manual review** — they default at nearly 2x the base rate.
3. **Apply modestly tighter scrutiny to applicants under 25** — default rate is 3x higher than the 65+ segment.
4. **Treat both zero credit history and 10+ existing credit lines as caution flags** — risk isn't purely linear with credit line count; both extremes carry elevated risk.
5. **Build an automatic review trigger for the combined low-score + overdue-history segment** — though small (0.13% of applicants), this group defaults at nearly 4x the portfolio average.

---

## 8. Repository Structure

```
├── 01_Database.sql                  # Raw table creation, load, and cleaning logic (raw → clean tables + bureau_summary view)
├── 02_Analysis.sql                  # 10 analysis queries with inline findings as comments
├── page1_portfolio_overview.png     # Dashboard screenshot — Portfolio Overview
├── page2_risk_deep_dive.png         # Dashboard screenshot — Risk Deep-Dive
├── page3_risk_drivers_ranked.png    # Dashboard screenshot — Risk Drivers Ranked
└── README.md
```

> **Power BI file:** `Portfolio_Overview.pbix` is too large for GitHub's web upload and isn't stored in this repo — [download it from Google Drive here](https://drive.google.com/file/d/168hx1WrxrIhwezvyd3VDz3oE-sbRyIKC/view?usp=sharing) to open the live, interactive report in Power BI Desktop.

> **Dataset:** Raw source files aren't included in this repo due to size. Download them from the [Home Credit Default Risk competition page on Kaggle](https://www.kaggle.com/competitions/home-credit-default-risk/data) — this project uses only two files from that competition: **`application_train.csv`** and **`bureau.csv`**. Load both into PostgreSQL before running `01_Database.sql`.

---

## 9. Limitations & Honest Caveats

- This is a **static snapshot**, not a time series — there is no trend/seasonality analysis, by design (the dataset doesn't support one).
- Several segment-level findings (e.g., Academic Degree education, Maternity Leave/Unemployed/Student income types) are based on very small sample sizes and are reported as directional only, not headline conclusions.
- The combined high-risk segment (n=394) is a strong directional finding but carries more statistical uncertainty than the larger single-factor results.
- No predictive model was built — this project is intentionally focused on **explainable segmentation** over black-box prediction, in line with how early-stage risk analysis is typically done before a scoring model is introduced.
