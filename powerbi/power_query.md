# Power Query code for the eight tables

Every query ends with `"en-US"` in its type step. Windows on this laptop uses South African number
settings (comma as decimal separator), so without it Power BI would read `37.7175` as `377175`
or as an error.

**How to add one:** in Power Query, **New Source > Blank Query**, then **Advanced Editor**, delete
everything, paste the block, click **Done**, and rename the query (right-click > Rename) to the
name in the heading.

## fact_prevalence (replace your existing query with this)
```
let
    Source = Csv.Document(File.Contents(DataFolder & "fact_prevalence.csv"), [Delimiter=",", Encoding=65001, QuoteStyle=QuoteStyle.Csv]),
    Headers = Table.PromoteHeaders(Source, [PromoteAllScalars=true]),
    Typed = Table.TransformColumnTypes(Headers, {
        {"outcome_key", type text}, {"province", type text}, {"category_key", type text},
        {"dimension", type text}, {"level", type text},
        {"n_women", Int64.Type}, {"n_events", Int64.Type},
        {"w_women", type number}, {"w_events", type number}}, "en-US")
in
    Typed
```

## fact_odds_ratios
```
let
    Source = Csv.Document(File.Contents(DataFolder & "fact_odds_ratios.csv"), [Delimiter=",", Encoding=65001, QuoteStyle=QuoteStyle.Csv]),
    Headers = Table.PromoteHeaders(Source, [PromoteAllScalars=true]),
    Typed = Table.TransformColumnTypes(Headers, {
        {"outcome_key", type text}, {"variable", type text}, {"variable_label", type text},
        {"level", type text}, {"level_label", type text}, {"reference_level", type text},
        {"odds_ratio", type number}, {"ci_lower", type number}, {"ci_upper", type number},
        {"p_value", type number}, {"log_or", type number},
        {"significant", type text}, {"direction", type text}}, "en-US"),
    OrLabel = Table.AddColumn(Typed, "OR label", each
        Number.ToText([odds_ratio], "0.00", "en-US") & " (" &
        Number.ToText([ci_lower], "0.00", "en-US") & "-" &
        Number.ToText([ci_upper], "0.00", "en-US") & ")", type text),
    TermLabel = Table.AddColumn(OrLabel, "term_label", each [variable_label] & ": " & [level_label], type text)
in
    TermLabel
```

## fact_chisq
```
let
    Source = Csv.Document(File.Contents(DataFolder & "fact_chisq.csv"), [Delimiter=",", Encoding=65001, QuoteStyle=QuoteStyle.Csv]),
    Headers = Table.PromoteHeaders(Source, [PromoteAllScalars=true]),
    Typed = Table.TransformColumnTypes(Headers, {
        {"outcome_key", type text}, {"variable", type text},
        {"chi_sq", type number}, {"df", Int64.Type}, {"p_value", type number},
        {"cramers_v", type number}, {"small_expected", Int64.Type},
        {"significant", type text}, {"variable_label", type text}}, "en-US")
in
    Typed
```

## fact_model_performance
```
let
    Source = Csv.Document(File.Contents(DataFolder & "fact_model_performance.csv"), [Delimiter=",", Encoding=65001, QuoteStyle=QuoteStyle.Csv]),
    Headers = Table.PromoteHeaders(Source, [PromoteAllScalars=true]),
    Typed = Table.TransformColumnTypes(Headers, {
        {"outcome_key", type text}, {"n", Int64.Type}, {"events", Int64.Type},
        {"auc", type number}, {"auc_lower", type number}, {"auc_upper", type number},
        {"auc_cv", type number}, {"brier", type number}, {"brier_null", type number},
        {"calib_slope_cv", type number}, {"icc_null", type number}, {"mor_null", type number},
        {"icc", type number}, {"mor", type number},
        {"r2_marginal", type number}, {"r2_tjur", type number}}, "en-US")
in
    Typed
```

## fact_model_metric_long (the unpivot, built on the query above)
```
let
    Source = fact_model_performance,
    Kept = Table.SelectColumns(Source, {"outcome_key", "auc", "auc_cv", "brier", "icc_null", "mor_null", "r2_tjur"}),
    Long = Table.UnpivotOtherColumns(Kept, {"outcome_key"}, "metric", "value")
in
    Long
```

## dim_outcome
```
let
    Source = Csv.Document(File.Contents(DataFolder & "dim_outcome.csv"), [Delimiter=",", Encoding=65001, QuoteStyle=QuoteStyle.Csv]),
    Headers = Table.PromoteHeaders(Source, [PromoteAllScalars=true]),
    Typed = Table.TransformColumnTypes(Headers, {
        {"outcome_key", type text}, {"outcome_var", type text}, {"outcome_label", type text},
        {"population", type text}, {"sort_order", Int64.Type}}, "en-US")
in
    Typed
```

## dim_province
```
let
    Source = Csv.Document(File.Contents(DataFolder & "dim_province.csv"), [Delimiter=",", Encoding=65001, QuoteStyle=QuoteStyle.Csv]),
    Headers = Table.PromoteHeaders(Source, [PromoteAllScalars=true]),
    Typed = Table.TransformColumnTypes(Headers, {
        {"province", type text}, {"province_name", type text}, {"iso_code", type text},
        {"latitude", type number}, {"longitude", type number}, {"country", type text}}, "en-US"),
    MapLocation = Table.AddColumn(Typed, "map_location", each [province_name] & ", South Africa", type text)
in
    MapLocation
```

## dim_category
```
let
    Source = Csv.Document(File.Contents(DataFolder & "dim_category.csv"), [Delimiter=",", Encoding=65001, QuoteStyle=QuoteStyle.Csv]),
    Headers = Table.PromoteHeaders(Source, [PromoteAllScalars=true]),
    Typed = Table.TransformColumnTypes(Headers, {
        {"category_key", type text}, {"dimension_label", type text}, {"dimension_order", Int64.Type},
        {"dimension", type text}, {"level", type text}, {"level_label", type text},
        {"level_order", Int64.Type}}, "en-US")
in
    Typed
```

## dim_variable
```
let
    Source = Csv.Document(File.Contents(DataFolder & "dim_variable.csv"), [Delimiter=",", Encoding=65001, QuoteStyle=QuoteStyle.Csv]),
    Headers = Table.PromoteHeaders(Source, [PromoteAllScalars=true]),
    Typed = Table.TransformColumnTypes(Headers, {
        {"variable", type text}, {"role", type text}, {"label", type text},
        {"description", type text}, {"dhs_source", type text}, {"type", type text},
        {"levels_or_coding", type text}, {"reference_level", type text},
        {"used_in_models", type text}, {"notes", type text}}, "en-US")
in
    Typed
```

When all nine queries are in, click **Close & Apply**.
