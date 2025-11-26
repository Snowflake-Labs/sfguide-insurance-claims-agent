USE ROLE CLAIMS_AGENT_ROLE;
USE DATABASE INSURANCE_CLAIMS_DEMO;
USE SCHEMA LOSS_CLAIMS;
USE WAREHOUSE CLAIMS_AGENT_WH;

CREATE OR REPLACE TABLE 
PARSED_CLAIM_NOTES (
    FILENAME VARCHAR(255),
    EXTRACTED_CONTENT VARCHAR(16777216),
    PARSE_DATE TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP,
    CLAIM_NO VARCHAR
);

INSERT INTO PARSED_CLAIM_NOTES (FILENAME, EXTRACTED_CONTENT, CLAIM_NO)
SELECT
    t1.RELATIVE_PATH AS FILENAME,
    t1.EXTRACTED_CONTENT,
    flattened.value:answer::VARCHAR AS CLAIM_NO
FROM
    (
        SELECT
            RELATIVE_PATH,
            TO_VARCHAR(
                SNOWFLAKE.CORTEX.PARSE_DOCUMENT(
                    '@INSURANCE_CLAIMS_DEMO.loss_claims.loss_evidence',
                    RELATIVE_PATH,
                    {'mode': 'OCR'}
                ):content
            ) AS EXTRACTED_CONTENT
        FROM
            DIRECTORY('@INSURANCE_CLAIMS_DEMO.loss_claims.loss_evidence')
        WHERE
            RELATIVE_PATH LIKE '%Claim_Note%'
    ) AS t1,
    LATERAL FLATTEN(
        input => SNOWFLAKE.CORTEX.EXTRACT_ANSWER(t1.EXTRACTED_CONTENT, 'What is the claim number?')
    ) AS flattened
WHERE
    flattened.value:score::NUMBER >= 0.5;

