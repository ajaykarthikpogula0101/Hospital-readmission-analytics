# 🏥 Hospital Readmission Analytics – Full Documentation (Phases 1–5)

---

## ✅ Phase 1 – Dataset Exploration

*(From Kaggle “Diabetes Hospital Readmission” dataset)*

**Cell 1: Importing Libraries**

**Cell 2: Reading & Previewing Data**
- Demographics: race, gender, age, weight
- Hospitalization details: admission_type_id, discharge_disposition_id, etc.
- Medications, diagnoses, target: readmitted
- Edge cases: `?` and `None` → need NULL; columns with hyphens not dbt-friendly; admission/discharge are coded integers.

**Cell 3: Shape & Info**
- Shape: (101,766, 50)
- encounter_id unique; patient_nbr repeats (multiple visits)
- Most columns are `object` type, labs are sparse

**Cell 4: Missing Values**
- max_glu_serum → ~96k missing
- A1Cresult → ~84k missing
- Many `?` placeholders (not actual NULLs)

**Cell 5: Placeholder Missing Check**
- weight ~97% missing → drop
- medical_specialty ~49% missing
- payer_code ~40% missing
- race, diag_1–3 have some missing but usable

**Cell 6: Uniqueness & Identifiers**
- encounter_id unique → PK for visits
- patient_nbr shows multiple encounters

**Cell 7: Race & Gender Cleaning**
- Race: mapped, `?` → Unknown
- Gender: balanced, 3 invalid mapped to Unknown

**Cell 8: Medical Specialty & Payer Code**
- `?` → Unknown; rare categories grouped into "Other"
- Medical specialty → 18 groups
- Payer code → 13 groups

**Cell 9: Age & Weight**
- Weight dropped (too incomplete)
- Age ranges cleaned into “20-30”, … “90-100”

**Cell 10: Diagnosis Cleaning**
- ICD-9 grouped into 10 broad categories
- diag_1 → Circulatory (30k), Respiratory (14k), Diabetes (9k)
- Created clean `dim_diagnosis` categories

**Cell 11: Standardization**
- max_glu_serum, A1Cresult standardized to consistent categories
- Medications standardized to `no/steady/up/down`
- change → yes/no, diabetesMed → yes/no
- Target column: `readmitted_flag` (1 = <30 days, 0 = otherwise)

**Cell 14: EDA Summary**
- Readmission imbalance (~11%)
- Age skewed to 60–90
- Diagnosis: circulatory & diabetes dominate
- Outliers exist in meds/labs → keep for now

**Notes:**
- Class imbalance to be handled later (Phase 4 modeling)
- Outliers not capped (warehouse = source of truth)

---

## ✅ Phase 2 – Snowflake Setup

**Setup Steps**
- Database: `HOSPITAL_DB`
- Schemas: `RAW`, `STAGING`, `ANALYTICS`
- Warehouse: `COMPUTE_WH`
- Role: `HOSPITAL_ROLE`
- Stage & File Format:
  ```sql
  CREATE FILE FORMAT RAW.CLEANED_CSV_FORMAT TYPE = 'CSV' ...;
  CREATE STAGE RAW.HOSPITAL_STAGE FILE_FORMAT = RAW.CLEANED_CSV_FORMAT;
  ```
- RAW table: `RAW.PATIENT_VISITS` (50 cols)

**Roadblocks & Fixes**
1. ❌ Privilege issues – dbt couldn’t create objects.
   - ✅ Fix: Gave `HOSPITAL_ROLE` **OWNERSHIP** on schemas.
2. ❌ Airflow import error (`SnowflakeOperator`).
   - ✅ Fix: Corrected import path.

---

## ✅ Phase 3 – Data Ingestion

**Setup Steps**
- Used SnowSQL `PUT` + `COPY INTO`.
- Partitioned files simulate daily ingestion (`2025-08-25.csv`, `2025-08-26.csv`).
- Audit log (`AUDIT.LOAD_LOGS`) tracks filename, execution date, row count, load time.

**Roadblocks & Fixes**
1. ❌ Wrong date loaded (execution_date + 1).
   - ✅ Fix: Adjusted to execution_date - 1.
2. ❌ Duplicate loads (fact_visits growing incorrectly).
   - ✅ Fix: Added TRUNCATE RAW step before load.
