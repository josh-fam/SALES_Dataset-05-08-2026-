# Sales Analytics Pipeline — Key Takeaways

## Project Summary
End to end analysis of 5,000 ecommerce sales transactions, moving from raw, messy source data through SQL cleaning, Python data quality investigation, and a 5page Power BI dashboard.

**Stack:** PostgreSQL (staging → clean → final tables) → Python/pandas (judgment call profiling) → Power BI

---

## Key Findings

**1. The `city` column was unreliable for 86% of rows**
Cross checking the stored `city` field against the city embedded in `purchase_address` showed a mismatch in 4,305 of 5,000 rows. The `city` column could not be trusted and was dropped in favor of a new `address_city` field derived directly from the address — the more specific, verifiable source.

**2. The `region` column showed no reliable relationship to city at all**
Unlike the city mismatch (which was consistently *wrong*), `region` showed no consistent mapping to `address_city` in either direction — each city's transactions were spread almost evenly across all four regions. Rather than force a fix, `region` was excluded from geographic analysis and flagged as unreliable, with `address_city` used as the sole trustworthy location field.

**3. Wholesale wins on volume, Online wins on value per order**
Wholesale leads in both order count and total revenue, but Online has the highest **average order value** — the opposite of what "wholesale = bulk = high value" would predict. In Store lags on both fronts. This is the one clearly meaningful, non flat pattern in the channel data.

**4. Several fields (delivery time, product revenue, region) show flat, near random distributions**
Average delivery time is ~4-5 days across every channel and product with no meaningful variation. Revenue and unit volume are nearly even across all 7 products. Combined with the region finding, this suggests parts of the dataset were generated independently of one another rather than modeling realistic causal relationships (e.g., faster online shipping, higher bulk order value) — a limitation of the underlying data, not a business insight, and treated as such rather than over-interpreted.

**5. ~5% of orders (247 rows) had missing pricing data**
`unit_price`, `total_sales`, and `cost` were missing together on the same 247 rows — investigated for clustering by product, sales rep, and date (none found) and by channel (a mild, non dramatic skew toward Wholesale). Concluded to be a low level, evenly distributed recording gap rather than a systemic bug tied to one source. Flagged and excluded from revenue calculations; retained for quantity/channel mix analysis.

---

## Methodology Notes
- **SQL** handled all mechanical cleaning: type casting, whitespace trimming, category casing standardization, and a custom `CASE`-based parser for two mixed date formats in the same column (`YYYY-MM-DD` and `MM/DD/YYYY`)
- **Python/pandas** was used for lighter touch visual confirmation of the SQL driven findings (channel skew, quantity distributions) rather than deep exploratory investigation.
- A real encoding bug was diagnosed and fixed during the project: accented characters (e.g., "São Paulo") displayed as garbled text in the terminal, the corruption was isolated to a client side encoding/codepage mismatch (`psql` session `client_encoding` plus the Windows terminal's console codepage), not the underlying data. Power BI was confirmed to read the correct data throughout.
- A whitespace vs empty string bug was caught and fixed: `NULLIF(column, '')` failed to catch values that were whitespace only rather than truly empty, causing a numeric cast error — fixed by trimming before the null check (`NULLIF(TRIM(column), '')`).

---

## Dashboard Pages
1. **Overview** — headline KPIs (order count, revenue, average order value, missing-pricing rate)
2. **Sales by Product** — revenue and unit volume by product
3. **Channel Performance** — revenue, order count, and average order value by sales channel
4. **Regional Breakdown** — city-level revenue map, plus documentation of the region/city mismatch
5. **Delivery Time** — average delivery time by channel and product
