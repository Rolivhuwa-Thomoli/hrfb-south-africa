# High-Risk Fertility Behaviour among South African Women

**Which social, economic and demographic factors are linked to high-risk fertility behaviour (HRFB) in South Africa?**

> **Status:** BSc Honours research project in Statistics, University of Venda (submission November 2026). The analysis is complete: variable selection, final multilevel models and a full model evaluation. The results below are from the final models.

High-risk fertility behaviour means births that put mother and child at higher risk of illness and death. The four types are having a first birth very young, giving birth at an older age, spacing births too closely, and having many children. Using nationally representative survey data for 8,514 women, I find out who is most at risk, taking into account that women living in the same community tend to be similar.

![Prevalence](figures/02_prevalence.png)

**About 1 in 3 South African women aged 15–49 (32%) have at least one high-risk fertility behaviour. About 1 in 9 (11%) have two or more.**

### Interactive dashboard

I also built an interactive **Power BI** report on the results. It has a province map, breakdowns by wealth, education and age, and a forest plot of adjusted odds ratios drawn with an R visual. It uses Power Query, a star-schema data model and survey-weighted DAX measures. See [powerbi/](powerbi/README.md).

[![Power BI dashboard](powerbi/screenshots/01_overview.png)](powerbi/README.md)

---

## Key findings

* **Education and wealth protect.** Women with higher education have 46–71% lower odds of an early first birth, a short birth interval and high parity than women with no education. Women in the richest households have lower odds of every one of the four outcomes (odds ratios 0.44 to 0.71).
* **Unmet need for limiting births is the strongest modifiable factor.** It is linked to 2.1–3.3 times higher odds of every outcome.
* **Mpumalanga stands out.** It has about twice the odds of early first birth and high parity compared with the Western Cape, after adjusting for everything else.
* **Marriage and parity go together.** Married women, women living with a partner, and women who were previously in a union have 2.2–2.6 times the odds of having more than 3 children.
* **Communities matter, but modestly.** Before adjusting, 3–8% of the variation lies between survey clusters (median odds ratio 1.4–1.7). The predictors explain almost all of it for early first birth.
* **The models discriminate well and hold up under validation.** Cross-validated AUC ranges from 0.68 (early first birth) to 0.89 (high parity), with calibration slopes between 0.92 and 0.94.

---

## Summary

