# Building the HRFB Power BI dashboard

> The published report implements pages 1 to 3 (Overview, Who is at risk, Modelled risk factors). The risk-factors page uses the R visual in `forest_plot_r_visual.R` instead of the line-chart forest plot described below, and the map uses the `Map Colour` measure for its shading. Pages 4 and 5 are left as extensions.

A step-by-step guide to turning the SADHS 2016 high-risk fertility behaviour (HRFB) analysis into a
five-page Power BI report for your portfolio. Each step names the Power BI skill it shows off, so you
can mention it on your CV and in interviews.

**Skills covered:** Power Query (parameters, type setting, unpivot, merge, custom columns), star-schema
data model, DAX measures (CALCULATE, DIVIDE, RANKX, SELECTEDVALUE, variables, dynamic titles),
slicers and sync slicers, filled map, drill-through, report-page tooltips, bookmarks and buttons,
conditional formatting, custom theme.

---

## 0. Before you start

1. Re-create the tables whenever the R results change:
   ``
   Rscript powerbi/export_powerbi.R
   ``
   (run it from the `Data Analysis` folder). It writes eight CSVs to `powerbi/data/`.
2. Open Power BI Desktop. Go to **File > Options and settings > Options > Global > Security** and tick
   **Use Map and Filled Map visuals**, then restart Power BI. Without this the map in step 4 is grey.
3. **Design > Themes** (the down arrow beside the theme thumbnails) **> Browse for themes** and pick `powerbi/hrfb_theme.json`.

### What is in the data

| File | Grain (one row per...) | Use |
|---|---|---|
| `fact_prevalence.csv` | outcome x province x breakdown level | weighted prevalence, map, breakdowns |
| `fact_odds_ratios.csv` | outcome x model term | adjusted odds ratios from the final GLMMs |
| `fact_chisq.csv` | outcome x variable | chi-square screening, Cramer's V |
| `fact_model_performance.csv` | outcome | AUC, Brier, ICC, MOR, R-squared |
| `dim_outcome.csv` | outcome | labels, population, sort order |
| `dim_province.csv` | province | display name, ISO code, lat/long |
| `dim_category.csv` | breakdown level | dimension + level labels and sort orders |
| `dim_variable.csv` | variable | data dictionary (labels, DHS source codes) |

`fact_prevalence` holds **weighted sums** (`w_women`, `w_events`) rather than percentages, so
prevalence can be re-aggregated correctly for any filter: `SUM(w_events) / SUM(w_women)`.
Each province has one `overall` row plus one row per level of six breakdowns (residence, wealth,
age group, education, marital status, ever used FP). Never add rows from two different breakdowns
together; the measures in step 3 take care of that.

The data is aggregated on purpose: DHS terms do not allow sharing respondent-level data, so the
.pbix and CSVs are safe to publish on GitHub.

---

## 1. Power Query: load and shape the data