3. ❌ Audit log mismatch.
   - ✅ Fix: Extended DAG to log fact table counts post-dbt.

---

## ✅ Phase 4 – dbt Setup & Modeling

**Setup**
- dbt project: `hospital_readmission_dbt`
- Configured schemas: staging → STAGING, marts → ANALYTICS
- Models:
  - Staging: `stg_patient_visits`
  - Dimensions: `dim_patients`, `dim_diagnosis`, `dim_admission`, `dim_discharge`, `dim_medical_specialty`, `dim_payer`
  - Facts: `fact_visits`, `fact_medications`
- Tests: unique, not_null, accepted_values; custom threshold test for Unknowns.

**Detailed Dimensions**
- **dim_diagnosis**: 10 categories from ICD-9; static lookup table.
- **dim_admission**: 8 codes mapped to labels.
- **dim_patients**:
  - Problem: duplicates (patients with multiple demographics)
  - Rule: take latest encounter; backfill Unknowns with recent valid value
  - Implementation: window functions (row_number, first_value)
  - Result: ~71k unique patients, Unknowns reduced, surrogate key added.

**Roadblocks & Fixes**
1. ❌ Privilege errors – dbt couldn’t build.
   - ✅ Fix: Granted schema ownership.
2. ❌ Deprecation warnings for `accepted_values` tests.
   - ✅ Fix: Updated YAML syntax with `arguments:`.
3. ❌ dim_patients duplicates.
   - ✅ Fix: Applied latest-encounter business rule with window functions.
4. ❌ Unknowns test failed.
   - ✅ Fix: Converted to WARN instead of FAIL.

**Validation**
- 38 tests passed, 1 warning (expected)
- Fact + dim tables correctly built in ANALYTICS

---

## ✅ Phase 5 – Orchestration & Validation

**Setup**
- Airflow DAG (`daily_stage_loader_http`) steps:
  1. Truncate RAW
  2. Load yesterday’s file
  3. Validate row count
  4. Insert audit log
  5. Trigger dbt run
  6. Update audit log with fact counts
  7. Run dbt tests

**Roadblocks & Fixes**
1. ❌ DAG not visible in Airflow UI.
   - ✅ Fix: Upgraded `apache-airflow-providers-snowflake` to 5.6.0.
2. ❌ Audit log missing fact counts.
   - ✅ Fix: Added update step after dbt run.
3. ❌ Syntax error in SQL health check.
   - ✅ Fix: Corrected placement of audit block in DAG.

**Result**
- DAG executes cleanly.
- Fact tables grow incrementally.
- Audit log aligned with RAW + facts.

---

## 📊 Current Status
- End-to-end pipeline running in Prod (ANALYTICS).
- Snowflake schemas: RAW → STAGING → ANALYTICS.
- dbt models clean, tested, and validated.
- Airflow orchestrates daily ingestion + dbt.
- Audit logs validated with fact row counts.

---
After the free trial of dbt cloud and astronomer airflow cloud, had to make some changes, so set up dbt and airflow locally.

## 🔧 Enhancements & Dashboard QA (Post-Phase 5)

**1. Prod Rollout & Schema Alignment**  
- Configured dbt profiles with **dev → DEV_STV** and **prod → ANALYTICS**.  
- Added `schema=` configs inside dbt models to enforce staging → STAGING and analytics → ANALYTICS.  
- Rebuilt models in prod with `dbt run --target prod --full-refresh`.  

**2. Admission Type “NULL” Code**  
- Confirmed that `admission_type_id = 6` means **NULL (not recorded)** in dataset dictionary.  
- Relabeled as **“Unknown / Not Recorded”** in `dim_admission` for business clarity.  

**3. Distinguishing Unknowns in Patient Demographics**  
- Race: relabeled “?” → **Unknown Race**  
- Gender: 3 invalid values mapped to **Unknown Gender**  
- Age: missing values mapped to **Unknown Age**  
- Ensures clarity in Power BI legends and avoids duplicate “Unknown” categories.  

**4. Dashboard QA in Power BI**  
- Verified KPI alignment: 102K encounters, 72K patients, 11% readmissions, 4.4 days LOS.  
- Filters renamed to business terms (“Age Group,” “Gender,” “Race,” “Admission Type”).  
- Standardized KPI card styling for consistency.  
- Heading section updated with banner-style title for professional polish.  
- Chose to **keep Unknowns visible** for transparency, aligning with data quality best practice.  

