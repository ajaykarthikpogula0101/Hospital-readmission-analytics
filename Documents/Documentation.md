# Hospital Readmission Analytics Pipeline

This project designs an end-to-end data engineering and analytics pipeline to study hospital readmissions.
It ingests raw patient data into Snowflake, transforms it into a clean star schema with dbt, orchestrates with Airflow, and powers BI dashboards to identify readmission risk factors.

---

## Executive Summary

Hospital readmissions are a critical challenge for healthcare providers, driving up costs and impacting patient outcomes.
This project builds a modern data pipeline that ingests raw hospital visit records into Snowflake, transforms them with dbt, automates refreshes with Airflow, and delivers Power BI dashboards for hospital leadership.

On top of the pipeline, predictive models were developed to identify patients at high risk of 30-day readmission.
The solution combines data engineering, analytics, and machine learning in a single portfolio project, demonstrating how modern data stack tools can deliver both operational efficiency and business insights.

---

## Goals

- Automate ingestion into Snowflake
- Transform into a clean star schema using dbt
- Orchestrate daily refresh with Airflow
- Visualize KPIs via Power BI
- Document and share results on GitHub

---

## Tech Stack

| Category | Tools |
|----------|-------|
| Storage & Processing | Snowflake (RAW → STAGING → ANALYTICS) |
| Transformations | dbt-core (Snowflake adapter) |
| Orchestration | Apache Airflow (Astronomer) |
| BI / Dashboards | Power BI |
| Scripting | Python + Snowflake Connector |
| Version Control | GitHub |

---

## Related Repositories