| | |
|---|---|
| **Data** | 2016 South Africa Demographic and Health Survey (SADHS): 8,514 women aged 15–49 in 729 survey clusters |
| **Outcomes** | 4 binary HRFB indicators, plus "any" and "multiple" |
| **Methods** | Data validation → bivariate screening (χ², Cramér's V) → **group LASSO** for mixed models (`glmmLasso`, λ by BIC), compared with ordinary and sparse group LASSO → two-level logistic regression (`lme4`) → evaluation (discrimination, calibration, DHARMa residuals, bootstrap optimism, cluster-level cross-validation, survey-weighted sensitivity analysis) |
| **Tools** | R · dplyr · ggplot2 · lme4 · glmmLasso · sparsegl · pROC · DHARMa · survey · Power BI (Power Query, DAX) |

---

## 1. Defining the outcomes

I used the standard DHS/WHO definitions and built each one from the women's birth histories:

| Outcome | Definition | Source variables | Prevalence (weighted) |
|---|---|---|---|
| Early first birth | First birth before age 18 | `V212` | 16.5% |
| Late birth | Most recent birth after age 34 | `B3_01`, `V011` (century-month codes) | 28.2% of women aged 35+ (9.6% of all women) |
| Short birth interval | Any interval between births under 24 months | `B11_01`–`B11_20` | 10.6% |
| High parity | More than 3 children ever born | `V201` | 10.8% |
| Any HRFB | At least one of the four | derived | 32.2% |
| Multiple HRFB | Two or more | derived | 11.0% |

**Decision: women with no births are coded 0 rather than treated as missing.** The 2,390 women with no children can't show any of these behaviours, and dropping them would make the results apply only to mothers. Many DHS studies instead limit the sample to recent births. I chose the whole-population view because the policy question is about all women of reproductive age. The trade-off: young women who haven't had children *yet* are counted as "not at risk", which is part of why age dominates the models.

**Decision: late birth is modelled only among women aged 35 and over** (n = 2,909). A woman of 25 cannot have had a birth after 34, so including her would make age a trivial predictor of this outcome.

---

## 2. Data quality: validating before modelling

### Missing data

![Missing data](figures/01_missing_data.png)

About 22 candidate predictors were screened. Two groups turned out to be **missing by design**, not at random:
- Questions about a partner and about household decision-making are only asked of women who are married or living with a partner, so 60–82% are missing.
- Health insurance and barriers to health care were only asked of a sub-sample, so 51% are missing.

**Decision:** I dropped these variables rather than impute them. Imputing a partner's age for a woman who has no partner makes no sense, and restricting the sample to women in a union would change the research question. Every variable I kept is 100% complete.

### Consistency checks

I wrote rules that every record should satisfy and checked the data against them:

| Rule | Violations | What I did |
|---|---|---|
| Age at first birth is missing only for women with no births | 0 | — |
| Age at most recent birth is missing only for women with no births | 0 | — |
| Birth interval is missing only for women with fewer than 2 births | 18 | **All 18 are twins.** Their only births are a twin pair, so there's no interval. Coding them 0 is correct. |
| Age at first birth is at or below current age | 0 | — |

### Outliers

One woman was recorded as giving birth at **age 3**: born in 1972, with a first birth in 1975, almost certainly a date-of-birth entry error. Seventeen women have a recorded first birth before age 12. My exploratory pipeline in `R/` removes these 17 records. The final analysis data set keeps all 8,514 women.

**What I caught on review:** my first version of the outlier filter also removed anyone with a first birth at **29 or older** (`age_at_first_birth < 29 & > 11`). That would have silently dropped **290 women** with perfectly normal late first births, and biased the "late birth" outcome, because those are exactly the women most likely to give birth after 34.

---

## 3. Bivariate screening

![Screening](figures/03_bivariate_screening.png)

For every outcome and predictor pair, I ran a χ² test of independence and used Cramér's V to measure how strong the association is. With n ≈ 8,500, even tiny associations come out statistically significant, so **effect size matters more than the p-value** here. I also checked that no expected cell count falls below 5, which the χ² test assumes.

What stands out:
- **Age group** has the strongest association with high parity (V = 0.39), followed by education (0.26) and marital status (0.26). Part of the age effect is mechanical: older women have simply had more time to have children.
- **Unmet need for contraception, marital status and education** are consistently associated with the outcomes.
- **Sex of household head** shows almost no association with any outcome (V ≤ 0.023).

---

## 4. Variable selection: group LASSO for mixed models

**Why not just screen with p-values?** Choosing predictors one at a time from bivariate tests ignores correlations between them. Education, literacy and wealth, for example, overlap heavily. The LASSO adds a penalty that shrinks weak coefficients to exactly zero, so the selection takes all predictors into account together.

**Why `glmmLasso`?** Women are sampled in clusters, so women in the same community are not independent. `glmmLasso` fits the penalty inside a model with a random intercept for each cluster.

**Why a *group* LASSO?** A factor like province enters the model as eight dummy variables. An ordinary LASSO can drop some provinces and keep others, which leaves a factor with a strange, data-driven reference group. The group LASSO treats all dummies of a factor as one group, so **a factor is kept or dropped as a whole**.

**How the penalty was chosen:** 40 values of λ on a log scale down to 10⁻⁴, with λ chosen by **BIC**. I first used 5-fold cross-validation, but BIC needs one fit per λ instead of five, so the search runs about five times faster.

**Result:**

| Outcome | Predictors kept (of 14) |
|---|---|
| First birth before 18 | 14 |
| Birth after age 34 | 6: age group, residence, wealth, working status, ever used family planning, unmet need |
| Short birth interval | 14 |
| High parity | 14 |

For three outcomes the LASSO kept everything: judged together, none of the predictors is redundant. For late birth it dropped eight, including province, education and marital status.

**Robustness check:** I repeated the selection with an ordinary (ungrouped) LASSO and a sparse group LASSO (`sparsegl`), each at its own BIC-optimal λ, and compared the estimates side by side.

**A bug I fixed while refactoring:** the four original selection scripts were near-identical copies, which I merged into one function. While testing it, every fit after the first λ failed silently. `glmmLasso` returns the cluster variance as a 1×1 *matrix*, and passing that back in as the next warm start breaks the fit. In my original scripts, `c()` had turned it into a number by accident. Converting it explicitly (`as.numeric()`) fixed it. Wrapping the fits in `try()` had hidden the failures, and I only noticed because the CV curve came back with a single point. I now let a failed fit stop the script.

---

## 5. Final two-level logistic models

`glmmLasso` selects variables but doesn't give valid standard errors, so I refitted the selected predictors as an ordinary (unpenalised) two-level logistic regression with `lme4::glmer`:

$$\text{logit}\,P(y_{ij}=1) = \beta_0 + \mathbf{x}_{ij}^\top\boldsymbol\beta + u_j, \qquad u_j \sim N(0, \sigma^2_u)$$

where woman *i* lives in cluster *j*.

![Odds ratios](figures/05_odds_ratios.png)

Red points raise the odds, green points lower them and grey points are not significant at 5%. Full table: [`results/final_odds_ratios.csv`](results/final_odds_ratios.csv).

**Interpreting these with care:** this is cross-sectional data, so some associations probably run the *other way*. Women who have already had several children are more likely to *want to limit* births (unmet need for limiting) and to have *started* using contraception (ever used FP). These variables partly reflect the outcome rather than cause it, so I treat them as markers, not risk factors.

---

## 6. Model evaluation

![ROC curves](figures/06_roc_curves.png)

| | First birth before 18 | Birth after 34 | Short birth interval | High parity |
|---|---|---|---|---|
| AUC (95% CI) | 0.69 (0.67–0.70) | 0.70 (0.68–0.72) | 0.77 (0.76–0.79) | 0.90 (0.89–0.91) |
| AUC, 5-fold CV by cluster | 0.68 | 0.69 | 0.76 | 0.89 |
| Calibration slope, CV | 0.92 | 0.94 | 0.92 | 0.93 |
| ICC, null model | 0.033 | 0.063 | 0.032 | 0.081 |
| MOR, null model | 1.38 | 1.57 | 1.37 | 1.67 |
| ICC, final model | 0.000 (singular) | 0.040 | 0.017 | 0.073 |
| Significance agrees with survey-weighted model | 30 of 34 terms | 9 of 10 | 29 of 34 | 33 of 34 |

What I checked, and why:
- **Discrimination and calibration.** AUC, Brier score, calibration slope and calibration-in-the-large, and the Hosmer–Lemeshow test.
- **Overfitting.** Harrell's bootstrap optimism (200 resamples) and 5-fold cross-validation that holds out **whole clusters**, so the test data really is new communities. The drop from apparent to validated AUC is at most 0.012.
- **Clustering.** ICC, median odds ratio and the proportional change in variance against the null model, plus a likelihood-ratio test of the random intercept. For early first birth the cluster variance shrinks to zero once the predictors are in (a singular fit), so a single-level model would do.
- **Assumptions.** DHARMa simulated residuals at woman and cluster level, and generalised VIFs (all below 2) for multicollinearity.
- **Survey design.** The GLMMs are unweighted, so I refitted each model as a survey-weighted logistic regression (weights, PSUs and strata). Significance agrees for 101 of 112 terms, and the median difference in log odds ratios is below 0.03.

Full table: [`results/final_model_evaluation.csv`](results/final_model_evaluation.csv).

---

## Limitations

1. **Age as exposure time.** Age dominates three of the four outcomes because older women have had more years in which the behaviour could happen. Analysing births rather than women, or adding years at risk as an offset, would separate the two.
2. **Cross-sectional data.** Family-planning variables are measured after the births they are meant to explain, so their associations cannot be read as causal.
3. **Selection then inference.** p-values from a model refitted after LASSO selection are optimistic. I report them alongside the penalised estimates and interpret them cautiously.
4. **Weights in the multilevel models.** The main models are unweighted. The survey-weighted refit agrees closely, but a weighted multilevel estimator (e.g. `WeMix`) would be the stronger check.

---

## Repository structure

```
├── R/
│   ├── 01_prepare_data.R        # read DHS file, derive outcomes, recode predictors (exploratory pipeline)
│   ├── 02_explore.R             # missing-data audit, consistency checks, prevalence, χ² screening
│   ├── 03_variable_selection.R  # first glmmLasso run with 5-fold CV
│   ├── 04_multilevel_models.R   # first glmer refit
│   └── 05_final_figures.R       # final forest plot, drawn from results/ (no survey data needed)
├── run_all.R                    # runs the exploratory pipeline
├── data/README.md               # how to get the SADHS data (not included)
├── figures/
├── results/                     # aggregated tables only (CSV), from the final analysis
└── powerbi/                     # Power BI report, its aggregated data, theme and build guide
```

The scripts in `R/01`–`R/04` are my first, exploratory version of the pipeline. The final selection, modelling and evaluation code (group LASSO, model evaluation, method comparison) will be added after the dissertation is examined. Everything in `results/` and `figures/` comes from the final analysis.

**Data note:** the SADHS microdata is **not included**, as required by the DHS Program's terms of use. Only aggregated results are published.

## References

- National Department of Health, Stats SA, SAMRC & ICF (2019). *South Africa Demographic and Health Survey 2016.* Pretoria and Rockville, MD.
- Groll, A. & Tutz, G. (2014). Variable selection for generalized linear mixed models by L1-penalized estimation. *Statistics and Computing*, 24(2), 137–154.
- Bates, D., Mächler, M., Bolker, B. & Walker, S. (2015). Fitting linear mixed-effects models using lme4. *Journal of Statistical Software*, 67(1).
- Merlo, J. et al. (2006). A brief conceptual tutorial of multilevel analysis in social epidemiology: using measures of clustering in multilevel logistic regression. *Journal of Epidemiology & Community Health*, 60(4), 290–297.
- Rutstein, S.O. & Winter, R. (2014). *The effects of fertility behavior on child survival and child nutritional status.* DHS Analytical Studies No. 37. ICF International.

---

*Rolivhuwa Thomoli · BSc Honours Statistics, University of Venda*