**5. Diagnosis Categories (Optional)**  
- Explored linking diag1_id, diag2_id, diag3_id.  
- Best practice = use **role-playing dimensions** (DIM_DIAGNOSIS1/2/3) to avoid ambiguous joins in BI tools.  
- For executive summary dashboard, analysis limited to **primary diagnosis only**.  

---

## 📊 Updated Dashboard Insights
- Readmission rate: 11% (within 30 days)  
- Average length of stay: 4.4 days  
- Highest risk: elderly patients (70–90), Emergency admissions  
- Unknown categories surfaced clearly for Race, Gender, and Admission Type → ensuring data completeness transparency  

---

## 📌 Key Takeaway
- **Unknowns are not noise — they are data quality signals.**  
- By surfacing them clearly, dashboards build **trust** and guide improvements in upstream data collection.  

---

## 🔜 Phase 6 – BI Dashboard
Planned metrics (Power BI / Streamlit):
- Readmission rate by diagnosis category
- Readmission rate by age group
- Admission type vs readmissions
- Avg stay duration (readmitted vs not)
- Patient volume trend
- Filters: month, age, insurance type


**Setup**
- Connected Power BI to Snowflake `ANALYTICS` schema.  
- Built executive summary dashboard with clean KPIs and demographic/admission breakdowns.  
- Applied business-friendly naming for filters and categories.  
- Ensured Unknowns were surfaced clearly instead of hidden.  

**Dashboard Metrics & Insights**
- **Readmission Rate (30 days):** 11%  
- **Average Length of Stay:** 4.4 days  
- **Encounters:** ~102K total  
- **Unique Patients:** ~72K  

**Breakdowns**
- **By Age Group:** elderly (70–90) and young adults (20–30) at higher risk  
- **By Gender & Race:** readmission rates broadly consistent, with Unknown Race/Gender surfaced transparently  
- **By Admission Type:** dominated by Emergency encounters; “Unknown / Not Recorded” shown separately  

**Design Improvements**
- Standardized KPI card styling (consistent background and font).  
- Filters renamed and aligned: Age Group, Gender, Race, Admission Type.  
- Dashboard title redesigned with banner-style heading for executive readability.  
- Decision: keep Unknowns visible → critical for data quality transparency.  

**Notes**
- No time-series trends included (dataset has no admission/discharge dates).  
- Diagnosis categories explored but not included in summary view (requires role-playing dimensions in Power BI).  


---

## 📌 Lessons Learned (Roadblocks Recap)
- **Connection & Privileges:** Needed schema ownership for dbt to build.
- **Airflow DAG:** Fixed import path, upgraded provider package, corrected execution_date logic.
- **Audit Logging:** Extended to track fact counts post-dbt.
- **dbt Tests:** Fixed deprecation warnings; allowed WARN for >5% Unknowns.
- **dim_patients:** Resolved duplicates by defining business rule (latest encounter wins).
- **Prod Rollout:** Discovered schema alignment issues between staging and analytics; fixed by adding explicit `schema=` configs in dbt models.
- **Admission Type:** Learned that `admission_type_id = 6` is a valid dataset code (“NULL / Not Recorded”); relabeled in `dim_admission` to avoid misleading NULLs in dashboards.
- **Unknown Categories:** Initially surfaced as plain “Unknown” across race and gender; relabeled as **Unknown Race**, **Unknown Gender**, and **Unknown Age** for clarity.
- **Data Types in Joins:** Found staging stored `admission_type_id` as text while dim stored as number; casting fixed failed joins that led to blanks in Power BI.
- **Diagnosis Dimensions:** Attempting to join diag1/2/3 to a single dim caused ambiguous relationships in Power BI; best practice is to use role-playing dimensions (DIM_DIAGNOSIS1/2/3).
- **Dashboard QA:** Discovered readability issues with filter labels and card styling; fixed with business-friendly names, consistent formatting, and a banner-style heading.
- **Data Quality Philosophy:** Decided to keep Unknowns visible in dashboards as signals of upstream data issues, ensuring transparency and trust.


---

## ✅ Phase 7 – Modeling & Evaluation