### 1a. A folder parameter (shows: parameters, reusable queries)
**Home > Transform data** opens Power Query.
1. **Manage Parameters > New**: Name `DataFolder`, Type `Text`, Current value = the full path to
   `powerbi\data\` (end it with a backslash).
2. **New Source > Text/CSV**, pick `fact_prevalence.csv`, click **Transform Data**.
3. Open **Advanced Editor** and replace the hard-coded path with the parameter:
   ``
   Source = Csv.Document(File.Contents(DataFolder & "fact_prevalence.csv"),
            [Delimiter=",", Encoding=65001, QuoteStyle=QuoteStyle.Csv]),
   ``
4. Add the other tables by pasting the ready-made queries in [power_query.md](power_query.md) into blank queries. They set every type with the en-US culture so decimals read correctly on computers with comma decimal settings, such as South African Windows.

Now anyone who clones the repo changes one parameter and the whole report refreshes.

### 1b. Types and clean names (shows: data profiling, type discipline)
* Turn on **View > Column quality / Column distribution / Column profile** and screenshot it for the
  README: it shows you check data before modelling.
* Set types explicitly: whole numbers for `n_women`, `n_events`, `level_order`; decimal for
  `w_women`, `w_events`, `odds_ratio`, `ci_*`, `p_value`; text for keys.
* Rename queries to drop `.csv` (e.g. `fact_prevalence`).

### 1c. Unpivot model metrics (shows: unpivot)
Duplicate `fact_model_performance` and call it `fact_model_metric_long`. Select `outcome_key`,
right-click > **Unpivot Other Columns**. Rename `Attribute` to `metric` and `Value` to `value`. This
long table drives a small-multiples chart on page 4 without one measure per metric.

### 1d. Custom columns (shows: M expressions, conditional columns)
In `fact_odds_ratios`, **Add Column > Custom Column**:
* `OR label` = `Number.ToText([odds_ratio], "0.00") & " (" & Number.ToText([ci_lower], "0.00") & "-" & Number.ToText([ci_upper], "0.00") & ")"`
* `term_label` = `[variable_label] & ": " & [level_label]`

In `dim_province`, add `map_location` = `[province_name] & ", South Africa"` and later set its
**Data category** to *State or Province* (Column tools ribbon). The country suffix stops Bing from
placing "Free State" or "North West" in another country.

**Close & Apply.**

---

## 2. Data model (shows: star schema, relationships, sort-by-column)

In **Model view**, create these relationships (all single direction, many-to-one, from fact to dim):

| From (many) | To (one) |
|---|---|
| `fact_prevalence[outcome_key]` | `dim_outcome[outcome_key]` |
| `fact_prevalence[province]` | `dim_province[province]` |
| `fact_prevalence[category_key]` | `dim_category[category_key]` |
| `fact_odds_ratios[outcome_key]` | `dim_outcome[outcome_key]` |
| `fact_odds_ratios[variable]` | `dim_variable[variable]` |
| `fact_chisq[outcome_key]` | `dim_outcome[outcome_key]` |
| `fact_chisq[variable]` | `dim_variable[variable]` |
| `fact_model_performance[outcome_key]` | `dim_outcome[outcome_key]` |
| `fact_model_metric_long[outcome_key]` | `dim_outcome[outcome_key]` |

Then:
* **Sort by column**: `dim_outcome[outcome_label]` by `sort_order`; `dim_category[level_label]` by
  `level_order`; `dim_category[dimension_label]` by `dimension_order`.
* Hide the key columns in the fact tables (right-click > Hide in report view) so report users only
  see the dimension fields.
* Create an empty table for measures: **Home > Enter data**, name it `_Measures`, load it, add the
  measures below to it, then delete its dummy column.

Screenshot the Model view for the README. A tidy star schema is one of the first things reviewers look for.

---

## 3. DAX measures

Create a display folder per group (select a measure > Properties > Display folder).

### Prevalence (folder: Prevalence)
``DAX
Weighted Women =
IF ( HASONEVALUE ( dim_category[dimension] ),
     SUM ( fact_prevalence[w_women] ),
     CALCULATE ( SUM ( fact_prevalence[w_women] ), dim_category[dimension] = "overall" ) )

Weighted Events =
IF ( HASONEVALUE ( dim_category[dimension] ),
     SUM ( fact_prevalence[w_events] ),
     CALCULATE ( SUM ( fact_prevalence[w_events] ), dim_category[dimension] = "overall" ) )

Women (unweighted) =
IF ( HASONEVALUE ( dim_category[dimension] ),
     SUM ( fact_prevalence[n_women] ),
     CALCULATE ( SUM ( fact_prevalence[n_women] ), dim_category[dimension] = "overall" ) )

Prevalence % =
IF ( HASONEVALUE ( dim_outcome[outcome_key] ),
     DIVIDE ( [Weighted Events], [Weighted Women] ) )
``
Format `Prevalence %` as Percentage, 1 decimal. The `HASONEVALUE` guards stop two problems: adding
women across different breakdowns (which counts each woman seven times) and averaging across outcomes
that have different populations.

``DAX
Prevalence (DHS rule) =
VAR _n = [Women (unweighted)]
RETURN IF ( _n >= 25, [Prevalence %] )
``
DHS reports suppress estimates based on fewer than 25 unweighted cases. Use this one in tables and
mention the rule in a tooltip. It is a good talking point about statistical judgement.

``DAX
National Prevalence % =
CALCULATE ( [Prevalence %], REMOVEFILTERS ( dim_province ) )

Gap vs National (pp) =
( [Prevalence %] - [National Prevalence %] ) * 100

Province Rank =
IF ( HASONEVALUE ( dim_province[province_name] ),
     RANKX ( ALL ( dim_province[province_name] ), [Prevalence %], , DESC, DENSE ) )

Highest Province =
VAR _top = TOPN ( 1, ALL ( dim_province[province_name] ), [Prevalence %], DESC )
RETURN MAXX ( _top, dim_province[province_name] )
``

### Odds ratios (folder: Models)
``DAX
Odds Ratio = AVERAGE ( fact_odds_ratios[odds_ratio] )
OR Lower = AVERAGE ( fact_odds_ratios[ci_lower] )
OR Upper = AVERAGE ( fact_odds_ratios[ci_upper] )

Significant Factors =
CALCULATE ( COUNTROWS ( fact_odds_ratios ), fact_odds_ratios[p_value] < 0.05 )

Strongest Risk Factor =
VAR _t = TOPN ( 1,
               FILTER ( fact_odds_ratios, fact_odds_ratios[p_value] < 0.05 ),
               fact_odds_ratios[odds_ratio], DESC )
RETURN MAXX ( _t, fact_odds_ratios[term_label] & " (OR " & FORMAT ( fact_odds_ratios[odds_ratio], "0.0" ) & ")" )

OR Colour =
SWITCH ( TRUE (),
         MAX ( fact_odds_ratios[p_value] ) >= 0.05, "#9AA5AE",
         [Odds Ratio] > 1, "#C44536",
         "#3D9970" )

AUC = AVERAGE ( fact_model_performance[auc] )
ICC (null model) = AVERAGE ( fact_model_performance[icc_null] )
MOR (null model) = AVERAGE ( fact_model_performance[mor_null] )
``

### Titles (folder: Labels)
``DAX
Selected Outcome = SELECTEDVALUE ( dim_outcome[outcome_label], "Select one outcome" )

Map Title = "Weighted prevalence of " & LOWER ( [Selected Outcome] ) & " by province"

Breakdown Title =
[Selected Outcome] & " by " & LOWER ( SELECTEDVALUE ( dim_category[dimension_label], "group" ) )

Population Note = "Population: " & SELECTEDVALUE ( dim_outcome[population] )
``
Use these with **Format visual > General > Title > fx > Field value** to get titles that change with
the slicers.

---

## 4. Report pages

Page size 16:9. Put the same outcome slicer on every page and link them with
**View > Sync slicers**.

### Page 1. Overview
* **Slicer** `dim_outcome[outcome_label]`, single select, tile style across the top.
* **Four cards** (or one multi-row card), each `Prevalence %` filtered in the visual filter pane to
  one outcome. These show the headline rates regardless of the slicer: edit interactions
  (**Format > Edit interactions**) so the slicer does not filter them.
* **Filled map**: Location `dim_province[map_location]`, Tooltips `Prevalence %`, colour
  **fx > Gradient** on `Prevalence %`. Title uses `[Map Title]`.
* **Bar chart**: `dim_province[province_name]` by `Prevalence %`, sorted descending, with a constant
  line from `National Prevalence %` (Analytics pane > Y-axis constant line > fx).
* **Card**: `Highest Province`.

### Page 2. Who is at risk
* **Slicer** `dim_category[dimension_label]`, single select, *exclude* "Overall" in the filter pane.
* **Clustered bar** `dim_category[level_label]` by `Prevalence %`; title `[Breakdown Title]`.
* **Matrix**: rows `dim_province[province_name]`, columns `dim_category[level_label]`, values
  `Prevalence (DHS rule)`, conditional formatting **Background colour > Gradient**.
* **Province slicer** (dropdown) so the user can compare one province with the country.

### Page 3. Risk factors (adjusted odds ratios)
* **Slicer** `dim_variable[label]` (multi-select) next to the outcome slicer.
* **Forest plot**: Line chart or scatter with Y-axis `fact_odds_ratios[term_label]` and X-axis
  `Odds Ratio`; turn off the line, turn on markers, then **Analytics > Error bars**: upper bound
  `OR Upper`, lower bound `OR Lower`. Add an X-axis constant line at 1 and set the X-axis to
  **Logarithmic** scale. Colour markers with **fx > Field value** on `OR Colour`.
* **Table**: `term_label`, `OR label`, `p_value`, `direction`, with icons
  (conditional formatting > Icons) on `p_value`.
* **Card**: `Strongest Risk Factor`, **Card**: `Significant Factors`.

### Page 4. Model performance
* **Small multiples** clustered column: axis `dim_outcome[outcome_label]`, value `value`,
  small multiples `metric` from `fact_model_metric_long`, filtered to `auc`, `auc_cv`, `brier`,
  `icc_null`, `r2_tjur`.
* **Cards**: `AUC`, `ICC (null model)`, `MOR (null model)` for the selected outcome.
* **Text box** with a two-line plain-English reading, e.g. "AUC 0.90 for high parity: the model ranks a
  random high-parity woman above a random low-parity woman 90% of the time."
* **Bar chart** from `fact_chisq`: `dim_variable[label]` by `cramers_v`, colour by `significant`.

### Page 5. Province detail (drill-through)
* In the **Drill through** well, add `dim_province[province_name]`. Power BI adds a back button.
* **Cards**: `Prevalence %`, `National Prevalence %`, `Gap vs National (pp)`, `Province Rank`.
* **Clustered bar**: `dim_category[level_label]` by `Prevalence %` with the breakdown slicer.
* Back on pages 1 and 2, right-click a province > **Drill through > Province detail**.

### Tooltip page (report-page tooltip)
New page, **Page information > Allow use as tooltip**, canvas type *Tooltip*. Add `Province Rank`,
`Gap vs National (pp)`, `Women (unweighted)` and the DHS footnote. Then on the map
**Format > Tooltips > Type: Report page > Page: Tooltip**.

### Bookmarks and buttons (shows: storytelling and navigation)
* On page 1, duplicate the map, swap it for a **Table** of the same fields, then in the **Selection**
  pane hide one or the other and save two bookmarks: *Map view* and *Table view* (untick **Data** in
  each bookmark so they keep slicer selections). Add two buttons that action those bookmarks.
* Add a **Reset filters** bookmark (captured with every slicer cleared) and a button for it.
* Add a **Page navigator** (Insert > Buttons > Navigator) across the top of every page.

---

## 5. Finishing touches

* **About** text box on page 1: data source (South Africa DHS 2016, women 15 to 49, n = 8,514;
  women 35+ n = 2,909), weights applied, models are multilevel logistic regressions with a cluster
  random intercept and group-lasso variable selection.
* **File > Options > Current file > Report settings**: turn off *Allow users to save filters* so every visitor sees the same starting view.
* Save as `HRFB_South_Africa.pbix` in the `powerbi/` folder.

## 6. Screenshots for GitHub

Save these as PNG at 1600 px wide or more (Windows key + Shift + S, or **File > Export > PDF** and
crop) into `powerbi/screenshots/`:

| File | What |
|---|---|
| `01_overview.png` | Page 1 with one outcome selected |
| `02_who_is_at_risk.png` | Page 2 with "Wealth" selected |
| `03_risk_factors.png` | Page 3 forest plot |
| `04_model_performance.png` | Page 4 |
| `05_drillthrough.png` | Province detail for one province |
| `06_data_model.png` | Model view |
| `07_power_query.png` | Power Query with column profiling on |
| `08_dax_measures.png` | Measure table with display folders |
| `demo.gif` (optional) | 20 to 30 s screen recording of slicers, drill-through and bookmarks (ScreenToGif is free) |