- **dbt Models:** [Hospital_Readmission_dbt](https://github.com/ajaykarthikpogula0101/Hospital_Readmission_dbt)
- **Airflow Orchestration:** [Hospital_Readmission_AirflowOrchestration](https://github.com/ajaykarthikpogula0101/Hospital_Readmission_AirflowOrchestration)

---

## Phase 1 — Dataset Exploration

Source: Kaggle "Diabetes Hospital Readmission" dataset

**Key Findings**
- Shape: 101,766 rows × 50 columns
- `encounter_id` is unique; `patient_nbr` repeats (multiple visits per patient)
- `weight` dropped (97% missing); `medical_specialty` and `payer_code` partially missing
- `?` placeholders mapped to NULL or "Unknown" categories
- ICD-9 diagnosis codes grouped into 10 broad categories
- Target column: `readmitted_flag` (1 = readmitted within 30 days, 0 = otherwise)
- Class imbalance: ~11% positive readmission rate
- Medications standardized to `no / steady / up / down`

---

## Phase 2 — Snowflake Setup

**Configuration**
- Database: `HOSPITAL_DB`
- Schemas: `RAW`, `STAGING`, `ANALYTICS`
- Warehouse: `COMPUTE_WH`
- Role: `HOSPITAL_ROLE`
- Stage and file format created for CSV ingestion into `RAW.PATIENT_VISITS` (50 columns)

**Roadblocks and Fixes**

| Issue | Fix |
|-------|-----|
| dbt privilege errors — could not create objects | Granted schema OWNERSHIP to HOSPITAL_ROLE |
| Airflow SnowflakeOperator import error | Corrected import path |

---

## Phase 3 — Data Ingestion

**Approach**
- Used SnowSQL `PUT` and `COPY INTO` commands
- Partitioned files simulate daily ingestion (e.g., `2025-08-25.csv`)
- Audit log (`AUDIT.LOAD_LOGS`) tracks filename, execution date, row count, and load time

**Roadblocks and Fixes**

| Issue | Fix |
|-------|-----|
| Wrong date loaded (execution_date + 1 offset) | Adjusted to execution_date - 1 |
| Duplicate loads causing fact_visits to grow incorrectly | Added TRUNCATE RAW step before each load |
| Audit log mismatch with actual fact counts | Extended DAG to log fact table counts post-dbt |

---

## Phase 4 — dbt Setup and Modeling

**Project Structure**
- Staging: `stg_patient_visits`
- Dimensions: `dim_patients`, `dim_diagnosis`, `dim_admission`, `dim_discharge`, `dim_medical_specialty`, `dim_payer`
- Facts: `fact_visits`, `fact_medications`
- Tests: unique, not_null, accepted_values; custom threshold test for Unknown categories

**dim_patients Logic**
- Problem: patients with multiple encounters caused demographic duplicates
- Rule applied: latest encounter wins; backfill Unknowns with most recent valid value
- Implementation: window functions (`ROW_NUMBER`, `FIRST_VALUE`)
- Result: ~71K unique patients, surrogate key added, Unknown categories reduced

**Roadblocks and Fixes**

| Issue | Fix |
|-------|-----|
| dbt privilege errors | Granted schema ownership |
| Deprecation warnings for `accepted_values` tests | Updated YAML syntax with `arguments:` |
| dim_patients duplicates | Applied latest-encounter business rule with window functions |
| Unknown threshold test failures | Converted failing test to WARN |

**Validation**
- 38 tests passed, 1 warning (expected behavior)
- All fact and dimension tables correctly built in ANALYTICS schema

---

## Phase 5 — Orchestration and Validation

**Airflow DAG Steps**
1. Truncate RAW schema
2. Load previous day's file
3. Validate row count
4. Insert audit log entry
5. Trigger dbt run
6. Update audit log with post-dbt fact counts
7. Run dbt tests

**Roadblocks and Fixes**

| Issue | Fix |
|-------|-----|
| DAG not appearing in Airflow UI | Upgraded `apache-airflow-providers-snowflake` to 5.6.0 |
| Audit log missing post-dbt fact counts | Added update step after dbt run completes |
| Syntax error in SQL health check | Corrected placement of audit block in DAG |

**Result**
- DAG executes cleanly end-to-end
- Fact tables grow incrementally with each daily run
- Audit log aligned with RAW load counts and post-dbt fact counts

---

## Post-Phase 5 Enhancements

**Prod Rollout and Schema Alignment**
- Configured dbt profiles: dev → DEV schema, prod → ANALYTICS schema
- Added explicit `schema=` configs inside dbt models for precise layer routing
- Rebuilt all models in prod with `dbt run --target prod --full-refresh`

**Admission Type Correction**
- Confirmed `admission_type_id = 6` means "NULL / Not Recorded" per dataset dictionary
- Relabeled as "Unknown / Not Recorded" in `dim_admission` for business clarity

**Unknown Category Labeling**
- Race `?` → "Unknown Race"
- Gender invalid values → "Unknown Gender"
- Missing Age → "Unknown Age"
- Ensures distinct, unambiguous labels across Power BI legends

**Dashboard QA**
- Verified KPI alignment: 102K encounters, 72K patients, 11% readmission rate, 4.4 days avg LOS
- Filters renamed to business terms: Age Group, Gender, Race, Admission Type
- Standardized KPI card styling for visual consistency
- Decision: retain Unknown categories in dashboards as data quality signals

---

## Phase 6 — BI Dashboard

**Connection**
- Power BI connected directly to Snowflake ANALYTICS schema

**Key KPIs**

| Metric | Value |
|--------|-------|
| Readmission Rate (30 Days) | 11% |
| Average Length of Stay | 4.4 days |
| Total Encounters | ~102K |
| Unique Patients | ~72K |

**Breakdowns**
- **By Age Group:** Elderly patients (70–90) and young adults (20–30) show higher readmission rates
- **By Gender and Race:** Rates broadly consistent across groups; Unknown categories surfaced transparently
- **By Admission Type:** Emergency encounters dominate (53%); "Unknown / Not Recorded" shown separately

**Design Decisions**
- Unknown categories retained and clearly labeled — critical for data quality transparency
- Diagnosis role-playing dimensions (DIM_DIAGNOSIS1/2/3) identified as best practice for future multi-diagnosis analysis
- No time-series trends included — dataset lacks admission and discharge date fields

---

## Snowflake Setup (Screenshots)

**Database and Schemas**
![Snowflake Database](diagrams/snowflake/snowflake_database.PNG)

**RAW, STAGING, ANALYTICS**
![Snowflake Schemas](diagrams/snowflake/sf_schema_tables.PNG)

**Stage and File Format**
![Snowflake Stage](diagrams/snowflake/snowflake_stage.PNG)

**Analytics Layer**
![Snowflake Analytics](diagrams/snowflake/snowflake_analytics.PNG)

---

## dbt Transformations (Screenshots)

**Lineage Graph**
![dbt Lineage](diagrams/dbt/dbt_lineage.PNG)

**Model Documentation**
![dbt Docs](diagrams/dbt/dbt.PNG)

---

## Dashboard Preview

**Power BI Executive Summary**
![Dashboard](dashboards/powerbi_dashboard.PNG)

---

## Phase 7 — Predictive Modeling and Evaluation

**Objective**
Predict 30-day hospital readmission using Snowflake-transformed data.
Multiple algorithms were tested, class imbalance was addressed, hyperparameters were tuned, and explainability methods (SHAP, EBM) were applied.

**Dataset**
- Source: `fact_visits` joined with dimension tables from Snowflake ANALYTICS schema
- Final dataset: ~102K encounters, ~72K patients
- Target: `readmitted_flag` (1 = readmitted within 30 days)
- Class distribution: 89% negative, 11% positive — highly imbalanced
- Split: patient-level 80/20 to prevent data leakage

**Baseline Models**

| Model | ROC-AUC | Recall | Notes |
|-------|---------|--------|-------|
| Logistic Regression | ~0.55 | ~0.50 | Weak baseline features |
| Random Forest | ~0.52 | ~0.00 | Predicted majority class only |
| XGBoost (default) | ~0.54 | ~0.50 | Only slightly above random |

**Enriched Dataset Results**
- Added diagnoses, admission/discharge info, payer, specialty, labs, 23 drug features (~200 features total)
- Logistic Regression with class weights: AUC ~0.67, Recall ~0.57
- Confirmed discharge type, age, and diagnoses as strongest predictors

**Imbalance Handling**
- Tested: undersampling, SMOTE, class weights, threshold tuning
- Decision: prioritize recall — catching at-risk patients is more critical than precision in healthcare

**Hyperparameter Tuning (XGBoost)**
- Method: RandomizedSearchCV (30 iterations, 5-fold cross-validation)
- Parameters tuned: `max_depth`, `n_estimators`, `learning_rate`, `subsample`, `colsample_bytree`, `min_child_weight`, `gamma`
- Best cross-validated ROC-AUC: ~0.68
- Final test performance: **ROC-AUC 0.684–0.687**

**Alternative Models**

| Model | ROC-AUC | Notes |
|-------|---------|-------|
| LightGBM (weighted) | ~0.68 | Similar to XGBoost |
| CatBoost | ~0.68–0.69 | Did not consistently outperform XGBoost |
| EBM | ~0.67 | Lower performance, higher interpretability |

**Explainability**
- SHAP (XGBoost, LightGBM, CatBoost): discharge disposition, age group, diagnosis categories, and medication count identified as top global drivers
- EBM feature curves confirmed medical intuition: elderly patients, diabetes, and complex discharges = higher readmission risk
- Logistic Regression coefficients validated clinical logic (e.g., hospice discharge → negative readmission probability)

**Final Model Selection**
- Best model: XGBoost with reduced features, class weighting, and hyperparameter tuning
- Test ROC-AUC: ~0.687
- Recall prioritized over precision to align with clinical objectives

---

## Results

- Successfully ingested and processed ~102,000 hospital encounters into Snowflake
- Designed a robust star schema (`fact_visits`, `dim_patients`, `dim_diagnosis`, `dim_admission`) to power analytics
- dbt lineage graph and documentation provided full transparency across 10+ models and 40+ tests
- Automated daily refresh with Airflow DAGs ensured reproducibility and near real-time insights
- Best predictive model (XGBoost, tuned and weighted) achieved ROC-AUC ~0.687 with recall prioritized
- Power BI executive dashboard delivered for hospital leadership with readmission rates, LOS analysis, and patient volume insights

**Business Impact:** This pipeline demonstrates how modern data engineering and ML workflows can help hospitals reduce readmission costs, improve patient care, and highlight upstream data quality gaps.

---

## Lessons Learned

| Area | Lesson |
|------|--------|
| Snowflake Privileges | Schema ownership required for dbt to build objects |
| Airflow DAG | Fixed import path, upgraded provider package, corrected execution_date logic |
| Audit Logging | Extended to track fact counts post-dbt run |
| dbt Tests | Fixed deprecation warnings; allowed WARN for Unknown categories exceeding 5% |
| dim_patients | Resolved duplicates by applying latest-encounter business rule with window functions |
| Prod Rollout | Schema alignment issues fixed by adding explicit schema configs in dbt models |
| Admission Type | `admission_type_id = 6` is a valid dataset code; relabeled to avoid misleading NULLs |
| Unknown Categories | Relabeled as Unknown Race, Unknown Gender, Unknown Age for clarity in Power BI |
| Data Type Joins | Staging stored admission_type_id as text; dim stored as number — casting fixed blank joins |
| Diagnosis Dimensions | Role-playing dimensions (DIM_DIAGNOSIS1/2/3) required to avoid ambiguous relationships |
| Dashboard QA | Business-friendly filter labels and consistent card styling improved executive readability |
| Data Quality Philosophy | Unknowns retained as data quality signals rather than hidden or dropped |

---

## Business Value

- Identifies patients at high risk of 30-day readmission
- Highlights critical diagnosis categories driving readmissions (circulatory, diabetes)
- Enables hospitals to target interventions and reduce costs
- Surfaces data quality issues (Unknown payer codes, specialties, labs) for operational improvement

---

## Author

**Ajay Karthik Pogula**
Applied Machine Learning | Data Engineering
[GitHub](https://github.com/ajaykarthikpogula0101)

---


