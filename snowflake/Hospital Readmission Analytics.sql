-----------------------------------------------------------------
-- HOSPITAL READMISSION ANALYTICS – MASTER SQL SCRIPT
-- Author: <Srilekha Tirumala Vinjamoori>
-- Purpose: End-to-end setup of Snowflake environment,
--          ingestion, role management, and sanity checks.
-----------------------------------------------------------------


/***************************************************************
         ENVIRONMENT & CONTEXT SETUP
****************************************************************/
use role sysadmin;
select current_role();

SHOW WAREHOUSES LIKE 'COMPUTE_WH';
SELECT CURRENT_WAREHOUSE();


-- Create the project database
CREATE DATABASE IF NOT EXISTS HOSPITAL_DB
  COMMENT = 'Hospital Readmission Analytics';

-- Set your working context
USE DATABASE HOSPITAL_DB;

-- Quick checks
SHOW DATABASES LIKE 'HOSPITAL_DB';
SELECT CURRENT_DATABASE();

-- Create rooms (schemas) in our HOSPITAL_DB

CREATE SCHEMA IF NOT EXISTS RAW;
CREATE SCHEMA IF NOT EXISTS STAGING;
CREATE SCHEMA IF NOT EXISTS ANALYTICS;

-- Work in RAW for now
USE SCHEMA RAW;

-- Quick checks
SHOW SCHEMAS IN DATABASE HOSPITAL_DB;
SELECT CURRENT_SCHEMA() AS working_schema;


-- Step 5: Quick sanity checks
SHOW WAREHOUSES LIKE 'COMPUTE_WH';
SHOW DATABASES LIKE 'HOSPITAL_DB';
SHOW SCHEMAS IN DATABASE HOSPITAL_DB;


/***************************************************************
          ROLE & SECURITY SETUP
****************************************************************/


-- Use the role that can create/grant roles
USE ROLE SECURITYADMIN;

-- Create a dedicated project role
CREATE ROLE IF NOT EXISTS HOSPITAL_ROLE;

-- (Optional) give this role to your user so you can use it
-- Replace <YOUR_USERNAME> with your Snowflake login name
GRANT ROLE HOSPITAL_ROLE TO USER SRITV;

-- Switch back to the role that owns/creates objects
USE ROLE SYSADMIN;

-- Let the role use our warehouse + database
GRANT USAGE, MONITOR ON WAREHOUSE COMPUTE_WH TO ROLE HOSPITAL_ROLE;
GRANT USAGE ON DATABASE HOSPITAL_DB TO ROLE HOSPITAL_ROLE;

-- Let the role use our schemas
GRANT USAGE ON SCHEMA HOSPITAL_DB.RAW TO ROLE HOSPITAL_ROLE;
GRANT USAGE ON SCHEMA HOSPITAL_DB.STAGING TO ROLE HOSPITAL_ROLE;
GRANT USAGE ON SCHEMA HOSPITAL_DB.ANALYTICS TO ROLE HOSPITAL_ROLE;

-- Allow creating the common things we’ll need
GRANT CREATE TABLE, CREATE STAGE, CREATE FILE FORMAT ON SCHEMA HOSPITAL_DB.RAW TO ROLE HOSPITAL_ROLE;
GRANT CREATE TABLE ON SCHEMA HOSPITAL_DB.STAGING TO ROLE HOSPITAL_ROLE;
GRANT CREATE VIEW, CREATE TABLE ON SCHEMA HOSPITAL_DB.ANALYTICS TO ROLE HOSPITAL_ROLE;

USE ROLE ACCOUNTADMIN;
-- Future-proof: anything new we add later is accessible
GRANT SELECT ON FUTURE TABLES IN SCHEMA HOSPITAL_DB.RAW TO ROLE HOSPITAL_ROLE;
GRANT SELECT ON FUTURE VIEWS  IN SCHEMA HOSPITAL_DB.ANALYTICS TO ROLE HOSPITAL_ROLE;