CREATE OR REPLACE TABLE PARSED_GUIDELINES (
    FILENAME VARCHAR(255),
    EXTRACTED_CONTENT VARCHAR(16777216), 
    PARSE_DATE TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO PARSED_GUIDELINES (FILENAME, EXTRACTED_CONTENT)
SELECT
    t1.RELATIVE_PATH AS FILENAME,
    TO_VARCHAR(
        SNOWFLAKE.CORTEX.PARSE_DOCUMENT(
            '@INSURANCE_CLAIMS_DEMO.loss_claims.loss_evidence',
            t1.RELATIVE_PATH,
            {'mode': 'OCR'}
        ):content
    ) AS EXTRACTED_CONTENT
FROM
    DIRECTORY('@INSURANCE_CLAIMS_DEMO.loss_claims.loss_evidence') AS t1
WHERE
    t1.RELATIVE_PATH LIKE '%Guideline%';

CREATE OR REPLACE TABLE PARSED_INVOICES (
    FILENAME VARCHAR(255),
    EXTRACTED_CONTENT VARCHAR(16777216), 
    PARSE_DATE TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP,
    CLAIM_NO VARCHAR
);


INSERT INTO PARSED_INVOICES (FILENAME, EXTRACTED_CONTENT, CLAIM_NO)
SELECT
    t1.RELATIVE_PATH,
    t1.EXTRACTED_CONTENT,
    -- Extract the answer from the flattened JSON object
    flattened.value:answer::VARCHAR AS CLAIM_NO
FROM
    (
        SELECT
            RELATIVE_PATH,
            TO_VARCHAR(
                SNOWFLAKE.CORTEX.PARSE_DOCUMENT(
                    '@INSURANCE_CLAIMS_DEMO.loss_claims.loss_evidence',
                    RELATIVE_PATH,
                    {'mode': 'OCR'}
                ):content
            ) AS EXTRACTED_CONTENT
        FROM
            DIRECTORY('@INSURANCE_CLAIMS_DEMO.loss_claims.loss_evidence')
        WHERE
            RELATIVE_PATH LIKE '%invoice%'
    ) AS t1,
    LATERAL FLATTEN(
        input => SNOWFLAKE.CORTEX.EXTRACT_ANSWER(t1.EXTRACTED_CONTENT, 'What is the claim no?')
    ) AS flattened
WHERE
    flattened.value:score::NUMBER >= 0.5;

----- chunk data in claim notes and guidelines -----

CREATE OR REPLACE TABLE NOTES_CHUNK_TABLE AS
SELECT
    FILENAME,
    CLAIM_NO,  -- Add this line to include the claim number
    GET_PRESIGNED_URL('@INSURANCE_CLAIMS_DEMO.loss_claims.loss_evidence', FILENAME, 86400) AS file_url,
    CONCAT(FILENAME, ': ', c.value::TEXT) AS chunk,
    'English' AS language
FROM
    PARSED_CLAIM_NOTES,
    LATERAL FLATTEN(SNOWFLAKE.CORTEX.SPLIT_TEXT_RECURSIVE_CHARACTER(
        EXTRACTED_CONTENT,
        'markdown',
        200, -- chunks of 200 characters
        30 -- 30 character overlap
    )) c;

CREATE OR REPLACE TABLE GUIDELINES_CHUNK_TABLE AS
SELECT
    FILENAME,
    GET_PRESIGNED_URL('@INSURANCE_CLAIMS_DEMO.loss_claims.loss_evidence', FILENAME, 86400) AS file_url,
    CONCAT(FILENAME, ': ', c.value::TEXT) AS chunk,
    'English' AS language
FROM
    PARSED_GUIDELINES,
    LATERAL FLATTEN(SNOWFLAKE.CORTEX.SPLIT_TEXT_RECURSIVE_CHARACTER(
        EXTRACTED_CONTENT,
        'markdown',
        200, -- chunks of 2000 characters
        30 -- 300 character overlap
    )) c;


---- create cortex search services -----

CREATE OR REPLACE
CORTEX SEARCH SERVICE 
INSURANCE_CLAIMS_DEMO_claim_notes
  ON chunk
  ATTRIBUTES file_url, claim_no, filename
  WAREHOUSE = CLAIMS_AGENT_WH
  TARGET_LAG = '1 hour'
  EMBEDDING_MODEL = 'snowflake-arctic-embed-l-v2.0'
AS (
  SELECT
    chunk,
    file_url,
    claim_no,
    filename
  FROM NOTES_CHUNK_TABLE
);

CREATE OR REPLACE
CORTEX SEARCH SERVICE 
INSURANCE_CLAIMS_DEMO_guidelines
  ON chunk
  ATTRIBUTES file_url, filename
  WAREHOUSE = CLAIMS_AGENT_WH
  TARGET_LAG = '1 hour'
  EMBEDDING_MODEL = 'snowflake-arctic-embed-l-v2.0'
AS (
  SELECT
     chunk,
     file_url,
     filename
  FROM GUIDELINES_CHUNK_TABLE
);

CREATE OR REPLACE FUNCTION INSURANCE_CLAIMS_DEMO.LOSS_CLAIMS.CLASSIFY_DOCUMENT("FILE_NAME" VARCHAR, "STAGE_NAME" VARCHAR DEFAULT '@INSURANCE_CLAIMS_DEMO.LOSS_CLAIMS.LOSS_EVIDENCE')
RETURNS OBJECT
LANGUAGE SQL
AS '
    WITH classification_result AS (
        SELECT AI_EXTRACT(
            TO_FILE(stage_name, file_name),
            [
                ''What type of document is this? Classify as one of: Invoice, Evidence Image, Medical Bill, Insurance Claim, Policy Document, Correspondence, Legal Document, Financial Statement, Other''
            ]
        ) as classification_data
    )
    SELECT 
        OBJECT_CONSTRUCT(
            ''success'', TRUE,
            ''file_name'', file_name,
            ''classification_type'', classification_data[0]:answer::STRING,
            ''description'', classification_data[1]:answer::STRING,
            ''business_context'', classification_data[2]:answer::STRING,
            ''document_purpose'', classification_data[3]:answer::STRING,
            ''confidence_score'', (
                classification_data[0]:score::NUMBER + 
                classification_data[1]:score::NUMBER + 
                classification_data[2]:score::NUMBER + 
                classification_data[3]:score::NUMBER
            ) / 4,
            ''classification_timestamp'', CURRENT_TIMESTAMP(),
            ''full_classification_data'', classification_data
        ) as result
    FROM classification_result
';

CREATE OR REPLACE FUNCTION INSURANCE_CLAIMS_DEMO.LOSS_CLAIMS.PARSE_DOCUMENT_FROM_STAGE("FILE_NAME" VARCHAR)
RETURNS VARIANT
LANGUAGE SQL
AS '
    SELECT AI_PARSE_DOCUMENT(
        TO_FILE(''@INSURANCE_CLAIMS_DEMO.loss_claims.loss_evidence'', file_name),
        {
            ''mode'': ''LAYOUT'',
            ''page_split'': TRUE
        }
    )::VARIANT
';

CREATE OR REPLACE FUNCTION INSURANCE_CLAIMS_DEMO.LOSS_CLAIMS.GET_IMAGE_SUMMARY("IMAGE_FILE" VARCHAR, "STAGE_NAME" VARCHAR)
RETURNS VARCHAR
LANGUAGE SQL
AS '
    SELECT SNOWFLAKE.CORTEX.COMPLETE(
        ''claude-3-5-sonnet'',
        ''Summarize the key insights from the attached image in 100 words.'',
        TO_FILE(''@'' || STAGE_NAME || ''/'' || IMAGE_FILE)
    )
';

CREATE OR REPLACE PROCEDURE INSURANCE_CLAIMS_DEMO.LOSS_CLAIMS.TRANSCRIBE_AUDIO_SIMPLE("FILE_NAME" VARCHAR, "STAGE_NAME" VARCHAR DEFAULT '@loss_evidence')
RETURNS OBJECT
LANGUAGE SQL
EXECUTE AS OWNER
AS '
BEGIN
    -- This approach avoids variable scoping issues by using a different pattern
    RETURN (
        WITH transcription_query AS (
            SELECT 
                :file_name as fn,
                :stage_name as sn,
                AI_TRANSCRIBE(
                    TO_FILE(:stage_name, :file_name),
                    PARSE_JSON(''{"timestamp_granularity": "speaker"}'')
                ) as transcription_result
        )
        SELECT OBJECT_CONSTRUCT(
            ''success'', TRUE,
            ''file_name'', fn,
            ''stage_name'', sn,
            ''transcription'', transcription_result,
            ''transcription_timestamp'', CURRENT_TIMESTAMP()
        )
        FROM transcription_query
    );
EXCEPTION
    WHEN OTHER THEN
        RETURN OBJECT_CONSTRUCT(
            ''success'', FALSE,
            ''file_name'', :file_name,
            ''stage_name'', :stage_name,
            ''error_code'', SQLCODE,
            ''error_message'', SQLERRM,
            ''transcription_timestamp'', CURRENT_TIMESTAMP()
        );
END;
';

--CREATE CORTEX ANALYST YAML FILE

create or replace semantic view INSURANCE_CLAIMS_DEMO.LOSS_CLAIMS.CA_INSURANCE_CLAIMS_DEMO
	tables (
		AUTHORIZATION primary key (PERFORMER_ID),
		CLAIMS primary key (CLAIM_NO),
		CLAIM_LINES primary key (LINE_NO),
		FINANCIAL_TRANSACTIONS primary key (LINE_NO),
		INVOICES
	)
	relationships (
		CLAIM_LINES_TO_AUTHORIZATION as CLAIM_LINES(PERFORMER_ID) references AUTHORIZATION(PERFORMER_ID),
		CLAIM_TO_CLAIM_LINES_CLAIM_ID as CLAIM_LINES(CLAIM_NO) references CLAIMS(CLAIM_NO),
		FINANCIAL_TO_CLAIM_LINES as CLAIM_LINES(LINE_NO) references FINANCIAL_TRANSACTIONS(LINE_NO),
		CLAIM_LINES_TO_INVOICE as INVOICES(LINE_NO) references CLAIM_LINES(LINE_NO),
		FINANCIAL_TO_INVOICE as INVOICES(LINE_NO) references FINANCIAL_TRANSACTIONS(LINE_NO)
	)
	facts (
		AUTHORIZATION.FROM_AMT as FROM_AMT with synonyms=('beginning_balance','initial_amount','lower_bound_amount','minimum_amount','starting_amount') comment='The amount of funds being transferred or allocated from one account or source to another.',
		AUTHORIZATION.TO_AMT as TO_AMT with synonyms=('ceiling_amount','end_amount','end_value','max_value','maximum_amount','to_value','upper_bound','upper_limit') comment='The total amount of the authorization.',
		FINANCIAL_TRANSACTIONS.FIN_TX_AMT as FIN_TX_AMT with synonyms=('amount_transacted','financial_amount','financial_transaction_value','payment_amount','transaction_amount','transaction_cost','transaction_value') comment='The amount of the financial transaction.',
		INVOICES.INVOICE_AMOUNT as INVOICE_AMOUNT with synonyms=('amount_billed','billed_amount','invoice_cost','invoice_price','invoice_total','invoice_value','total_due','total_invoice_value') comment='The total amount due on an invoice, representing the sum of all charges, taxes, and fees associated with a specific transaction or order.'
	)
	dimensions (
		AUTHORIZATION.CURRENCY as CURRENCY with synonyms=('bill_type','coin_type','denomination','exchange_unit','legal_tender','monetary_unit','money_unit','tender_type') comment='The currency in which the transaction or authorization was processed.',
		AUTHORIZATION.PERFORMER_ID as PERFORMER_ID with synonyms=('account_id','actor_id','executor_id','operator_id','performer_key','practitioner_id','provider_id','user_id') comment='Unique identifier for the individual or entity responsible for performing a specific task or action.',
		CLAIMS.CAUSE_OF_LOSS as CAUSE_OF_LOSS with synonyms=('accident_cause','claim_cause','claim_reason','damage_cause','incident_cause','loss_cause','loss_origin','loss_reason','reason_for_claim') comment='The reason or event that triggered the insurance claim, such as a natural disaster or accident.',
		CLAIMS.CLAIMANT_ID as CLAIMANT_ID with synonyms=('claimant_identifier','claimant_number','insured_id','insured_party_id','policy_owner_id','policyholder_id') comment='Unique identifier for the individual or entity submitting the claim.',
		CLAIMS.CLAIM_NO as CLAIM_NO with synonyms=('claim_id','claim_identifier','claim_number','claim_reference','policy_claim_number') comment='Unique identifier for a claim, used to distinguish one claim from another.',
		CLAIMS.CLAIM_STATUS as CLAIM_STATUS with synonyms=('claim_decision','claim_disposition','claim_outcome','claim_resolution','claim_result','claim_state','claim_verdict') comment='The current status of the claim, indicating whether it is still being processed (Open) or has been resolved.',
		CLAIMS.CREATED_DATE as CREATED_DATE with synonyms=('created_timestamp','creation_date','date_created','entry_date','insertion_date','record_date','registration_date','submission_date') comment='Date when the claim was created.',
		CLAIMS.FNOL_COMPLETION_DATE as FNOL_COMPLETION_DATE with synonyms=('first_notice_of_loss_completion_date','first_report_of_loss_date','initial_loss_report_date','loss_notification_completion_date','notice_of_loss_completion_date') comment='Date when the First Notice of Loss (FNOL) was completed, marking the initial report of a claim.',
		CLAIMS.LINE_OF_BUSINESS as LINE_OF_BUSINESS with synonyms=('business_line','business_segment','industry','market_segment','product_category','product_line','service_category','service_line') comment='The type of business or industry that the claim is related to, such as property, casualty, or liability.',
		CLAIMS.LOSS_DATE as LOSS_DATE with synonyms=('accident_date','date_of_incident','date_of_loss','incident_date','loss_event_date','loss_occurrence_date') comment='Date on which the loss or damage occurred.',
		CLAIMS.LOSS_DESCRIPTION as LOSS_DESCRIPTION with synonyms=('claim_description','claim_summary','damage_description','incident_description','incident_summary','loss_details','loss_narrative','loss_summary') comment='A brief description of the loss or damage that occurred, as reported by the claimant.',
		CLAIMS.LOSS_STATE as LOSS_STATE with synonyms=('location_of_loss','loss_location','loss_region','loss_state_province','loss_territory','state_of_loss','state_where_loss_occurred') comment='The state in which the loss occurred.',
		CLAIMS.LOSS_ZIP_CODE as LOSS_ZIP_CODE with synonyms=('claim_zip_code','incident_zip','loss_location_zip','loss_postal_code','loss_postcode','loss_zip') comment='The five-digit zip code where the loss occurred.',
		CLAIMS.PERFORMER as PERFORMER with synonyms=('caregiver','doctor','healthcare_provider','medical_professional','nurse','practitioner','provider','service_provider','therapist') comment='The individual or entity that performed the medical service or procedure associated with the claim.',
		CLAIMS.POLICY_NO as POLICY_NO with synonyms=('contract_id','contract_number','policy_code','policy_id','policy_identifier','policy_number') comment='Unique identifier for the insurance policy associated with the claim.',
		CLAIMS.REPORTED_DATE as REPORTED_DATE with synonyms=('claim_reported_date','date_reported','filing_date','incident_reported_date','logged_date','notification_date','reported_on','submission_date') comment='The date on which the claim was reported to the organization.',
		CLAIM_LINES.CLAIMANT_ID as CLAIMANT_ID with synonyms=('claimant_identifier','claimant_number','claimer_id','insured_id','policy_holder_id','policy_owner_id') comment='Unique identifier for the individual or entity submitting the claim.',
		CLAIM_LINES.CLAIM_NO as CLAIM_NO with synonyms=('claim_code','claim_id','claim_identifier','claim_number','claim_reference','policy_number') comment='Unique identifier for a claim, used to track and manage individual claims submitted by patients or healthcare providers for reimbursement or insurance coverage.',
		CLAIM_LINES.CLAIM_STATUS as CLAIM_STATUS with synonyms=('claim_disposition','claim_outcome','claim_phase','claim_progress','claim_resolution','claim_result','claim_state') comment='The current status of a claim, indicating whether it is still being processed (Open) or has been resolved.',
		CLAIM_LINES.LINE_NO as LINE_NO with synonyms=('claim_line_number','line_number','record_number','row_number','sequence_number') comment='Unique identifier for each line item within a claim.',
		CLAIM_LINES.LOSS_DESCRIPTION as LOSS_DESCRIPTION with synonyms=('claim_cause','claim_description','damage_description','incident_description','incident_summary','loss_reason','loss_summary') comment='A brief description of the damage or loss incurred by the policyholder, as reported on the claim.',
		CLAIM_LINES.CREATED_DATE as CREATED_DATE with synonyms=('creation_date','date_created','date_entered','date_recorded','entry_date','record_date','registration_date') comment='Date when the claim line was created.',
		CLAIM_LINES.PERFORMER_ID as PERFORMER_ID with synonyms=('caregiver_id','healthcare_provider_id','medical_professional_id','practitioner_id','provider_id','service_provider_id') comment='The unique identifier of the healthcare provider who performed the medical service or procedure associated with the claim line.',
		CLAIM_LINES.REPORTED_DATE as REPORTED_DATE with synonyms=('date_reported','event_date','filing_date','incident_date','logged_date','occurrence_date','reported_on','submission_date') comment='The date on which the claim was reported to the insurance company.',
		FINANCIAL_TRANSACTIONS.CURRENCY as CURRENCY with synonyms=('coin_type','denomination','exchange_unit','legal_tender','medium_of_exchange','monetary_unit','money_unit','tender_type') comment='The currency in which the financial transaction was made.',
		FINANCIAL_TRANSACTIONS.FINANCIAL_TYPE as FINANCIAL_TYPE with synonyms=('account_type','financial_category','financial_classification','payment_method','transaction_classification','transaction_type') comment='The type of financial transaction, either a Revenue Share Voucher (RSV) or a payment (PAY).',
		FINANCIAL_TRANSACTIONS.FIN_TX_POST_DT as FIN_TX_POST_DT with synonyms=('financial_transaction_date','posting_date','posting_timestamp','transaction_date','transaction_posted_date','transaction_posting_date') comment='Date the financial transaction was posted.',
		FINANCIAL_TRANSACTIONS.FXID as FXID with synonyms=('exchange_id','exchange_transaction_key','financial_exchange_identifier','foreign_exchange_id','transaction_id') comment='Unique identifier for a foreign exchange transaction.',
		FINANCIAL_TRANSACTIONS.LINE_NO as LINE_NO with synonyms=('entry_number','line_number','record_number','row_number','sequence_number','transaction_line') comment='A unique identifier for each line item within a financial transaction.',
		INVOICES.CURRENCY as CURRENCY with synonyms=('coin_type','denomination','exchange_rate_unit','legal_tender','monetary_denomination','monetary_unit','money_unit','tender_type') comment='The currency in which the invoice was issued.',
		INVOICES.DESCRIPTION as DESCRIPTION with synonyms=('item_description','item_info','item_note','item_text','product_details','product_info','product_note') comment='A categorization of the type of goods or services billed to a customer, such as materials, equipment, or work performed.',
		INVOICES.INVOICE_DATE as INVOICE_DATE with synonyms=('bill_date','billing_date','date_invoiced','document_date','invoice_creation_date','payment_due_date') comment='Date the invoice was issued.',
		INVOICES.INV_ID as INV_ID with synonyms=('invoice_code','invoice_id','invoice_identifier','invoice_number','invoice_reference') comment='Unique identifier for each invoice.',
		INVOICES.INV_LINE_NBR as INV_LINE_NBR with synonyms=('invoice_item_number','invoice_line_id','invoice_line_number','item_number','line_item_number','line_nbr') comment='Unique identifier for each line item on an invoice.',
		INVOICES.LINE_NO as LINE_NO with synonyms=('entry_number','item_number','line_item_number','line_number','row_number','sequence_number') comment='A unique identifier for each line item on an invoice, representing the sequential order in which the items appear on the invoice.',
		INVOICES.VENDOR as VENDOR with synonyms=('contractor','dealer','distributor','manufacturer','merchant','provider','seller','supplier','trader') comment='The name of the vendor or supplier that the invoice is associated with.'
	)
	with extension (CA='{"tables":[{"name":"AUTHORIZATION","dimensions":[{"name":"CURRENCY","sample_values":["USD"]},{"name":"PERFORMER_ID","sample_values":["181","171","191"]}],"facts":[{"name":"FROM_AMT","sample_values":["0.00"]},{"name":"TO_AMT","sample_values":["3000.00","2500.00","5000.00"]}]},{"name":"CLAIMS","dimensions":[{"name":"CAUSE_OF_LOSS","sample_values":["Hurricane"]},{"name":"CLAIM_NO","sample_values":["1899"]},{"name":"CLAIM_STATUS","sample_values":["Open"]},{"name":"CLAIMANT_ID","sample_values":["19"]},{"name":"LINE_OF_BUSINESS","sample_values":["Property"]},{"name":"LOSS_DESCRIPTION","sample_values":["Damaged dwelling and fence after the tree fell"]},{"name":"LOSS_STATE","sample_values":["NJ"]},{"name":"LOSS_ZIP_CODE","sample_values":["8820"]},{"name":"PERFORMER","sample_values":["18"]},{"name":"POLICY_NO","sample_values":["888"]}],"time_dimensions":[{"name":"CREATED_DATE","sample_values":["2025-01-06"]},{"name":"FNOL_COMPLETION_DATE","sample_values":["2025-01-06"]},{"name":"LOSS_DATE","sample_values":["2025-01-06"]},{"name":"REPORTED_DATE","sample_values":["2025-01-06"]}]},{"name":"CLAIM_LINES","dimensions":[{"name":"CLAIM_NO","sample_values":["1899"]},{"name":"CLAIM_STATUS","sample_values":["Open"]},{"name":"CLAIMANT_ID","sample_values":["19"]},{"name":"LINE_NO","sample_values":["17","18","16"]},{"name":"LOSS_DESCRIPTION","sample_values":["Damaged Dwelling","Damaged Fence","Damaged Lawn"]},{"name":"PERFORMER_ID","sample_values":["181","171","191"]}],"time_dimensions":[{"name":"CREATED_DATE","sample_values":["2025-01-06"]},{"name":"REPORTED_DATE","sample_values":["2025-01-06"]}]},{"name":"FINANCIAL_TRANSACTIONS","dimensions":[{"name":"CURRENCY","sample_values":["USD"]},{"name":"FINANCIAL_TYPE","sample_values":["RSV","PAY"]},{"name":"FXID","sample_values":["22","23","24"]},{"name":"LINE_NO","sample_values":["17","18","16"]}],"facts":[{"name":"FIN_TX_AMT","sample_values":["3000.00","3500.00","4000.00"]}],"time_dimensions":[{"name":"FIN_TX_POST_DT","sample_values":["2025-03-06","2025-06-15","2025-02-15"]}]},{"name":"INVOICES","dimensions":[{"name":"CURRENCY","sample_values":["USD"]},{"name":"DESCRIPTION","sample_values":["Hardware","Labor","Wooden Logs"]},{"name":"INV_ID","sample_values":["7","5","6"]},{"name":"INV_LINE_NBR","sample_values":["3","2","1"]},{"name":"LINE_NO","sample_values":["16","18","17"]},{"name":"VENDOR","sample_values":["LMN","XYZ","ABC"]}],"facts":[{"name":"INVOICE_AMOUNT","sample_values":["2500.00","1000.00","500.00"]}],"time_dimensions":[{"name":"INVOICE_DATE","sample_values":["2025-05-15","2025-03-18","2025-04-20"]}]}],"relationships":[{"name":"CLAIM_LINES_TO_AUTHORIZATION"},{"name":"CLAIM_TO_CLAIM_LINES_CLAIM_ID"},{"name":"FINANCIAL_TO_CLAIM_LINES"},{"name":"CLAIM_LINES_TO_INVOICE"},{"name":"FINANCIAL_TO_INVOICE"}],"verified_queries":[{"name":"Was a payment made in excess of the performer authority? Please respond yes or no and provide more details if yes.","question":"Was a payment made in excess of the performer authority? Please respond yes or no and provide more details if yes.","sql":"WITH auth_fin_tx AS (\\n  SELECT\\n    a.performer_id,\\n    a.to_amt AS max_authorized_amt,\\n    ft.fin_tx_amt\\n  FROM\\n    authorization AS a\\n    INNER JOIN claim_lines AS cl ON a.performer_id = cl.performer_id\\n    INNER JOIN financial_transactions AS ft ON cl.line_no = ft.line_no\\n)\\nSELECT\\n  performer_id,\\n  max_authorized_amt,\\n  fin_tx_amt,\\n  CASE\\n    WHEN fin_tx_amt > max_authorized_amt THEN ''Yes''\\n    ELSE ''No''\\n  END AS payment_exceeds_authority\\nFROM\\n  auth_fin_tx","use_as_onboarding_question":false,"verified_by":"Marie Duran","verified_at":1755720163},{"name":"Was a payment issued to the vendor 30+ calendar days after the invoice was received? If yes, please provide details","question":"Was a payment issued to the vendor 30+ calendar days after the invoice was received? If yes, please provide details","sql":"WITH invoice_payment AS (\\n  SELECT\\n    i.vendor,\\n    i.invoice_date,\\n    ft.fin_tx_post_dt,\\n    DATEDIFF(DAY, i.invoice_date, ft.fin_tx_post_dt) AS days_between\\n  FROM\\n    invoices AS i\\n    LEFT OUTER JOIN financial_transactions AS ft ON i.line_no = ft.line_no\\n)\\nSELECT\\n  vendor,\\n  invoice_date,\\n  fin_tx_post_dt,\\n  days_between,\\n  CASE\\n    WHEN days_between > 30 THEN ''Yes''\\n    ELSE ''No''\\n  END AS payment_issued_late\\nFROM\\n  invoice_payment","use_as_onboarding_question":false,"verified_by":"Marie Duran","verified_at":1755720298},{"name":"Was a payment issued to the vendor 8-13 calendar days after the invoice was received?","question":"Was a payment issued to the vendor 8-13 calendar days after the invoice was received?","sql":"WITH invoice_payment AS (\\n  SELECT\\n    i.vendor,\\n    i.invoice_date,\\n    ft.fin_tx_post_dt,\\n    DATEDIFF(DAY, i.invoice_date, ft.fin_tx_post_dt) AS days_between\\n  FROM\\n    invoices AS i\\n    LEFT OUTER JOIN financial_transactions AS ft ON i.line_no = ft.line_no\\n)\\nSELECT\\n  vendor,\\n  invoice_date,\\n  fin_tx_post_dt,\\n  days_between,\\n  CASE\\n    WHEN days_between BETWEEN 8\\n    AND 13 THEN ''Yes''\\n    ELSE ''No''\\n  END AS payment_issued_within_range\\nFROM\\n  invoice_payment","use_as_onboarding_question":false,"verified_by":"Marie Duran","verified_at":1755720353}]}');

-- create agent --
CREATE OR REPLACE AGENT SNOWFLAKE_INTELLIGENCE.AGENTS.CLAIMS_AUDIT_AGENT
FROM SPECIFICATION
$$
{
    "models": {
      "orchestration": "auto"
    },
    "instructions": {
      "orchestration": "-If the user asks about claim completeness, deem a claim as complete if the following are available: Claim level data, claim lines, financial, claim notes",
      "sample_questions": [
        {
          "question": "Based on the state of new jersey's insurance claims guidelines, have any of my claims been outside of the mandated settlement window?"
        },
        {
          "question": "Was there a reserve rationale in the file notes?"
        },
        {
          "question": "Was a payment made in excess of the reserve amount for claim 1899?"
        },
        {
          "question": "Can you transcribe the media file 'consultation_5_mix_es_en.wav stored in '@INSURANCE_CLAIMS_DEMO.loss_claims.loss_evidence'?"
        },
        {
          "question": "What is the callers intent?"
        },
        {
          "question": "What is the customers reason for calling?"
        },
        {
          "question": "Can you give me a summary of 1899_claim_evidence1.jpeg image please?"
        },
        {
          "question": "What is the similarity score between the summary of the claim evidence and the claim description for claim 1899?"
        },
        {
          "question": "Does the file Gemini_Generated3.jpeg appear to be tampered with?"
        },
        {
          "question": "Is claim 1899 complete?"
        }
      ]
    },
    "tools": [
      {
        "tool_spec": {
          "type": "cortex_analyst_text_to_sql",
          "name": "CA_INS",
          "description": "AUTHORIZATION:\n- Database: INSURANCE_CLAIMS_DEMO, Schema: LOSS_CLAIMS\n- This table manages authorization limits for performers/providers in the insurance claims system. It defines spending authority ranges with minimum and maximum amounts that can be authorized by specific performers.\n- The table establishes financial controls by setting authorization boundaries, ensuring that claim payments stay within approved limits for each performer.\n- LIST OF COLUMNS: PERFORMER_ID (unique identifier for performer - links to PERFORMER_ID in CLAIM_LINES), CURRENCY (transaction currency), FROM_AMT (minimum authorization amount), TO_AMT (maximum authorization amount)\n\nCLAIMS:\n- Database: INSURANCE_CLAIMS_DEMO, Schema: LOSS_CLAIMS\n- This is the main claims table containing comprehensive information about insurance claims including policy details, loss information, and claim status. It serves as the central hub for claim management with details about when losses occurred, were reported, and processed.\n- The table tracks the complete lifecycle of claims from initial loss occurrence through reporting and processing, providing essential data for claim analysis and management.\n- LIST OF COLUMNS: CLAIM_NO (unique claim identifier), LINE_OF_BUSINESS (business type), CLAIM_STATUS (current claim state), CAUSE_OF_LOSS (loss reason), CLAIMANT_ID (person submitting claim), PERFORMER (service provider - links to PERFORMER_ID in other tables), POLICY_NO (insurance policy identifier), LOSS_DESCRIPTION (damage details), LOSS_STATE (loss location state), LOSS_ZIP_CODE (loss location zip), CREATED_DATE (claim creation date), LOSS_DATE (when loss occurred), REPORTED_DATE (when claim was reported), FNOL_COMPLETION_DATE (first notice of loss completion)\n\nCLAIM_LINES:\n- Database: INSURANCE_CLAIMS_DEMO, Schema: LOSS_CLAIMS\n- This table contains individual line items for each claim, breaking down claims into specific components or damages. Each line represents a separate aspect of the overall claim with its own status and performer assignment.\n- The table enables detailed tracking of claim components, allowing for granular management of different types of damages or services within a single claim.\n- LIST OF COLUMNS: CLAIM_NO (links to CLAIM_NO in CLAIMS), LOSS_DESCRIPTION (specific line item damage), CLAIM_STATUS (line item status), CLAIMANT_ID (claim submitter), PERFORMER_ID (assigned service provider - links to AUTHORIZATION), LINE_NO (unique line identifier - links to FINANCIAL_TRANSACTIONS and INVOICES), CREATED_DATE (line creation date), REPORTED_DATE (line reporting date)\n\nFINANCIAL_TRANSACTIONS:\n- Database: INSURANCE_CLAIMS_DEMO, Schema: LOSS_CLAIMS\n- This table records all financial activities related to claims including payments and reserves. It tracks the monetary flow for each claim line item with transaction types, amounts, and posting dates.\n- The table provides complete financial audit trail for claims processing, enabling tracking of reserves set aside and actual payments made for claim resolution.\n- LIST OF COLUMNS: FXID (foreign exchange transaction ID), FINANCIAL_TYPE (transaction category like RSV/PAY), CURRENCY (transaction currency), LINE_NO (links to CLAIM_LINES and INVOICES), FIN_TX_POST_DT (transaction posting date), FIN_TX_AMT (transaction amount)\n\nINVOICES:\n- Database: INSURANCE_CLAIMS_DEMO, Schema: LOSS_CLAIMS\n- This table contains invoice information from vendors providing services or materials for claim repairs. It includes detailed line items with descriptions, amounts, and vendor information for tracking claim-related expenses.\n- The table facilitates vendor payment processing and expense tracking by maintaining detailed records of all invoiced items and their associated costs.\n- LIST OF COLUMNS: INV_ID (invoice identifier), INV_LINE_NBR (invoice line number), LINE_NO (links to CLAIM_LINES and FINANCIAL_TRANSACTIONS), DESCRIPTION (item/service description), CURRENCY (invoice currency), VENDOR (supplier name), INVOICE_DATE (invoice issue date), INVOICE_AMOUNT (invoice total)\n\nGUIDELINES_CHUNK_TABLE:\n- Database: INSURANCE_CLAIMS_DEMO, Schema: LOSS_CLAIMS\n- This table stores processed guidelines documents in chunks for easy retrieval and reference. It contains insurance claims processing guidelines broken into manageable text segments.\n- The table supports compliance and procedural guidance by providing searchable access to regulatory and company guidelines for claims handling.\n- LIST OF COLUMNS: FILENAME (guideline document name), FILE_URL (document storage location), CHUNK (guideline text segment), LANGUAGE (content language)\n\nNOTES_CHUNK_TABLE:\n- Database: INSURANCE_CLAIMS_DEMO, Schema: LOSS_CLAIMS\n- This table contains claim-specific notes and documentation broken into text chunks for analysis and retrieval. It stores detailed notes about claim progress, decisions, and observations.\n- The table provides comprehensive claim documentation history, enabling detailed tracking of claim handling decisions and progress updates.\n- LIST OF COLUMNS: FILENAME (notes document name), FILE_URL (document storage location), CHUNK (notes text segment), LANGUAGE (content language), CLAIM_NO (links to CLAIMS table)\n\nPARSED_INVOICES:\n- Database: INSURANCE_CLAIMS_DEMO, Schema: LOSS_CLAIMS\n- This table contains extracted content from invoice images or documents that have been processed through parsing technology. It stores the raw extracted text from invoice files for further processing.\n- The table enables automated invoice processing by capturing and storing parsed invoice content for integration with the structured invoice data.\n- LIST OF COLUMNS: FILENAME (source invoice file), EXTRACTED_CONTENT (parsed invoice text), PARSE_DATE (when parsing occurred)\n\nREASONING:\nThis semantic model represents a comprehensive insurance claims management system that tracks the complete lifecycle of property insurance claims from initial loss through financial settlement. The model centers around claims and their associated line items, with strong relationships connecting authorization limits, financial transactions, invoices, and supporting documentation. The system enforces financial controls through performer authorization limits while maintaining detailed audit trails of all financial activities and supporting documentation.\n\nDESCRIPTION:\nThe CA_INSURANCE_CLAIMS_DEMO semantic model is a comprehensive insurance claims management system from the INSURANCE_CLAIMS_DEMO database's LOSS_CLAIMS schema that tracks property insurance claims from loss occurrence through financial settlement. The model centers on the CLAIMS table which connects to CLAIM_LINES for detailed damage breakdowns, with each line item linked to FINANCIAL_TRANSACTIONS for payment tracking and INVOICES for vendor billing. The system includes financial controls through the AUTHORIZATION table that sets spending limits for performers, while NOTES_CHUNK_TABLE and GUIDELINES_CHUNK_TABLE provide supporting documentation and regulatory guidance. The PARSED_INVOICES table enables automated processing of invoice documents, creating a complete end-to-end claims processing workflow with full audit trails and compliance tracking."
        }
      },
      {
        "tool_spec": {
          "type": "cortex_search",
          "name": "Guidelines",
          "description": ""
        }
      },
      {
        "tool_spec": {
          "type": "cortex_search",
          "name": "claim_notes",
          "description": ""
        }
      },
      {
        "tool_spec": {
          "type": "generic",
          "name": "CLASSIFY_FUNCTION",
          "description": "PROCEDURE/FUNCTION DETAILS:\n- Type: Custom Function\n- Language: SQL\n- Signature: (FILE_NAME VARCHAR, STAGE_NAME VARCHAR)\n- Returns: OBJECT\n- Execution: Caller context with standard null handling\n- Volatility: Volatile (uses AI processing and current timestamp)\n- Primary Function: AI-powered document classification and analysis\n- Target: Files stored in Snowflake stages\n- Error Handling: Returns structured object with success indicators\n\nDESCRIPTION:\nThis AI-powered document classification function analyzes files stored in Snowflake stages to automatically identify and categorize document types such as invoices, medical bills, insurance claims, policy documents, and other business-critical documents. The function leverages Snowflake's AI_EXTRACT capability to perform intelligent document analysis, returning a comprehensive JSON object that includes the classification type, detailed description, business context, document purpose, and a confidence score averaged across multiple AI analysis dimensions. Users should ensure they have appropriate permissions to access the specified stage and file, as the function requires read access to stage data and AI processing capabilities enabled in their Snowflake environment. The function is particularly valuable for organizations processing large volumes of mixed document types, as it provides consistent, automated classification with detailed metadata that can drive downstream business processes. The returned object structure makes it easy to integrate with data pipelines, reporting systems, and workflow automation tools while maintaining full traceability through timestamp tracking and complete classification data preservation.\n\nUSAGE SCENARIOS:\n- Document intake processing: Automatically classify incoming documents from various sources (email attachments, file uploads, scanned documents) to route them to appropriate business processes and departments\n- Insurance claims processing: Analyze uploaded claim documents, evidence images, and supporting materials to streamline claim review workflows and ensure proper categorization for regulatory compliance\n- Financial document management: Classify invoices, receipts, financial statements, and correspondence to support automated accounting processes, audit trails, and regulatory reporting requirements"
        }
      },
      {
        "tool_spec": {
          "type": "generic",
          "name": "Parse_document",
          "description": "PROCEDURE/FUNCTION DETAILS:\n- Type: Custom Function\n- Language: SQL\n- Signature: (FILE_NAME VARCHAR)\n- Returns: VARIANT\n- Execution: Caller context with standard null handling\n- Volatility: Stable (depends on file content)\n- Primary Function: Document parsing and content extraction\n- Target: Files stored in the loss_evidence stage within the INSURANCE_CLAIMS_DEMO.loss_claims schema\n- Error Handling: Relies on Snowflake's AI_PARSE_DOCUMENT built-in error handling\n\nDESCRIPTION:\nThis custom SQL function serves as a specialized document processing tool designed specifically for insurance loss claims operations, leveraging Snowflake's AI-powered document parsing capabilities to extract structured data from evidence files. The function takes a file name as input and automatically retrieves the corresponding document from the designated loss_evidence file stage, then processes it using advanced layout analysis with page-splitting enabled to maintain document structure integrity. This function is particularly valuable for insurance companies and claims processors who need to systematically extract information from various types of loss evidence documents such as police reports, medical records, repair estimates, or photographic evidence submitted as part of insurance claims. The function returns data in VARIANT format, providing flexibility to handle diverse document types and extracted content structures, making it ideal for downstream processing workflows that require structured data analysis. Users should ensure they have appropriate access permissions to both the file stage and the AI_PARSE_DOCUMENT functionality, and should be prepared to handle potential parsing errors for corrupted or unsupported file formats.\n\nUSAGE SCENARIOS:\n- Claims Processing Automation: Automatically extract key information from newly submitted claim evidence documents to populate claim databases and accelerate adjuster review processes\n- Bulk Document Analysis: Process large volumes of historical claim documents to extract patterns, identify fraud indicators, or perform compliance audits across the insurance portfolio\n- Integration Testing: Validate document parsing workflows in development environments by testing various document formats and structures before deploying to production claim processing systems",
          "input_schema": {
            "type": "object",
            "properties": {
              "file_name": {
                "type": "string"
              }
            },
            "required": [
              "file_name"
            ]
          }
        }
      },
      {
        "tool_spec": {
          "type": "generic",
          "name": "Image_summary",
          "description": "PROCEDURE/FUNCTION DETAILS:\n- Type: Custom Function\n- Language: SQL\n- Signature: (IMAGE_FILE VARCHAR, STAGE_NAME VARCHAR)\n- Returns: VARCHAR\n- Execution: Caller context with standard null handling\n- Volatility: Volatile (depends on external AI service)\n- Primary Function: AI-powered image analysis and summarization\n- Target: Image files stored in Snowflake stages\n- Error Handling: Relies on Snowflake Cortex error handling\n\nDESCRIPTION:\nThis custom function leverages Snowflake's Cortex AI capabilities to automatically analyze and summarize images stored in your data warehouse stages. The function takes an image file name and stage location as inputs, then uses Claude-3.5-Sonnet AI model to generate concise 100-word summaries of key insights found in the image. This is particularly valuable for organizations dealing with large volumes of visual data such as charts, diagrams, documents, or photographs that need to be catalogued and understood at scale. Users must have appropriate permissions to access both the specified stage and Snowflake Cortex services, and should be aware that processing costs will apply for each AI model invocation. The function returns a text summary that can be stored, indexed, or used for further analysis workflows.\n\nUSAGE SCENARIOS:\n- Business Intelligence: Automatically summarize chart images, dashboard screenshots, or report visualizations to create searchable metadata and improve data discovery across your organization\n- Document Processing: Extract key insights from scanned documents, forms, or technical diagrams stored in your data lake to enable automated content classification and retrieval\n- Quality Assurance: Analyze product images, inspection photos, or monitoring screenshots to generate standardized descriptions for compliance reporting and audit trails",
          "input_schema": {
            "type": "object",
            "properties": {
              "image_file": {
                "type": "string"
              },
              "stage_name": {
                "description": "default the stage to INSURANCE_CLAIMS_DEMO.LOSS_CLAIMS.LOSS_EVIDENCE",
                "type": "string"
              }
            },
            "required": [
              "image_file",
              "stage_name"
            ]
          }
        }
      },
      {
        "tool_spec": {
          "type": "generic",
          "name": "TRANSCRIBE_CALLS",
          "description": "PROCEDURE/FUNCTION DETAILS:\n- Type: Custom Function\n- Language: SQL\n- Signature: (FILE_NAME VARCHAR, STAGE_NAME VARCHAR)\n- Returns: OBJECT\n- Execution: OWNER with exception handling\n- Volatility: Stable\n- Primary Function: Audio/Video File Transcription\n- Target: Media files stored in Snowflake stages\n- Error Handling: Comprehensive try-catch with structured error responses\n\nDESCRIPTION:\nThis custom function provides automated transcription capabilities for audio and video files stored in Snowflake stages, leveraging Snowflake's AI_TRANSCRIBE functionality with speaker-level timestamp granularity. The function takes a file name and stage name as parameters, processes the media file through Snowflake's AI transcription service, and returns a structured JSON object containing either the successful transcription results or detailed error information. It executes with OWNER privileges to ensure proper access to stage files and AI services, while implementing robust error handling that captures SQL error codes and messages for troubleshooting. The function is designed for business users who need to convert speech content from recorded meetings, interviews, or other audio/video materials into searchable text format. Users should ensure they have appropriate permissions to access the specified stage and that the target files are in supported audio/video formats, as the function will return detailed error information if transcription fails due to file format issues, permission problems, or AI service limitations.\n\nUSAGE SCENARIOS:\n- Meeting transcription: Convert recorded business meetings, conference calls, or interviews stored in Snowflake stages into searchable text with speaker identification and timestamps\n- Content analysis workflows: Process large volumes of audio/video content for compliance monitoring, sentiment analysis, or content categorization in data pipeline operations\n- Development and testing: Validate transcription accuracy and error handling behavior when building applications that integrate speech-to-text functionality with Snowflake's AI capabilities",
          "input_schema": {
            "type": "object",
            "properties": {
              "file_name": {
                "type": "string"
              },
              "stage_name": {
                "description": "default the stage to INSURANCE_CLAIMS_DEMO.LOSS_CLAIMS.LOSS_EVIDENCE",
                "type": "string"
              }
            },
            "required": [
              "file_name",
              "stage_name"
            ]
          }
        }
      }
    ],
    "tool_resources": {
      "CA_INS": {
        "semantic_view": "INSURANCE_CLAIMS_DEMO.LOSS_CLAIMS.CA_INSURANCE_CLAIMS_DEMO"
      },
      "CLASSIFY_FUNCTION": {
        "execution_environment": {
          "query_timeout": 30,
          "type": "warehouse",
          "warehouse": "CLAIMS_AGENT_WH"
        },
        "identifier": "INSURANCE_CLAIMS_DEMO_DB.ANALYTICS.CLASSIFY_DOCUMENT",
        "name": "CLASSIFY_DOCUMENT(VARCHAR, DEFAULT VARCHAR)",
        "type": "function"
      },
      "Guidelines": {
        "max_results": 4,
        "name": "INSURANCE_CLAIMS_DEMO.LOSS_CLAIMS.INSURANCE_CLAIMS_DEMO_GUIDELINES",
        "title_column": "filename",
        "id_column": "file_url"
      },
      "Image_summary": {
        "execution_environment": {
          "query_timeout": 60,
          "type": "warehouse",
          "warehouse": "CLAIMS_AGENT_WH"
        },
        "identifier": "INSURANCE_CLAIMS_DEMO.LOSS_CLAIMS.GET_IMAGE_SUMMARY",
        "name": "GET_IMAGE_SUMMARY(VARCHAR, VARCHAR)",
        "type": "function"
      },
      "Parse_document": {
        "execution_environment": {
          "query_timeout": 30,
          "type": "warehouse",
          "warehouse": "CLAIMS_AGENT_WH"
        },
        "identifier": "INSURANCE_CLAIMS_DEMO.LOSS_CLAIMS.PARSE_DOCUMENT_FROM_STAGE",
        "name": "PARSE_DOCUMENT_FROM_STAGE(VARCHAR)",
        "type": "function"
      },
      "TRANSCRIBE_CALLS": {
        "execution_environment": {
          "query_timeout": 60,
          "type": "warehouse",
          "warehouse": "CLAIMS_AGENT_WH"
        },
        "identifier": "INSURANCE_CLAIMS_DEMO.LOSS_CLAIMS.TRANSCRIBE_AUDIO_SIMPLE",
        "name": "TRANSCRIBE_AUDIO_SIMPLE(VARCHAR, DEFAULT VARCHAR)",
        "type": "procedure"
      },
      "claim_notes": {
        "max_results": 4,
        "name": "INSURANCE_CLAIMS_DEMO.LOSS_CLAIMS.INSURANCE_CLAIMS_DEMO_CLAIM_NOTES",
        "title_column": "filename",
        "id_column": "file_url"
      }
    }
  }
$$;

----- Automated URL Refresh System -----
-- Presigned URLs expire after 24 hours, so refresh every 12 hours to ensure links remain valid

CREATE OR REPLACE TASK INSURANCE_CLAIMS_DEMO.LOSS_CLAIMS.REFRESH_NOTES_PRESIGNED_URLS_TASK
  WAREHOUSE = CLAIMS_AGENT_WH
  SCHEDULE = 'USING CRON 0 1,13 * * * America/New_York'  -- Runs twice daily at 1:00 AM and 1:00 PM EST
  COMMENT = 'Refreshes presigned URLs for Notes Chunk Table every 12 hours to keep download links valid'
AS
  UPDATE INSURANCE_CLAIMS_DEMO.LOSS_CLAIMS.NOTES_CHUNK_TABLE
  SET file_url = GET_PRESIGNED_URL('@INSURANCE_CLAIMS_DEMO.loss_claims.loss_evidence', FILENAME, 86400);

CREATE OR REPLACE TASK INSURANCE_CLAIMS_DEMO.LOSS_CLAIMS.REFRESH_GUIDELINES_PRESIGNED_URLS_TASK
  WAREHOUSE = CLAIMS_AGENT_WH
  SCHEDULE = 'USING CRON 0 1,13 * * * America/New_York'  -- Runs twice daily at 1:00 AM and 1:00 PM EST
  COMMENT = 'Refreshes presigned URLs for Guidelines Chunk Table every 12 hours to keep download links valid'
AS
  UPDATE INSURANCE_CLAIMS_DEMO.LOSS_CLAIMS.GUIDELINES_CHUNK_TABLE
  SET file_url = GET_PRESIGNED_URL('@INSURANCE_CLAIMS_DEMO.loss_claims.loss_evidence', FILENAME, 86400);

-- Activate the tasks to start automatic URL refresh
ALTER TASK INSURANCE_CLAIMS_DEMO.LOSS_CLAIMS.REFRESH_NOTES_PRESIGNED_URLS_TASK RESUME;
ALTER TASK INSURANCE_CLAIMS_DEMO.LOSS_CLAIMS.REFRESH_GUIDELINES_PRESIGNED_URLS_TASK RESUME;