-- CHECKING THE TABLES 
SELECT * FROM applicants
SELECT * FROM bureau_history

-- Default rate = out of everyone in a group, what percentage actually failed to repay their loan (had payment difficulty).
-- It's just: defaults ÷ total people in that group × 100. So a default rate of 9.59% for "Working" means: out of every 100 working applicants, about 9-10 of them ran into serious repayment trouble.

-- Q1: Does default rate vary by income bracket?
SELECT
    CASE
        WHEN income_total < 100000 THEN 'Under 100K'
        WHEN income_total < 200000 THEN '100K - 200K'
        WHEN income_total < 300000 THEN '200K - 300K'
        WHEN income_total < 500000 THEN '300K - 500K'
        ELSE '500K+'
    END AS income_bracket,
    COUNT(*) AS total_applicants,
    SUM(target) AS total_defaults,
    ROUND(100.0 * SUM(target) / COUNT(*), 2) AS default_rate_pct
FROM applicants
GROUP BY 1
ORDER BY MIN(income_total);

-- a relative drop of ~34% from lowest to highest bracket. Note: 100K-200K (8.55%) is
-- marginally higher than Under 100K (8.20%), so the relationship isn't perfectly linear.

-- Q2: Does default rate vary by income type (employment category)?
SELECT
    income_type,
    COUNT(*) AS total_applicants,
    SUM(target) AS total_defaults,
    ROUND(100.0 * SUM(target) / COUNT(*), 2) AS default_rate_pct
FROM applicants
GROUP BY income_type
ORDER BY default_rate_pct DESC;

-- Finding: Working applicants default at 9.59% vs 5.39% for Pensioners — nearly 2x higher,
-- likely reflecting income stability differences. Commercial associate and State servant
-- sit in between. NOTE: Maternity leave, Unemployed, Student, and Businessman categories
-- have very small sample sizes (5-22 applicants) — their rates (0%-40%) are not statistically
-- reliable and should be excluded from headline findings.

-- Q3: Does default rate vary by age?
SELECT
    CASE
        WHEN age_years < 25 THEN 'Under 25'
        WHEN age_years < 35 THEN '25-35'
        WHEN age_years < 45 THEN '35-45'
        WHEN age_years < 55 THEN '45-55'
        WHEN age_years < 65 THEN '55-65'
        ELSE '65+'
    END AS age_bracket,
    COUNT(*) AS total_applicants,
    SUM(target) AS total_defaults,
    ROUND(100.0 * SUM(target) / COUNT(*), 2) AS default_rate_pct
FROM applicants
GROUP BY 1
ORDER BY MIN(age_years);
-- Finding: Strong, perfectly monotonic relationship — default rate falls from 12.36%
-- (Under 25) to 3.79% (65+), a >3x difference. Every bracket has 8,000+ applicants,
-- so this is high-confidence. Likely reflects shorter credit history, less job
-- tenure, and lower financial cushion among younger applicants rather than age itself.

-- Q4: Does default rate vary by education level?
SELECT
    education_type,
    COUNT(*) AS total_applicants,
    SUM(target) AS total_defaults,
    ROUND(100.0 * SUM(target) / COUNT(*), 2) AS default_rate_pct
FROM applicants
GROUP BY education_type
ORDER BY default_rate_pct DESC;

-- Finding: Default rate falls as education rises. Reliable comparison: Secondary
-- education (8.94%, n=218K) vs Higher education (5.36%, n=75K) — ~1.7x difference,
-- both high-confidence samples. Academic degree shows the lowest rate (1.83%) but
-- has only 164 applicants — directional only, not a headline number.

-- Q5: Does default rate vary by family/marital status?
SELECT
    family_status,
    COUNT(*) AS total_applicants,
    SUM(target) AS total_defaults,
    ROUND(100.0 * SUM(target) / COUNT(*), 2) AS default_rate_pct
FROM applicants
GROUP BY family_status
ORDER BY default_rate_pct DESC;

-- Finding: Widowed applicants default least (5.82%) vs Civil marriage/Single applicants
-- highest (~9.9%) — both ends have large, reliable samples (16K-45K+). Likely reflects
-- age (widowed skew older, and age strongly predicts lower default per Q3) and household
-- income stability. "Unknown" (n=2) is noise — excluded from findings entirely.

-- Q6: Does default rate vary by housing situation?
SELECT
    housing_type,
    COUNT(*) AS total_applicants,
    SUM(target) AS total_defaults,
    ROUND(100.0 * SUM(target) / COUNT(*), 2) AS default_rate_pct
FROM applicants
GROUP BY housing_type
ORDER BY default_rate_pct DESC;

-- Finding: Rented apartment (12.31%) and With parents (11.70%) default noticeably more
-- than House/apartment owners (7.80%, the dominant category at n=272,868). All samples
-- are large enough to be reliable. Consistent with the broader pattern across Q3-Q6:
-- stability signals (age, marriage, ownership, education) correlate with lower default.

-- Q7: Does default rate vary by external bureau credit score (ext_source_2)?
-- ext_source_2 is a normalized score from 0 to 1 provided by an external credit bureau.
-- Lower score = judged riskier by that external source. This tests whether their score
-- actually lines up with real default behavior in this data.
SELECT
    CASE
        WHEN ext_source_2 < 0.2 THEN '0.0-0.2 (Lowest)'
        WHEN ext_source_2 < 0.4 THEN '0.2-0.4'
        WHEN ext_source_2 < 0.6 THEN '0.4-0.6'
        WHEN ext_source_2 < 0.8 THEN '0.6-0.8'
        ELSE '0.8-1.0 (Highest)'
    END AS ext_score_bracket,
    COUNT(*) AS total_applicants,
    SUM(target) AS total_defaults,
    ROUND(100.0 * SUM(target) / COUNT(*), 2) AS default_rate_pct