/***************************************************************
        RAW TABLE & STAGE SETUP
****************************************************************/

USE ROLE HOSPITAL_ROLE;          -- or HOSPITAL_ROLE if you granted it to yourself
USE WAREHOUSE COMPUTE_WH;
USE DATABASE HOSPITAL_DB;
USE SCHEMA RAW;

CREATE OR REPLACE TABLE RAW.PATIENT_VISITS (
  encounter_id STRING,
  patient_nbr STRING,
  race STRING,
  gender STRING,
  age STRING,
  admission_type_id STRING,
  discharge_disposition_id STRING,
  admission_source_id STRING,
  time_in_hospital STRING,
  payer_code STRING,
  medical_specialty STRING,
  num_lab_procedures STRING,
  num_procedures STRING,
  num_medications STRING,
  number_outpatient STRING,
  number_emergency STRING,
  number_inpatient STRING,
  diag_1 STRING,
  diag_2 STRING,
  diag_3 STRING,
  number_diagnoses STRING,
  max_glu_serum STRING,
  A1Cresult STRING,
  metformin STRING,
  repaglinide STRING,
  nateglinide STRING,
  chlorpropamide STRING,
  glimepiride STRING,
  acetohexamide STRING,
  glipizide STRING,
  glyburide STRING,
  tolbutamide STRING,
  pioglitazone STRING,
  rosiglitazone STRING,
  acarbose STRING,
  miglitol STRING,
  troglitazone STRING,
  tolazamide STRING,
  examide STRING,
  citoglipton STRING,
  insulin STRING,
  "glyburide-metformin" STRING,
  "glipizide-metformin" STRING,
  "glimepiride-pioglitazone" STRING,
  "metformin-rosiglitazone" STRING,
  "metformin-pioglitazone" STRING,
  "change" STRING,
  diabetesMed STRING,
  readmitted STRING,
  readmitted_flag STRING
);


-- Quick check
DESC TABLE PATIENT_VISITS;

--- Phase 3: Data Ingestion

USE DATABASE HOSPITAL_DB;
USE SCHEMA RAW;

CREATE OR REPLACE STAGE hospital_stage
  COMMENT = 'Stage for hospital readmission CSV files';

SHOW STAGES IN SCHEMA RAW;

---Upload the file in the stage

LIST @hospital_stage;

CREATE OR REPLACE FILE FORMAT RAW.cleaned_csv_format
  TYPE = 'CSV'
  FIELD_DELIMITER = ','
  FIELD_OPTIONALLY_ENCLOSED_BY = '"'
  SKIP_HEADER = 1
  EMPTY_FIELD_AS_NULL = TRUE
  NULL_IF = ('', 'NULL', '?');


SHOW FILE FORMATS IN SCHEMA RAW;

/***************************************************************
         INGESTION FROM STAGE
****************************************************************/

-- peek at first 5 rows of the staged file
SELECT $1, $2, $3, $4, $5, $9, $49, $50
FROM @HOSPITAL_DB.RAW.hospital_stage
(FILE_FORMAT => RAW.cleaned_csv_format)
LIMIT 5;


-- Make sure we’re in the right place
USE DATABASE HOSPITAL_DB;
USE SCHEMA RAW;
USE WAREHOUSE COMPUTE_WH;

-- Preview how rows will land in the table (no insert yet)
COPY INTO RAW.PATIENT_VISITS
FROM @HOSPITAL_DB.RAW.hospital_stage
FILE_FORMAT = (FORMAT_NAME = RAW.cleaned_csv_format)
VALIDATION_MODE = RETURN_5_ROWS;


-- Load every file currently in the stage into the table
COPY INTO RAW.PATIENT_VISITS
FROM @HOSPITAL_DB.RAW.hospital_stage
FILE_FORMAT = (FORMAT_NAME = RAW.cleaned_csv_format)
ON_ERROR = 'CONTINUE';

