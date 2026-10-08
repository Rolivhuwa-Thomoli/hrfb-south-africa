## =====================================================================
## Table 4.7: group LASSO estimates at the optimal lambda (BIC), for every
## level of every predictor, with a Keep / Discard decision per variable.
##
## STEP 6. Needs data/hrfb_data.RData (step 1) and the group LASSO
## results saved in output/ (step 4):
##   group_bic_18.RData, group_bic_34.RData,
##   group_bic_sbi.RData, group_bic_parity.RData
## (these contain gbic_18, gbic_34, gbic_sbi, gbic_parity)
##
## Output: output/tab_selection.tex (also printed to the console so you can
##         copy it straight into chapter4.tex)
## =====================================================================

load("data/hrfb_data.RData")   # df (for the factor levels)
load("output/group_bic_18.RData")
load("output/group_bic_34.RData")
load("output/group_bic_sbi.RData")
load("output/group_bic_parity.RData")

results <- list(gbic_18, gbic_34, gbic_sbi, gbic_parity)
col_names <- c("Before 18", "After 34", "SBI", "High parity")

## Predictors and their levels (reference level first), as used in the models
predictors <- c("age_group", "province", "residence", "ethnicity",
                "hh_head_sex", "education", "literacy", "wealth_index",
                "marital_status", "currently_working", "ever_used_fp",
                "unmet_need", "consumes_media", "heard_fp_from_media")

var_label <- c(age_group = "Age group", province = "Province",
               residence = "Residence", ethnicity = "Ethnicity",
               hh_head_sex = "Sex of household head", education = "Education",
               literacy = "Literacy", wealth_index = "Wealth index",
               marital_status = "Marital status",
               currently_working = "Currently working",
               ever_used_fp = "Ever used family planning",
               unmet_need = "Unmet need for contraception",
               consumes_media = "Consumes media",
               heard_fp_from_media = "Heard FP message in media")

level_label <- function(x) {
  lab <- c(less_than_24 = "$<$24", "25_to_29" = "25--29", "30_to_34" = "30--34",
           "35_to_39" = "35--39", "40_and_higher" = "40+",
           Kwazulu_Natal = "KwaZulu-Natal", Black_or_African = "Black African",
           White_or_Other = "White/Other", No_education = "No education",
           Cannot_read = "Cannot read", Reads_partially = "Reads partially",
           Reads_fully = "Reads fully", Never_in_union = "Never in union",
           Living_with_partner = "Living with partner",
           Widowed_or_Divorced_or_Separated = "Widowed/divorced/separated",
           No_unmet_need = "No unmet need", Using_for_spacing = "Using for spacing",
           Using_for_limiting = "Using for limiting",
           Unmet_need_for_spacing = "Unmet need for spacing",
           Unmet_need_for_limiting = "Unmet need for limiting")
  out <- ifelse(x %in% names(lab), lab[x], gsub("_", " ", x))
  unname(out)
}

## Levels of each factor. Age group differs for "after 34" (35-39 vs 40+),
## so its rows are listed separately.
lv <- lapply(predictors, function(v) levels(droplevels(df)[[v]]))
names(lv) <- predictors

## Look up one coefficient in one fit ("" if the level is not in that model)
get_coef <- function(res, v, l) {
  cf <- res$best_fit$coefficients
  nm <- make.names(paste0(v, l))
  if (!(nm %in% names(cf))) return(NA)
  unname(cf[nm])
}

fmt <- function(x) {
  if (is.na(x)) return("")
  if (x == 0) return("0")
  out <- sprintf("%.3f", x)
  sub("^-", "$-$", out)
}

L <- c("{\\small\\setlength{\\tabcolsep}{5pt}",
       "\\begin{longtable}{lrrrr}",
       "\\caption{Group LASSO estimates (log-odds scale) at the BIC-optimal $\\lambda$ for each level, and the resulting decision for each variable.} \\label{tab:selection} \\\\",
       "\\toprule",
       paste0("Variable / level & ", paste(col_names, collapse = " & "), " \\\\"),
       "\\midrule", "\\endfirsthead",
       "\\toprule",
       paste0("Variable / level & ", paste(col_names, collapse = " & "), " \\\\"),
       "\\midrule", "\\endhead",
       "\\midrule \\multicolumn{5}{r}{\\textit{Continued on next page}} \\\\", "\\endfoot",
       "\\bottomrule", "\\endlastfoot")

for (v in predictors) {

  ## levels to show: for age group add 40+ vs 35-39 row used in "after 34"
  levels_all <- lv[[v]][-1]

  ## decision per outcome: Keep if any level is non-zero
  decision <- sapply(results, function(res) {
    vals <- sapply(names(res$best_fit$coefficients), function(n) startsWith(n, v))
    cf <- res$best_fit$coefficients[vals]
    if (length(cf) == 0) return("--")
    if (any(cf != 0)) "\\textbf{Keep}" else "\\textit{Discard}"
  })

  L <- c(L, paste0("\\textit{", var_label[v], "} (ref: ", level_label(lv[[v]][1]), ") & ",
                   paste(decision, collapse = " & "), " \\\\"))

  for (l in levels_all) {
    vals <- sapply(results, function(res) fmt(get_coef(res, v, l)))
    L <- c(L, paste0("\\quad ", level_label(l), " & ", paste(vals, collapse = " & "), " \\\\"))
  }
}

## Footer rows: optimal lambda and BIC
lam <- sapply(results, function(res) sprintf("%.2f", res$lambda[res$opt]))
bic <- sapply(results, function(res) sprintf("%.1f", res$BIC[res$opt]))
nk  <- sapply(results, function(res) length(res$selected))
L <- c(L, "\\midrule",
       paste0("Optimal $\\lambda$ & ", paste(lam, collapse = " & "), " \\\\"),
       paste0("BIC at optimal $\\lambda$ & ", paste(bic, collapse = " & "), " \\\\"),
       paste0("Variables kept (of 14) & ", paste(nk, collapse = " & "), " \\\\"),
       "\\end{longtable}}",
       "\\vspace{-6pt}",
       "{\\footnotesize \\textit{Note.} A variable is kept if at least one of its levels has a non-zero estimate; with the group LASSO all levels of a variable are either non-zero together or zero together. For birth after age 34 (women aged 35+), age group compares 40+ with 35--39, so only the 40+ row applies and the reference is 35--39. Estimates are penalised (shrunk towards zero) and are used only for selection; the unpenalised estimates are given in Section~\\ref{sec:glmm}.}",
       "\\medskip")

writeLines(L, "output/tab_selection.tex")
cat(L, sep = "\n")
