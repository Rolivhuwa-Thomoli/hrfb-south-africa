## =====================================================================
## Side-by-side comparison of the three penalised methods, at each
## method's BIC-optimal lambda only (no lambda-path output).
##
##   ordinary glmmLasso    : 04c_ordinary_glmmlasso.R   -> output/ordinary_bic_*.RData
##   group lasso (glmmLasso): 04_group_lasso_selection.R -> output/group_bic_*.RData
##   sparse group lasso    : 09_sparse_group_lasso.R    -> output/sgl_final_estimates.RData
##
## Estimates are on the log-odds scale (beta); OR = exp(beta). A term that a
## method drops is shown as 0 (kept in the table so the three line up).
## A term that is not in a model at all (greater_34 has no under-35 age
## groups) is shown as "-".
##
## Writes
##   output/comparison_lasso_estimates.csv   (long table, all terms)
##   output/comparison_lasso_estimates.txt   (one table per outcome)
##
## STEP 10. Needs the outputs of steps 04, 04c and 09.
## =====================================================================

load_best <- function(file, obj) {
  e <- new.env(); load(file, envir = e)
  r <- e[[obj]]
  r$best_fit$coefficients        # intercept first, then terms
}

outcomes <- c("hrfb_less_18", "hrfb_greater_34", "hrfb_sbi", "hrfb_parity")
suffix   <- c(hrfb_less_18 = "18", hrfb_greater_34 = "34", hrfb_sbi = "sbi", hrfb_parity = "parity")

ord <- list(); grp <- list()
for (o in outcomes) {
  ord[[o]] <- load_best(paste0("output/ordinary_bic_", suffix[[o]], ".RData"), paste0("gbic_", suffix[[o]]))
  grp[[o]] <- load_best(paste0("output/group_bic_", suffix[[o]], ".RData"),    paste0("gbic_", suffix[[o]]))
}
e <- new.env(); load("output/sgl_final_estimates.RData", envir = e)
sgl <- lapply(e$sgl_final, `[[`, "beta")


## One block per outcome: union of terms, in the order of the group fit
rows <- list()
for (o in outcomes) {
  terms <- union(union(names(ord[[o]]), names(grp[[o]])), names(sgl[[o]]))
  terms <- c(intersect("(Intercept)", terms), setdiff(terms, "(Intercept)"))
  fill <- function(v) {
    out <- setNames(rep(NA_real_, length(terms)), terms)
    out[names(v)] <- v
    out
  }
  b_ord <- fill(ord[[o]]); b_grp <- fill(grp[[o]]); b_sgl <- fill(sgl[[o]])
  rows[[o]] <- data.frame(
    outcome        = o,
    term           = terms,
    glmmLasso_beta = round(b_ord, 4),
    glmmLasso_OR   = round(exp(b_ord), 3),
    group_beta     = round(b_grp, 4),
    group_OR       = round(exp(b_grp), 3),
    sparse_beta    = round(b_sgl, 4),
    sparse_OR      = round(exp(b_sgl), 3),
    row.names = NULL, stringsAsFactors = FALSE)
}
comp <- do.call(rbind, rows)
write.csv(comp, "output/comparison_lasso_estimates.csv", row.names = FALSE)


## ---------------------------------------------------------------------
## Text version: one table per outcome, "-" = term not in that model
## ---------------------------------------------------------------------
fmt <- function(x) ifelse(is.na(x), "-", sprintf("%.3f", x))
out_txt <- "output/comparison_lasso_estimates.txt"
con <- file(out_txt, open = "wt")
w <- function(...) cat(..., "\n", file = con, sep = "")

w("Penalised estimates from the three lasso methods, at each BIC-optimal lambda")
w("beta = log-odds coefficient; OR = exp(beta). 0 = shrunk out by that method.")
w("'-' = term not in that outcome's model. Reference categories: see output/variable_dictionary.csv.")
w("")
for (o in outcomes) {
  d <- comp[comp$outcome == o, ]
  w("==============================================================================")
  w(o)
  w("==============================================================================")
  w(sprintf("%-50s %12s %12s %12s", "term", "glmmLasso", "group", "sparse grp"))
  for (k in seq_len(nrow(d))) {
    w(sprintf("%-50s %12s %12s %12s", d$term[k],
              fmt(d$glmmLasso_beta[k]), fmt(d$group_beta[k]), fmt(d$sparse_beta[k])))
  }
  w(sprintf("%-50s %12d %12d %12d", "non-zero terms (excl. intercept)",
            sum(d$glmmLasso_beta[-1] != 0, na.rm = TRUE),
            sum(d$group_beta[-1] != 0, na.rm = TRUE),
            sum(d$sparse_beta[-1] != 0, na.rm = TRUE)))
  w("")
}
close(con)

cat("Wrote output/comparison_lasso_estimates.csv and .txt\n")