-- Row count
SELECT COUNT(*) AS row_count FROM RAW.PATIENT_VISITS;

-- Peek to confirm alignment
SELECT encounter_id, patient_nbr, age, time_in_hospital, readmitted, readmitted_flag
FROM RAW.PATIENT_VISITS
LIMIT 10;

-- See copy history (optional)
SELECT * FROM INFORMATION_SCHEMA.LOAD_HISTORY
WHERE TABLE_NAME = 'PATIENT_VISITS'
ORDER BY LAST_LOAD_TIME DESC
LIMIT 5;


/***************************************************************
CHECKING GRANTS - ROLE & PERMISSIONS VALIDATION - DBT Connection
****************************************************************/

SELECT CURRENT_ACCOUNT();

SHOW ROLES;

SHOW GRANTS TO USER SRITV;
SHOW GRANTS TO ROLE HOSPITAL_ROLE;
SHOW GRANTS ON TABLE HOSPITAL_DB.RAW.PATIENT_VISITS;
SHOW GRANTS ON SCHEMA HOSPITAL_DB.RAW;
SHOW GRANTS ON DATABASE HOSPITAL_DB;

SHOW FUTURE GRANTS IN SCHEMA HOSPITAL_DB.RAW;
SHOW FUTURE GRANTS IN SCHEMA HOSPITAL_DB.STAGING;
SHOW FUTURE GRANTS IN SCHEMA HOSPITAL_DB.ANALYTICS;

-- Connecting to dbt

SELECT 
  CURRENT_ACCOUNT()        AS account_locator,   -- e.g., NIB97747
  CURRENT_ACCOUNT_NAME()   AS account_name,      -- e.g., SRITV_ACCT
  CURRENT_REGION()         AS region;            -- e.g., AWS_US_EAST_1


SELECT 
  LOWER(CURRENT_ACCOUNT()) || '.' ||
  REPLACE(
    REGEXP_REPLACE(LOWER(CURRENT_REGION()), '^(aws|azure|gcp)_', ''),
    '_','-'
  )  AS dbt_account_identifier;
-- Example output: nib97747.us-east-1   (this is what you paste into dbt Cloud)


select count(*) from HOSPITAL_DB.RAW.PATIENT_VISITS;

-- what role are you right now?
select current_role();

-- what grants does HOSPITAL_ROLE already have?
show grants to role HOSPITAL_ROLE;

-- who owns these schemas?
show grants on schema HOSPITAL_DB.RAW;
show grants on schema HOSPITAL_DB.STAGING;
show grants on schema HOSPITAL_DB.ANALYTICS;



---
-- Switch to SYSADMIN (current owner of schemas)
USE ROLE SYSADMIN;

-- Transfer ownership of RAW schema
GRANT OWNERSHIP ON SCHEMA HOSPITAL_DB.RAW
TO ROLE HOSPITAL_ROLE
REVOKE CURRENT GRANTS;

-- Transfer ownership of STAGING schema
GRANT OWNERSHIP ON SCHEMA HOSPITAL_DB.STAGING
TO ROLE HOSPITAL_ROLE
REVOKE CURRENT GRANTS;

-- Transfer ownership of ANALYTICS schema
GRANT OWNERSHIP ON SCHEMA HOSPITAL_DB.ANALYTICS
TO ROLE HOSPITAL_ROLE
REVOKE CURRENT GRANTS;

-- Transfer ownership of DEV schema
GRANT OWNERSHIP ON SCHEMA HOSPITAL_DB.DEV_STV
TO ROLE HOSPITAL_ROLE
REVOKE CURRENT GRANTS;



-- Run as HOSPITAL_ROLE (the new owner)
USE ROLE HOSPITAL_ROLE;

