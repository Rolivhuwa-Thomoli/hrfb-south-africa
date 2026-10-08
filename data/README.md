# Data

This project uses the **2016 South Africa Demographic and Health Survey (SADHS)**,
Individual (women's) Recode, file `ZAIR71FL.SAV` (SPSS format).

The data is **not included in this repository**. The DHS Program's terms of use
do not allow the data to be redistributed. To reproduce the analysis:

1. Register for free at <https://dhsprogram.com/data/new-user-registration.cfm> and request access to the South Africa 2016 survey.
2. Download the Individual Recode in SPSS format (`ZAIR71SV.zip`).
3. Unzip it so the file sits at `ZAIR71SV/ZAIR71FL.SAV` in the repository root.
4. From the repository root, run `Rscript run_all.R`.

Only aggregated results (prevalence tables, test statistics and odds ratios) are published in `results/` and `figures/`.

**Citation:** National Department of Health (NDoH), Statistics South Africa (Stats SA), South African Medical Research Council (SAMRC), and ICF. 2019. *South Africa Demographic and Health Survey 2016.* Pretoria, South Africa, and Rockville, Maryland, USA: NDoH, Stats SA, SAMRC, and ICF.