FROM applicants
WHERE ext_source_2 IS NOT NULL
GROUP BY 1
ORDER BY MIN(ext_source_2);

-- Finding: By far the strongest predictor found in this analysis — default rate drops
-- from 18.84% (lowest score bracket) to 1.76% (highest), a >10x spread, and perfectly
-- monotonic across all 5 brackets. Dwarfs every demographic factor tested (age: 3x,
-- education: 1.7x). Confirms ext_source_2 is a well-calibrated external risk signal.
-- Top bracket has a smaller sample (n=569) but is still reasonably reliable.

-- Q8: Do applicants with more existing credit lines elsewhere default more?
-- Step 1 (the WITH block): collapse bureau_history from many-rows-per-applicant
-- down to one row per applicant, counting how many credit lines they have.
WITH bureau_counts AS (
    SELECT
        sk_id_curr,
        COUNT(*) AS num_credit_lines
    FROM bureau_history
    GROUP BY sk_id_curr
)
-- Step 2: joining that summary back to applicants and bucket the counts.
SELECT
    CASE
        WHEN COALESCE(b.num_credit_lines, 0) = 0 THEN '0 (no bureau history)'
        WHEN b.num_credit_lines <= 2 THEN '1-2'
        WHEN b.num_credit_lines <= 5 THEN '3-5'
        WHEN b.num_credit_lines <= 10 THEN '6-10'
        ELSE '10+'
    END AS credit_line_bucket,
    COUNT(*) AS total_applicants,
    SUM(a.target) AS total_defaults,
    ROUND(100.0 * SUM(a.target) / COUNT(*), 2) AS default_rate_pct
FROM applicants a
LEFT JOIN bureau_counts b ON a.sk_id_curr = b.sk_id_curr
GROUP BY 1
ORDER BY MIN(COALESCE(b.num_credit_lines, 0));

-- Finding: NOT linear — a U-shape. Highest default rate is at 0 credit lines (10.12%,
-- no track record to judge them on), drops to a low of 7.40% at 3-5 lines, then rises
-- again to 8.18% at 10+ lines (likely over-leveraged). All buckets have 32K+ applicants,
-- so the shape is reliable. Takeaway: moderate credit history is the safest zone —
-- both no history and excessive credit lines are riskier.

-- Q9: Does an applicant's total existing debt (from other lenders) predict default?
WITH bureau_debt AS (
    SELECT
        sk_id_curr,
        SUM(credit_sum_debt) AS total_external_debt
    FROM bureau_history
    GROUP BY sk_id_curr
)
SELECT
    CASE
        WHEN COALESCE(d.total_external_debt, 0) = 0 THEN 'No external debt'
        WHEN d.total_external_debt < 50000 THEN 'Under 50K'
        WHEN d.total_external_debt < 200000 THEN '50K-200K'
        WHEN d.total_external_debt < 500000 THEN '200K-500K'
        ELSE '500K+'
    END AS external_debt_bucket,
    COUNT(*) AS total_applicants,
    SUM(a.target) AS total_defaults,
    ROUND(100.0 * SUM(a.target) / COUNT(*), 2) AS default_rate_pct
FROM applicants a
LEFT JOIN bureau_debt d ON a.sk_id_curr = d.sk_id_curr
GROUP BY 1
ORDER BY MIN(COALESCE(d.total_external_debt, 0));

-- Finding: Mild, monotonic upward trend — default rate rises from 7.27% (no external
-- debt) to 9.09% (500K+ debt), only a ~1.25x spread. All buckets have 18K+ applicants,
-- so the trend is reliable but modest — a much weaker signal than ext_source_2 (10x)
-- or age (3x). Real, but not a headline finding.

-- Q10: Do applicants with a history of overdue payments elsewhere default more on THIS loan?
WITH bureau_overdue AS (
    SELECT
        sk_id_curr,
        MAX(days_overdue) AS worst_days_overdue
    FROM bureau_history
    GROUP BY sk_id_curr
)
SELECT
    CASE
        WHEN COALESCE(o.worst_days_overdue, 0) > 0 THEN 'Has overdue history'
        ELSE 'No overdue history'
    END AS overdue_flag,
    COUNT(*) AS total_applicants,
    SUM(a.target) AS total_defaults,
    ROUND(100.0 * SUM(a.target) / COUNT(*), 2) AS default_rate_pct
FROM applicants a
LEFT JOIN bureau_overdue o ON a.sk_id_curr = o.sk_id_curr
GROUP BY 1;

-- Finding: Applicants with overdue history default at ~2x the rate of those without
-- (15.90% vs 7.99%) — one of the strongest, most intuitive signals in the project.
-- Sample is reliable (n=3,397) but this flag only applies to ~1.1% of applicants overall,
-- so it's a high-confidence but narrow-coverage risk indicator.

-- Summary for Power Bi
CREATE VIEW bureau_summary AS
SELECT
    sk_id_curr,
    COUNT(*) AS num_credit_lines,
    SUM(credit_sum_debt) AS total_external_debt,
    MAX(days_overdue) AS worst_days_overdue
FROM bureau_history
GROUP BY sk_id_curr;