GRANT USAGE ON SCHEMA HOSPITAL_DB.RAW        TO ROLE SYSADMIN;
GRANT USAGE ON SCHEMA HOSPITAL_DB.STAGING    TO ROLE SYSADMIN;
GRANT USAGE ON SCHEMA HOSPITAL_DB.ANALYTICS  TO ROLE SYSADMIN;
GRANT USAGE ON SCHEMA HOSPITAL_DB.DEV_STV    TO ROLE SYSADMIN;



SHOW GRANTS ON DATABASE HOSPITAL_DB;
USE ROLE SYSADMIN;

-- let HOSPITAL_ROLE open the database
GRANT USAGE ON DATABASE HOSPITAL_DB TO ROLE HOSPITAL_ROLE;

-- (optional) if you want to go all-in, you can transfer ownership too:
GRANT OWNERSHIP ON DATABASE HOSPITAL_DB TO ROLE HOSPITAL_ROLE REVOKE CURRENT GRANTS;



-- dbt connection and set up completed

/***************************************************************
            UNIQUE VALUE CHECKS
****************************************************************/

select
    patient_nbr,
    count(*) as num_rows
from dim_patients
group by patient_nbr
having count(*) > 1
order by num_rows desc;

select *
from dim_patients
where patient_nbr = 2163357;

select * from dim_diagnosis;

select * from dim_admission;

-- Patient demographics
select race, count(*) from dim_patients group by race;

-- Readmission rate by admission type
select a.admission_type, avg(readmitted_flag) as readmission_rate
from fact_visits f
join dim_admission a on f.admission_type_id = a.admission_type_id
group by a.admission_type;

-- Medications analysis
select medication, status, count(*) 
from fact_medications 
group by medication, status;

/***************************************************************
                MAINTENANCE & DEV RESET
****************************************************************/


DROP SCHEMA IF EXISTS HOSPITAL_DB.DEV_STV_DEV_STV CASCADE;
DROP SCHEMA IF EXISTS HOSPITAL_DB.DEV_STV_STAGING CASCADE;
DROP SCHEMA IF EXISTS HOSPITAL_DB.DEV_STV_ANALYTICS CASCADE;


--Truncate the table in raw folder for AIrflow scheduling

show tables;

select * from patient_visits;

TRUNCATE TABLE PATIENT_VISITS;
TRUNCATE TABLE ANALYTICS.FACT_VISITS;
truncate table audit.load_logs;

SELECT COUNT(*) AS row_count
FROM PATIENT_VISITS;


/***************************************************************
             AUDIT & LOGGING
****************************************************************/

CREATE SCHEMA IF NOT EXISTS AUDIT;