### 🎯 Objective
Predict **30-day hospital readmission** using Snowflake-transformed data.  
We tested multiple algorithms, handled imbalance, tuned parameters, and applied explainability methods (SHAP, EBM).

---

### Step 1: Dataset Prep
- Source: `fact_visits` + dimensions from **Snowflake Analytics schema**  
- Final dataset: ~102K encounters, ~72K patients  
- Target: **readmitted_flag** (1 = readmitted <30 days, 0 = otherwise)  
- Distribution: 0 → 89%, 1 → 11% → **highly imbalanced**  
- Split: **patient-level 80/20** to avoid leakage  

---

### Step 2: Baseline Models
- Features: race, gender, age group, num_medications, time_in_hospital  
- Results:  
  - **Logistic Regression** → AUC ~0.55, Recall ~0.50, Precision ~0.12  
  - **Random Forest** → AUC ~0.52, predicted mostly majority class (Recall = 0)  
  - **XGBoost (default)** → AUC ~0.54, Recall ~0.50, Precision ~0.12  
- ⚠️ Baseline features were too weak and performance was only slightly better than random.  

---

### Step 3: Enriched Dataset
- Added: diagnoses, admission/discharge info, payer, specialty, labs, 23 drug features  
- One-hot + scaling → ~200 features  
- **Logistic Regression**:  
  - AUC ~0.62 (no weights)  
  - With class weights → AUC ~0.67, Recall ~0.57, Precision ~0.18  
- Confirms that **discharge type, age, and diagnoses** are the strongest predictors.  

---

### Step 4: Imbalance Handling
- Tested: **undersampling, SMOTE, class weights, threshold tuning**  
- Undersampling and SMOTE boosted recall but lowered precision significantly.  
- Threshold tuning confirmed the trade-off:  
  - **Low thresholds** → higher recall but many false alarms  
  - **High thresholds** → better precision but many missed readmissions  
- Decision: prioritize **recall** since catching risky patients is more important in healthcare.  

---

### Step 5: Hyperparameter Tuning (XGBoost)
- Used **RandomizedSearchCV** (30 iterations, 5-fold CV)  
- Tuned parameters: `max_depth`, `n_estimators`, `learning_rate`, `subsample`, `colsample_bytree`, `min_child_weight`, `gamma`  
- Best cross-validated ROC-AUC: ~0.68  
- Refit tuned model on full data with `scale_pos_weight` to handle imbalance  
- **Result:** Weighted & tuned XGBoost achieved **ROC-AUC ≈ 0.684–0.687** on the test set  
- This was the best performing model in the project  

---

### Step 6: Alternative Algorithms
- **LightGBM** with class weighting achieved ROC-AUC ~0.68  
- **CatBoost** achieved similar ROC-AUC (~0.68–0.69), but did not outperform XGBoost  
- **EBM (Explainable Boosting Machine)** reached ~0.67, but prioritized interpretability over raw performance  
- Conclusion: alternatives confirmed similar performance, but **none exceeded tuned XGBoost**  

---

### Step 7: Explainability
- **Logistic Regression coefficients**: validated clinical sense (children = very low risk; hospice discharges negative; certain transfer discharges positive)  
- **SHAP (XGBoost, LightGBM, CatBoost):**  
  - Global importance → discharge disposition, age group, diagnoses, number of medications  
  - Local plots explained why specific patients were flagged as high-risk  
- **EBM (Explainable Boosting Machine):**  
  - Feature curves made results easy to interpret for clinicians  
  - Trends confirmed medical intuition: elderly + diabetes + complex discharges = higher risk  

---

### 📌 Final Outcome
- Baseline models were weak (AUC ~0.55).  
- Enriched dataset improved performance significantly (AUC ~0.67).  
- **Best model:** **XGBoost with reduced features, class weighting, and hyperparameter tuning**, achieving **ROC-AUC ~0.687**.  
- Supporting models (LightGBM, CatBoost, EBM) provided validation and interpretability but did not surpass XGBoost.  
- Key drivers of readmission: **discharge disposition, age, diagnosis categories, labs, and medications**.  
- **Recall was prioritized** over precision, aligning with hospital needs to catch as many at-risk patients as possible.  
- Unknown categories were kept visible → treated as **data quality signals** rather than noise.  

---