CREATE TABLE IF NOT EXISTS AUDIT.LOAD_LOGS (
    load_id INTEGER AUTOINCREMENT,
    execution_date DATE,
    source_file VARCHAR,
    rows_loaded INT,
    load_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE AUDIT.LOAD_LOGS ADD COLUMN FACT_VISITS_COUNT INT;
ALTER TABLE AUDIT.LOAD_LOGS ADD COLUMN FACT_MEDICATIONS_COUNT INT;
DESC TABLE AUDIT.LOAD_LOGS;


USE DATABASE HOSPITAL_DB;
USE SCHEMA AUDIT;

CREATE OR REPLACE VIEW CUMULATIVE_LOADS AS
SELECT 
    execution_date,
    SUM(rows_loaded) OVER (ORDER BY execution_date ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cumulative_rows
FROM LOAD_LOGS
ORDER BY execution_date;


USE DATABASE HOSPITAL_DB;
USE SCHEMA RAW;

ALTER TABLE PATIENT_VISITS 
ADD COLUMN source_file VARCHAR;

ALTER TABLE RAW.PATIENT_VISITS DROP COLUMN source_file;


/***************************************************************
            VALIDATION & SANITY CHECKS
****************************************************************/

SELECT *
FROM ANALYTICS.dim_patients
WHERE race = 'Unknown' OR gender = 'Unknown' OR age_group = 'Unknown';

select distinct medical_specialty from 'dim_medical_specialty' order by 1;
select distinct payer_code from 'dim_payer') order by 1;


-- Count rows
select count(*) from ANALYTICS.dim_patients;
select count(*) from ANALYTICS.fact_visits;

-- Confirm Unknowns exist but are valid
select race, count(*) from ANALYTICS.dim_patients group by race;
select medical_specialty, count(*) from ANALYTICS.dim_medical_specialty group by 1;


--clean slate for dbt dev test
USE DATABASE HOSPITAL_DB;

-- Drop your dev schema and everything inside it
DROP SCHEMA IF EXISTS DEV_STV CASCADE;

-- (Optional) Recreate an empty schema immediately
CREATE SCHEMA DEV_STV;


-- Testing the dbtrun and dbt test
-- RAW should grow daily as Airflow ingests new files
select count(*) from HOSPITAL_DB.RAW.PATIENT_VISITS;

-- staging mirrors RAW
select count(*) from HOSPITAL_DB.DEV_STV.STG_PATIENT_VISITS;

-- facts/dims should align with what’s present in RAW so far
select count(*) from HOSPITAL_DB.DEV_STV.FACT_VISITS;
select count(*) from HOSPITAL_DB.DEV_STV.DIM_PATIENTS;

-- How many patients had >1 visit so far?
select count(*) 
from (
    select patient_nbr
    from HOSPITAL_DB.DEV_STV.STG_PATIENT_VISITS
    group by patient_nbr
    having count(*) > 1
);


-- Raw data (all encounters ingested so far)
select count(*) as raw_rows 
from HOSPITAL_DB.RAW.PATIENT_VISITS;

-- Staging should match RAW
select count(*) as stg_rows
from HOSPITAL_DB.DEV_STV.STG_PATIENT_VISITS;

-- Unique patients in dim_patients
select count(*) as dim_patients
from HOSPITAL_DB.DEV_STV.DIM_PATIENTS;

-- Encounters in fact_visits
select count(*) as fact_visits
from HOSPITAL_DB.DEV_STV.FACT_VISITS;

-- Patients vs visits (patients < visits, since some have multiple visits)
-- Total rows after full refresh
select count(*) as fact_meds
from HOSPITAL_DB.DEV_STV.FACT_MEDICATIONS;

-- Avg medications per encounter
select round(count(*)::float / nullif((select count(*) from HOSPITAL_DB.DEV_STV.FACT_VISITS),0),2) 
       as meds_per_visit
from HOSPITAL_DB.DEV_STV.FACT_MEDICATIONS;

-- Check 10 random visits with patient + meds
select fv.encounter_id, fv.patient_id, dp.race, dp.gender, fm.medication, fm.status
from HOSPITAL_DB.DEV_STV.FACT_VISITS fv
join HOSPITAL_DB.DEV_STV.DIM_PATIENTS dp on fv.patient_id = dp.patient_id
join HOSPITAL_DB.DEV_STV.FACT_MEDICATIONS fm on fv.encounter_id = fm.encounter_id
limit 10;


--duplicate check
select encounter_id, count(*) 
from HOSPITAL_DB.DEV_STV.FACT_VISITS
group by encounter_id
having count(*) > 1;
select encounter_id, medication, count(*) 
from HOSPITAL_DB.DEV_STV.FACT_MEDICATIONS
group by encounter_id, medication
having count(*) > 1;



-- Cleaning PROD
USE DATABASE HOSPITAL_DB;
DROP SCHEMA IF EXISTS ANALYTICS CASCADE;
CREATE SCHEMA ANALYTICS;



-- Check unexpected readmission flags
SELECT DISTINCT readmitted_flag
FROM HOSPITAL_DB.STAGING.stg_patient_visits
WHERE readmitted_flag NOT IN (0,1);

-- Check unexpected genders
SELECT DISTINCT gender
FROM HOSPITAL_DB.STAGING.stg_patient_visits
WHERE gender NOT IN ('Male','Female','Unknown');

-- Check unexpected races
SELECT DISTINCT race
FROM HOSPITAL_DB.STAGING.stg_patient_visits
WHERE race NOT IN ('Caucasian','AfricanAmerican','Asian','Hispanic','Other','Unknown');

SELECT race, gender, age_group
FROM HOSPITAL_DB.ANALYTICS.dim_patients
WHERE race = 'Unknown' OR gender = 'Unknown' OR age_group = 'Unknown';


SHOW TABLES IN SCHEMA HOSPITAL_DB.ANALYTICS;
SHOW PARAMETERS LIKE 'timezone';

SELECT query_text, start_time, end_time
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE query_text ILIKE '%fact_visits%'
  AND start_time >= DATEADD(hour, -1, CURRENT_TIMESTAMP)
ORDER BY start_time DESC;

ALTER SESSION SET TIMEZONE = 'America/Chicago';
SHOW TABLES IN SCHEMA HOSPITAL_DB.ANALYTICS;


-- Readmission rate
SELECT readmitted_flag, COUNT(*) 
FROM HOSPITAL_DB.ANALYTICS.fact_visits
GROUP BY readmitted_flag;

-- Age group distribution
SELECT age_group, COUNT(*) 
FROM HOSPITAL_DB.ANALYTICS.dim_patients
GROUP BY age_group
ORDER BY age_group;

-- Top diagnoses
SELECT diagnosis_category, COUNT(*)
FROM HOSPITAL_DB.ANALYTIC.dim_diagnosis
GROUP BY diagnosis_category
ORDER BY COUNT(*) DESC;

DESC TABLE HOSPITAL_DB.ANALYTICS.fact_visits;



SELECT d.diagnosis_category, COUNT(*) AS visits
FROM (
    SELECT diag1_id AS diagnosis_id FROM HOSPITAL_DB.ANALYTICS.fact_visits
    UNION ALL
    SELECT diag2_id FROM HOSPITAL_DB.ANALYTICS.fact_visits
    UNION ALL
    SELECT diag3_id FROM HOSPITAL_DB.ANALYTICS.fact_visits
) f
JOIN HOSPITAL_DB.ANALYTICS.dim_diagnosis d
  ON f.diagnosis_id = d.diagnosis_id
GROUP BY d.diagnosis_category
ORDER BY visits DESC;

-- shows all files last uploaded

SELECT *
FROM AUDIT.LOAD_LOGS
ORDER BY execution_date DESC
LIMIT 5;

SELECT *
FROM AUDIT.LOAD_LOGS
ORDER BY LOAD_TIME DESC
LIMIT 1;


TRUNCATE TABLE HOSPITAL_DB.ANALYTICS.fact_visits;
TRUNCATE TABLE HOSPITAL_DB.ANALYTICS.fact_medications;
TRUNCATE TABLE HOSPITAL_DB.AUDIT.load_logs;


-- completed the airflow scheduler, now loading the entire dataset to handle null values to check if dashboard has appropriate data showing

truncate table RAW.PATIENT_VISITS;  -- clear if needed

copy into RAW.PATIENT_VISITS
from @hospital_stage/clean_diabetic_data.csv
file_format = (format_name = cleaned_csv_format)
on_error = continue;

SELECT
    COUNT_IF(race IS NULL OR TRIM(race) = '')               AS null_race,
    COUNT_IF(gender IS NULL OR TRIM(gender) = '')           AS null_gender,
    COUNT_IF(age_group IS NULL OR TRIM(age_group) = '')     AS null_age_group,
    COUNT_IF(payer_code IS NULL OR TRIM(payer_code) = '')   AS null_payer_code,
    COUNT_IF(medical_specialty IS NULL OR TRIM(medical_specialty) = '') AS null_medical_specialty
FROM HOSPITAL_DB.DEV_STV.STG_PATIENT_VISITS;


SELECT DISTINCT race FROM HOSPITAL_DB.DEV_STV.STG_PATIENT_VISITS;
SELECT DISTINCT gender FROM HOSPITAL_DB.DEV_STV.STG_PATIENT_VISITS;
SELECT DISTINCT age_group FROM HOSPITAL_DB.DEV_STV.STG_PATIENT_VISITS;
SELECT DISTINCT payer_code FROM HOSPITAL_DB.DEV_STV.STG_PATIENT_VISITS;
SELECT DISTINCT medical_specialty FROM HOSPITAL_DB.DEV_STV.STG_PATIENT_VISITS;

-- Fact visits row count should match stg_patient_visits
SELECT COUNT(*) FROM HOSPITAL_DB.DEV_STV.FACT_VISITS;

-- Distinct patients
SELECT COUNT(DISTINCT patient_id) FROM HOSPITAL_DB.DEV_STV.FACT_VISITS;

-- Fact medications row count (each encounter expanded by meds)
SELECT COUNT(*) FROM HOSPITAL_DB.DEV_STV.FACT_MEDICATIONS;

-- Check sample
SELECT * FROM HOSPITAL_DB.DEV_STV.FACT_VISITS LIMIT 20;
SELECT * FROM HOSPITAL_DB.DEV_STV.FACT_MEDICATIONS LIMIT 20;


-- count rows in staging
SELECT COUNT(DISTINCT patient_nbr) AS stg_patients
FROM HOSPITAL_DB.DEV_STV.STG_PATIENT_VISITS;

-- count rows in dim
SELECT COUNT(DISTINCT patient_nbr) AS dim_patients
FROM HOSPITAL_DB.DEV_STV.DIM_PATIENTS;

-- check join coverage
SELECT COUNT(*) AS total_visits,
       COUNT(p.patient_id) AS matched_patients,
       COUNT(*) - COUNT(p.patient_id) AS unmatched
FROM HOSPITAL_DB.DEV_STV.STG_PATIENT_VISITS v
LEFT JOIN HOSPITAL_DB.DEV_STV.DIM_PATIENTS p
  ON v.patient_nbr = p.patient_nbr;


-- Staging patient_nbr
SELECT patient_nbr, COUNT(*) 
FROM HOSPITAL_DB.DEV_STV.STG_PATIENT_VISITS
GROUP BY patient_nbr
LIMIT 20;

-- Dim patient_nbr
SELECT patient_nbr, COUNT(*)
FROM HOSPITAL_DB.DEV_STV.DIM_PATIENTS
GROUP BY patient_nbr
LIMIT 20;

SELECT DISTINCT payer_code
FROM HOSPITAL_DB.DEV_STV.FACT_VISITS
ORDER BY payer_code;


--what distinct admission_type_id values exist in staging?
SELECT DISTINCT admission_type_id
FROM STG_PATIENT_VISITS
ORDER BY admission_type_id;

--which IDs exist in staging but not in dim_admission?
SELECT DISTINCT s.admission_type_id
FROM STG_PATIENT_VISITS s
LEFT JOIN DIM_ADMISSION d
  ON s.admission_type_id = d.admission_type_id
WHERE d.admission_type_id IS NULL;


SELECT
    diag1_id,  -- or diagnosis_category if you kept the text label
    COUNT(*) AS total_encounters,
    SUM(CASE WHEN readmitted_flag = 1 THEN 1 ELSE 0 END) AS readmitted_encounters,
    ROUND(SUM(CASE WHEN readmitted_flag = 1 THEN 1 ELSE 0 END) * 1.0 
          / COUNT(*), 3) AS readmission_rate
FROM FACT_VISITS
GROUP BY diag1_id
ORDER BY readmission_rate DESC;

SELECT DISTINCT race, gender, age_group
FROM HOSPITAL_DB.ANALYTICS.DIM_PATIENTS;


select distinct medication
from fact_medications;
DESC TABLE FACT_MEDICATIONS;


