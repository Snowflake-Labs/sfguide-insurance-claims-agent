USE ROLE ACCOUNTADMIN;
ALTER SESSION SET query_tag = '{"origin":"sf_sit-is","name":"retail_banking_ai_demo","version":{"major":1,"minor":0},"attributes":{"is_quickstart":1,"source":"sql"}}';

CREATE OR REPLACE WAREHOUSE BI_LARGE_WH
  WITH 
  WAREHOUSE_SIZE = 'LARGE'
  WAREHOUSE_TYPE = 'STANDARD'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE
  COMMENT = '';

CREATE OR REPLACE WAREHOUSE ANALYTICS_RIA_WH
  WITH 
  WAREHOUSE_SIZE = 'LARGE'
  WAREHOUSE_TYPE = 'STANDARD'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE
  COMMENT = '';

CREATE ROLE IF NOT EXISTS CLAIMS_AGENT_ROLE;
GRANT ROLE CLAIMS_AGENT_ROLE TO ROLE ACCOUNTADMIN;

-- Grant necessary privileges to the role
GRANT CREATE DATABASE ON ACCOUNT TO ROLE CLAIMS_AGENT_ROLE;
GRANT CREATE WAREHOUSE ON ACCOUNT TO ROLE CLAIMS_AGENT_ROLE;
GRANT ROLE CLAIMS_AGENT_ROLE TO ROLE sysadmin;

-- snowflake intelligence setup
CREATE DATABASE IF NOT EXISTS snowflake_intelligence;
GRANT USAGE ON DATABASE snowflake_intelligence TO ROLE PUBLIC;

CREATE SCHEMA IF NOT EXISTS snowflake_intelligence.agents;
GRANT USAGE ON SCHEMA snowflake_intelligence.agents TO ROLE PUBLIC;

GRANT CREATE AGENT ON SCHEMA snowflake_intelligence.agents TO ROLE CLAIMS_AGENT_ROLE;

GRANT USAGE ON WAREHOUSE BI_LARGE_WH TO ROLE CLAIMS_AGENT_ROLE;
GRANT OPERATE ON WAREHOUSE BI_LARGE_WH TO ROLE CLAIMS_AGENT_ROLE;
GRANT USAGE ON WAREHOUSE ANALYTICS_RIA_WH TO ROLE CLAIMS_AGENT_ROLE;
GRANT OPERATE ON WAREHOUSE ANALYTICS_RIA_WH TO ROLE CLAIMS_AGENT_ROLE;

-- Switch to custom role for setup
USE ROLE CLAIMS_AGENT_ROLE;

CREATE OR REPLACE DATABASE BANKING;
USE DATABASE BANKING;
CREATE OR REPLACE SCHEMA AUTO_LOANS_DEMO;
USE SCHEMA AUTO_LOANS_DEMO;

-- 1) Customers
CREATE OR REPLACE TABLE CUSTOMERS (
  CUSTOMER_ID         NUMBER        NOT NULL,
  FIRST_NAME          STRING        NOT NULL,
  LAST_NAME           STRING        NOT NULL,
  EMAIL               STRING,
  PHONE               STRING,
  DOB                 DATE,
  ADDRESS_LINE1       STRING,
  CITY                STRING,
  STATE               STRING,
  POSTAL_CODE         STRING,
  CREATED_AT          TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
  SEGMENT             STRING,                         -- e.g., Prime, Near-Prime, Subprime
  PRIMARY KEY (CUSTOMER_ID)
);

-- 2) Customer Accounts (bank-level relationship)
CREATE OR REPLACE TABLE CUSTOMER_ACCOUNTS (
  ACCOUNT_ID          NUMBER        NOT NULL,
  CUSTOMER_ID         NUMBER        NOT NULL,
  ACCOUNT_OPEN_DATE   DATE          NOT NULL,
  STATUS              STRING,                         -- Active, Closed, Suspended
  BRANCH_ID           STRING,
  PRIMARY KEY (ACCOUNT_ID)
);

-- 3) Loan Applications
CREATE OR REPLACE TABLE LOAN_APPLICATIONS (
  APPLICATION_ID      NUMBER        NOT NULL,
  CUSTOMER_ID         NUMBER        NOT NULL,
  SUBMITTED_AT        TIMESTAMP_NTZ NOT NULL,
  CHANNEL             STRING,                         -- Branch, Online, Dealer
  PRODUCT             STRING,                         -- New Auto, Used Auto, Refinance
  AMOUNT_REQUESTED    NUMBER(12,2)  NOT NULL,
  TERM_MONTHS         NUMBER        NOT NULL,
  INTEREST_RATE_OFFERED NUMBER(5,3),
  STATUS              STRING,                         -- Approved, Denied, Pending
  DECISION_AT         TIMESTAMP_NTZ,
  REASON_CODE         STRING,                         -- e.g., DTI, CreditScore, IncomeVerif
  PRIMARY KEY (APPLICATION_ID)
);

-- 4) Loans (funded/active)
CREATE OR REPLACE TABLE LOANS (
  LOAN_ID             NUMBER        NOT NULL,
  CUSTOMER_ID         NUMBER        NOT NULL,
  APPLICATION_ID      NUMBER,
  ACCOUNT_ID          NUMBER,
  ORIGINATION_DATE    DATE          NOT NULL,
  PRINCIPAL           NUMBER(12,2)  NOT NULL,
  INTEREST_RATE       NUMBER(5,3)   NOT NULL,
  TERM_MONTHS         NUMBER        NOT NULL,
  MATURITY_DATE       DATE          NOT NULL,
  LOAN_STATUS         STRING,                         -- Active, PaidOff, ChargedOff
  PRIMARY KEY (LOAN_ID)
);

-- 5) Payments
CREATE OR REPLACE TABLE PAYMENTS (
  PAYMENT_ID          NUMBER        NOT NULL,
  LOAN_ID             NUMBER        NOT NULL,
  CUSTOMER_ID         NUMBER        NOT NULL,
  PAYMENT_DATE        DATE          NOT NULL,
  AMOUNT_DUE          NUMBER(12,2),
  AMOUNT_PAID         NUMBER(12,2),
  PRINCIPAL_COMPONENT NUMBER(12,2),
  INTEREST_COMPONENT  NUMBER(12,2),
  LATE_FEE            NUMBER(12,2),
  PAST_DUE_DAYS       NUMBER,
  PAYMENT_STATUS      STRING,                         -- OnTime, Late, Missed
  PRIMARY KEY (PAYMENT_ID)
);

-- 6) Vehicles
CREATE OR REPLACE TABLE VEHICLES (
  VEHICLE_ID          NUMBER        NOT NULL,
  LOAN_ID             NUMBER        NOT NULL,
  VIN                 STRING        NOT NULL,
  MAKE                STRING,
  MODEL               STRING,
  MODEL_YEAR          NUMBER,
  MSRP                NUMBER(12,2),
  PURCHASE_PRICE      NUMBER(12,2),
  MILEAGE_AT_PURCHASE NUMBER,
  DEALER_ID           STRING,
  PRIMARY KEY (VEHICLE_ID)
);

-- Customers
INSERT INTO CUSTOMERS (CUSTOMER_ID, FIRST_NAME, LAST_NAME, EMAIL, PHONE, DOB, ADDRESS_LINE1, CITY, STATE, POSTAL_CODE, SEGMENT, CREATED_AT) VALUES
  (1001,'Ava','Johnson','ava.johnson@example.com','555-111-0001','1987-03-14','12 Oak St','Austin','TX','73301','Prime',CURRENT_TIMESTAMP()),
  (1002,'Ben','Martinez','ben.martinez@example.com','555-111-0002','1991-07-22','99 Pine Ave','Phoenix','AZ','85001','Near-Prime',CURRENT_TIMESTAMP()),
  (1003,'Cara','Lee','cara.lee@example.com','555-111-0003','1983-12-03','77 Maple Dr','Denver','CO','80014','Prime',CURRENT_TIMESTAMP()),
  (1004,'Dev','Singh','dev.singh@example.com','555-111-0004','1996-05-18','450 Elm St','Columbus','OH','43004','Subprime',CURRENT_TIMESTAMP()),
  (1005,'Ella','Nguyen','ella.nguyen@example.com','555-111-0005','1979-09-09','8 Birch Rd','Tampa','FL','33601','Prime',CURRENT_TIMESTAMP());

-- Accounts
INSERT INTO CUSTOMER_ACCOUNTS (ACCOUNT_ID, CUSTOMER_ID, ACCOUNT_OPEN_DATE, STATUS, BRANCH_ID) VALUES
  (20001,1001,'2021-01-15','Active','BR001'),
  (20002,1002,'2022-05-03','Active','BR002'),
  (20003,1003,'2020-08-24','Active','BR003'),
  (20004,1004,'2023-02-11','Active','BR004'),
  (20005,1005,'2019-10-02','Active','BR005');

-- Applications
INSERT INTO LOAN_APPLICATIONS (APPLICATION_ID, CUSTOMER_ID, SUBMITTED_AT, CHANNEL, PRODUCT, AMOUNT_REQUESTED, TERM_MONTHS, INTEREST_RATE_OFFERED, STATUS, DECISION_AT, REASON_CODE) VALUES
  (30001,1001,'2023-11-02 10:15','Dealer','New Auto',35000,72,4.250,'Approved','2023-11-02 15:30',NULL),
  (30002,1002,'2024-01-18 09:05','Online','Used Auto',18000,60,7.750,'Approved','2024-01-18 14:10',NULL),
  (30003,1003,'2024-03-05 13:20','Branch','Refinance',22000,48,5.490,'Approved','2024-03-05 16:05',NULL),
  (30004,1004,'2024-04-22 11:40','Dealer','Used Auto',24000,72,12.990,'Denied','2024-04-22 17:50','CreditScore'),
  (30005,1005,'2023-09-14 12:00','Online','New Auto',42000,72,4.990,'Approved','2023-09-14 16:45',NULL),
  (30006,1002,'2024-06-09 08:55','Dealer','Refinance',15000,36,6.990,'Pending',NULL,NULL),
  (30007,1004,'2024-07-12 10:30','Online','Used Auto',16000,60,11.490,'Approved','2024-07-12 15:00',NULL);

-- Loans (only for approved applications)
INSERT INTO LOANS (LOAN_ID, CUSTOMER_ID, APPLICATION_ID, ACCOUNT_ID, ORIGINATION_DATE, PRINCIPAL, INTEREST_RATE, TERM_MONTHS, MATURITY_DATE, LOAN_STATUS) VALUES
  (40001,1001,30001,20001,'2023-11-10',35000,4.250,72,'2029-11-10','Active'),
  (40002,1002,30002,20002,'2024-01-25',18000,7.750,60,'2029-01-25','Active'),
  (40003,1003,30003,20003,'2024-03-12',22000,5.490,48,'2028-03-12','Active'),
  (40004,1005,30005,20005,'2023-09-20',42000,4.990,72,'2029-09-20','Active'),
  (40005,1004,30007,20004,'2024-07-20',16000,11.490,60,'2029-07-20','Active');

-- Vehicles
INSERT INTO VEHICLES (VEHICLE_ID, LOAN_ID, VIN, MAKE, MODEL, MODEL_YEAR, MSRP, PURCHASE_PRICE, MILEAGE_AT_PURCHASE, DEALER_ID) VALUES
  (50001,40001,'1FTFW1EF1EFA12345','Ford','F-150',2023,54000,38000,12,'DLR-TX-001'),
  (50002,40002,'2C4RC1BG0ERB67890','Toyota','Camry',2021,30000,18500,24000,'DLR-AZ-014'),
  (50003,40003,'3FA6P0H72FRG45678','Honda','Civic',2020,25000,21000,19000,'DLR-CO-207'),
  (50004,40004,'5N1AT2MV7EC987654','Tesla','Model 3',2023,42000,41500,5,'DLR-FL-300'),
  (50005,40005,'1HGBH41JXMN109186','Hyundai','Elantra',2022,21000,16200,8000,'DLR-OH-120');

-- Payments (a few months of activity; include on-time and late)
INSERT INTO PAYMENTS (PAYMENT_ID, LOAN_ID, CUSTOMER_ID, PAYMENT_DATE, AMOUNT_DUE, AMOUNT_PAID, PRINCIPAL_COMPONENT, INTEREST_COMPONENT, LATE_FEE, PAST_DUE_DAYS, PAYMENT_STATUS) VALUES
  (60001,40001,1001,'2023-12-15',550.00,550.00,420.00,130.00,0.00,0,'OnTime'),
  (60002,40001,1001,'2024-01-15',550.00,550.00,422.00,128.00,0.00,0,'OnTime'),
  (60003,40001,1001,'2024-02-16',550.00,560.00,425.00,125.00,10.00,1,'Late'),

  (60004,40002,1002,'2024-02-25',400.00,400.00,310.00,90.00,0.00,0,'OnTime'),
  (60005,40002,1002,'2024-03-25',400.00,380.00,290.00,90.00,0.00,5,'Late'),
  (60006,40002,1002,'2024-04-25',400.00,0.00,0.00,0.00,0.00,35,'Missed'),

  (60007,40003,1003,'2024-04-12',520.00,520.00,400.00,120.00,0.00,0,'OnTime'),
  (60008,40003,1003,'2024-05-12',520.00,520.00,402.00,118.00,0.00,0,'OnTime'),

  (60009,40004,1005,'2023-10-20',600.00,600.00,470.00,130.00,0.00,0,'OnTime'),
  (60010,40004,1005,'2023-11-20',600.00,600.00,472.00,128.00,0.00,0,'OnTime'),
  (60011,40004,1005,'2023-12-20',600.00,600.00,474.00,126.00,0.00,0,'OnTime'),

  (60012,40005,1004,'2024-08-20',360.00,360.00,270.00,90.00,0.00,0,'OnTime'),
  (60013,40005,1004,'2024-09-20',360.00,320.00,230.00,90.00,0.00,7,'Late');

USE DATABASE BANKING;
CREATE OR REPLACE SCHEMA CREDIT;
USE SCHEMA CREDIT;

-- 1) Credit Card Applications
CREATE OR REPLACE TABLE CREDIT_CARD_APPLICATIONS (
  CC_APPLICATION_ID       NUMBER        NOT NULL,
  CUSTOMER_ID             NUMBER        NOT NULL,
  SUBMITTED_AT            TIMESTAMP_NTZ NOT NULL,
  CHANNEL                 STRING,                         -- Branch, Online, Partner
  CARD_PRODUCT            STRING,                         -- CashBack, Travel, Platinum
  CREDIT_LIMIT_REQUESTED  NUMBER(12,2),
  APR_OFFERED             NUMBER(5,3),
  STATUS                  STRING,                         -- Approved, Denied, Pending
  DECISION_AT             TIMESTAMP_NTZ,
  REASON_CODE             STRING,                         -- e.g., CreditScore, DTI
  PRIMARY KEY (CC_APPLICATION_ID)
);

-- 2) Credit Cards (approved/active)
CREATE OR REPLACE TABLE CREDIT_CARDS (
  CARD_ID                 NUMBER        NOT NULL,
  CUSTOMER_ID             NUMBER        NOT NULL,
  ACCOUNT_ID              NUMBER,                         -- references CORE.CUSTOMER_ACCOUNTS
  APPLICATION_ID          NUMBER,                         -- references CREDIT_CARD_APPLICATIONS
  CARD_NUMBER_TOKEN       STRING        NOT NULL,         -- tokenized, not real PAN
  CARD_PRODUCT            STRING,
  OPEN_DATE               DATE          NOT NULL,
  STATUS                  STRING,                         -- Active, Closed, Suspended
  CREDIT_LIMIT            NUMBER(12,2)  NOT NULL,
  CURRENT_BALANCE         NUMBER(12,2)  DEFAULT 0,
  APR                     NUMBER(5,3)   NOT NULL,
  PRIMARY KEY (CARD_ID)
);

-- 3) Merchants
CREATE OR REPLACE TABLE MERCHANTS (
  MERCHANT_ID             NUMBER        NOT NULL,
  MERCHANT_NAME           STRING        NOT NULL,
  MCC                     STRING,                         -- Merchant Category Code
  CITY                    STRING,
  STATE                   STRING,
  COUNTRY                 STRING,
  PRIMARY KEY (MERCHANT_ID)
);

-- 4) Card Transactions
CREATE OR REPLACE TABLE CARD_TRANSACTIONS (
  TRANSACTION_ID          NUMBER        NOT NULL,
  CARD_ID                 NUMBER        NOT NULL,
  CUSTOMER_ID             NUMBER        NOT NULL,
  MERCHANT_ID             NUMBER,
  AUTH_TIMESTAMP          TIMESTAMP_NTZ NOT NULL,
  POST_DATE               DATE,
  AMOUNT                  NUMBER(12,2)  NOT NULL,
  CURRENCY                STRING        DEFAULT 'USD',
  CATEGORY                STRING,                         -- Grocery, Fuel, Travel, Dining, Electronics, etc.
  CHANNEL                 STRING,                         -- POS, ECOM, Contactless
  STATUS                  STRING,                         -- Authorized, Posted, Reversed, Disputed
  PRIMARY KEY (TRANSACTION_ID)
);

-- 5) Card Statements
CREATE OR REPLACE TABLE CARD_STATEMENTS (
  STATEMENT_ID            NUMBER        NOT NULL,
  CARD_ID                 NUMBER        NOT NULL,
  STATEMENT_PERIOD_START  DATE          NOT NULL,
  STATEMENT_PERIOD_END    DATE          NOT NULL,
  DUE_DATE                DATE          NOT NULL,
  STATEMENT_BALANCE       NUMBER(12,2)  NOT NULL,
  MIN_PAYMENT_DUE         NUMBER(12,2)  NOT NULL,
  PRIMARY KEY (STATEMENT_ID)
);

-- 6) Card Payments
CREATE OR REPLACE TABLE CARD_PAYMENTS (
  CARD_PAYMENT_ID         NUMBER        NOT NULL,
  CARD_ID                 NUMBER        NOT NULL,
  CUSTOMER_ID             NUMBER        NOT NULL,
  STATEMENT_ID            NUMBER,                         -- optional: payment applied to statement
  PAYMENT_DATE            DATE          NOT NULL,
  AMOUNT                  NUMBER(12,2)  NOT NULL,
  METHOD                  STRING,                         -- ACH, Debit, Check
  STATUS                  STRING,                         -- Received, Returned
  PRIMARY KEY (CARD_PAYMENT_ID)
);

-- Applications (reuses customer_ids 1001..1005 from CORE.CUSTOMERS)
INSERT INTO CREDIT_CARD_APPLICATIONS (CC_APPLICATION_ID, CUSTOMER_ID, SUBMITTED_AT, CHANNEL, CARD_PRODUCT, CREDIT_LIMIT_REQUESTED, APR_OFFERED, STATUS, DECISION_AT, REASON_CODE) VALUES
  (70001,1001,'2024-06-10 09:45','Online','CashBack',15000,18.990,'Approved','2024-06-10 14:30',NULL),
  (70002,1002,'2024-07-02 11:20','Branch','Travel',12000,22.990,'Approved','2024-07-02 16:05',NULL),
  (70003,1003,'2024-07-15 13:10','Online','Platinum',20000,16.990,'Denied','2024-07-15 17:25','CreditScore'),
  (70004,1004,'2024-08-01 10:05','Partner','CashBack',8000,27.990,'Approved','2024-08-01 15:40',NULL),
  (70005,1005,'2024-06-25 12:00','Online','Travel',25000,17.990,'Approved','2024-06-25 15:10',NULL);

-- Cards (map approved apps to accounts from CORE.CUSTOMER_ACCOUNTS 20001..20005)
INSERT INTO CREDIT_CARDS (CARD_ID, CUSTOMER_ID, ACCOUNT_ID, APPLICATION_ID, CARD_NUMBER_TOKEN, CARD_PRODUCT, OPEN_DATE, STATUS, CREDIT_LIMIT, CURRENT_BALANCE, APR) VALUES
  (80001,1001,20001,70001,'4111-XXXX-XXXX-1234','CashBack','2024-06-15','Active',15000,1250.35,18.990),
  (80002,1002,20002,70002,'4111-XXXX-XXXX-2345','Travel','2024-07-05','Active',12000,3420.00,22.990),
  (80003,1004,20004,70004,'4111-XXXX-XXXX-3456','CashBack','2024-08-05','Active',8000,610.50,27.990),
  (80004,1005,20005,70005,'4111-XXXX-XXXX-4567','Travel','2024-06-28','Active',25000,9875.20,17.990);

-- Merchants
INSERT INTO MERCHANTS (MERCHANT_ID, MERCHANT_NAME, MCC, CITY, STATE, COUNTRY) VALUES
  (90001,'FreshMarket Grocery','5411','Austin','TX','US'),
  (90002,'FuelFast Station','5541','Phoenix','AZ','US'),
  (90003,'Skyways Airlines','4511','Denver','CO','US'),
  (90004,'Bistro Bella','5812','Columbus','OH','US'),
  (90005,'TechHub Electronics','5732','Tampa','FL','US'),
  (90006,'Global Hotel Group','7011','Miami','FL','US');

-- Transactions (mix of authorized, posted, reversed, disputed)
INSERT INTO CARD_TRANSACTIONS (TRANSACTION_ID, CARD_ID, CUSTOMER_ID, MERCHANT_ID, AUTH_TIMESTAMP, POST_DATE, AMOUNT, CURRENCY, CATEGORY, CHANNEL, STATUS) VALUES
  (91001,80001,1001,90001,'2024-08-05 18:10','2024-08-06',82.45,'USD','Grocery','POS','Posted'),
  (91002,80001,1001,90004,'2024-08-10 19:30','2024-08-11',56.20,'USD','Dining','POS','Posted'),
  (91003,80001,1001,90005,'2024-08-20 14:05','2024-08-21',399.99,'USD','Electronics','ECOM','Posted'),

  (91004,80002,1002,90002,'2024-08-07 08:25','2024-08-07',65.30,'USD','Fuel','POS','Posted'),
  (91005,80002,1002,90003,'2024-08-22 12:00','2024-08-23',780.00,'USD','Travel','ECOM','Posted'),
  (91006,80002,1002,90006,'2024-08-25 21:10',NULL,450.00,'USD','Travel','ECOM','Authorized'),

  (91007,80003,1004,90001,'2024-08-12 09:15','2024-08-13',34.18,'USD','Grocery','POS','Posted'),
  (91008,80003,1004,90002,'2024-08-15 07:50','2024-08-15',42.60,'USD','Fuel','POS','Posted'),
  (91009,80003,1004,90004,'2024-08-28 20:45','2024-08-29',88.00,'USD','Dining','POS','Reversed'),

  (91010,80004,1005,90005,'2024-08-03 10:05','2024-08-04',1299.00,'USD','Electronics','ECOM','Posted'),
  (91011,80004,1005,90006,'2024-08-18 22:10','2024-08-19',650.00,'USD','Travel','ECOM','Posted'),
  (91012,80004,1005,90003,'2024-08-28 06:40','2024-08-29',420.00,'USD','Travel','ECOM','Disputed');

-- Statements (Aug and Sep 2024 cycles)
INSERT INTO CARD_STATEMENTS (STATEMENT_ID, CARD_ID, STATEMENT_PERIOD_START, STATEMENT_PERIOD_END, DUE_DATE, STATEMENT_BALANCE, MIN_PAYMENT_DUE) VALUES
  (92001,80001,'2024-08-01','2024-08-31','2024-09-25',538.64,35.00),
  (92002,80002,'2024-08-01','2024-08-31','2024-09-20',1245.30,40.00),
  (92003,80003,'2024-08-01','2024-08-31','2024-09-22',164.78,30.00),
  (92004,80004,'2024-08-01','2024-08-31','2024-09-18',2369.00,71.00),

  (92005,80001,'2024-09-01','2024-09-30','2024-10-25',711.91,35.00),
  (92006,80002,'2024-09-01','2024-09-30','2024-10-20',2310.00,69.00),
  (92007,80003,'2024-09-01','2024-09-30','2024-10-22',205.38,30.00),
  (92008,80004,'2024-09-01','2024-09-30','2024-10-18',3150.40,95.00);

-- Payments (on-time and returned)
INSERT INTO CARD_PAYMENTS (CARD_PAYMENT_ID, CARD_ID, CUSTOMER_ID, STATEMENT_ID, PAYMENT_DATE, AMOUNT, METHOD, STATUS) VALUES
  (93001,80001,1001,92001,'2024-09-20',200.00,'ACH','Received'),
  (93002,80002,1002,92002,'2024-09-18',50.00,'Debit','Returned'),
  (93003,80003,1004,92003,'2024-09-21',40.00,'ACH','Received'),
  (93004,80004,1005,92004,'2024-09-16',100.00,'ACH','Received'),

  (93005,80001,1001,92005,'2024-10-22',100.00,'ACH','Received'),
  (93006,80002,1002,92006,'2024-10-18',80.00,'ACH','Received'),
  (93007,80003,1004,92007,'2024-10-20',35.00,'Debit','Received'),
  (93008,80004,1005,92008,'2024-10-15',95.00,'ACH','Received');

  -- Create semantic views --
  CREATE OR REPLACE SEMANTIC VIEW BANKING.CREDIT.CREDIT_SEMANTIC_VIEW
	TABLES (
		CARD_PAYMENTS primary key (CARD_PAYMENT_ID),
		CARD_STATEMENTS primary key (STATEMENT_ID),
		CARD_TRANSACTIONS primary key (TRANSACTION_ID),
		CREDIT_CARDS primary key (CARD_ID),
		CREDIT_CARD_APPLICATIONS primary key (CC_APPLICATION_ID),
		MERCHANTS primary key (MERCHANT_ID),
		BANKING.AUTO_LOANS_DEMO.CUSTOMERS primary key (CUSTOMER_ID) with synonyms=('clients','patrons','buyers','shoppers','consumers','users','accounts','profiles','individuals','persons') comment='The CUSTOMERS table stores information about individual customers, including their personal details, contact information, and demographic data, with a unique identifier for each customer.',
		BANKING.AUTO_LOANS_DEMO.CUSTOMER_ACCOUNTS primary key (ACCOUNT_ID)
	)
	RELATIONSHIPS (
		APPS_CUSTOMERS as CREDIT_CARD_APPLICATIONS(CUSTOMER_ID) references CUSTOMERS(CUSTOMER_ID)
	)
	FACTS (
		CARD_PAYMENTS.AMOUNT as AMOUNT with synonyms=('cost','price','total','payment_value','charge','fee','sum','value','transaction_amount') comment='The amount of each payment made by card.',
		CARD_STATEMENTS.MIN_PAYMENT_DUE as MIN_PAYMENT_DUE with synonyms=('minimum_payment_required','minimum_due','lowest_payment','minimum_payment_amount','smallest_payment_due','least_payment_required') comment='The minimum payment due on the credit card account for the current billing cycle.',
		CARD_STATEMENTS.STATEMENT_BALANCE as STATEMENT_BALANCE with synonyms=('outstanding_balance','current_balance','statement_total','account_balance','balance_due') comment='The current balance of the card account as of the statement date, representing the total amount owed by the cardholder.',
		CARD_TRANSACTIONS.AMOUNT as AMOUNT with synonyms=('cost','price','total','value','quantity','sum','payment','charge','fee','transaction_value') comment='The amount of the transaction, representing the value of the goods or services purchased.',
		CARD_TRANSACTIONS.CARD_ID as CARD_ID with synonyms=('card_number','card_identifier','payment_card_id','account_id','card_account_number','card_reference') comment='Unique identifier for a specific credit or debit card used to make a transaction.',
		CARD_TRANSACTIONS.CUSTOMER_ID as CUSTOMER_ID with synonyms=('client_id','user_id','account_holder_id','cardholder_id','account_number','customer_number') comment='Unique identifier for the customer who made the transaction.',
		CARD_TRANSACTIONS.MERCHANT_ID as MERCHANT_ID with synonyms=('seller_id','vendor_id','retailer_id','store_id','supplier_id','trader_id','business_id') comment='Unique identifier for the merchant where the transaction took place.',
		CARD_TRANSACTIONS.TRANSACTION_ID as TRANSACTION_ID with synonyms=('transaction_number','transaction_code','transaction_key','unique_transaction_identifier','transaction_reference','transaction_serial_number','transaction_identifier') comment='Unique identifier for each transaction made on a credit or debit card.',
		CREDIT_CARDS.APR as APR with synonyms=('annual_percentage_rate','interest_rate','yearly_interest_rate','finance_charge_rate','nominal_interest_rate') comment='Annual Percentage Rate (APR) of the credit card, representing the interest rate charged on outstanding balances.',
		CREDIT_CARDS.CREDIT_LIMIT as CREDIT_LIMIT with synonyms=('available_credit','credit_ceiling','credit_maximum','max_credit','credit_allowance','credit_cap','credit_threshold','maximum_credit_limit') comment='The maximum amount of credit that can be used on a credit card.',
		CREDIT_CARDS.CURRENT_BALANCE as CURRENT_BALANCE with synonyms=('outstanding_balance','current_amount','account_balance','available_balance','existing_balance','present_balance','balance_due','current_account_value') comment='The current outstanding balance on the credit card account, representing the total amount owed by the customer.',
		CREDIT_CARD_APPLICATIONS.APR_OFFERED as APR_OFFERED with synonyms=('interest_rate_offered','offered_apr','annual_percentage_rate','interest_rate_applied','offered_interest_rate') comment='The APR (Annual Percentage Rate) offered to the customer as part of the credit card application.',
		CREDIT_CARD_APPLICATIONS.CREDIT_LIMIT_REQUESTED as CREDIT_LIMIT_REQUESTED with synonyms=('requested_credit_amount','credit_request','desired_credit_limit','applied_credit_limit','requested_loan_amount','credit_application_amount') comment='The amount of credit the applicant is requesting to be approved for on their new credit card.'
	)
	DIMENSIONS (
		CARD_PAYMENTS.CARD_ID as CARD_ID with synonyms=('card_number','card_identifier','payment_card_id','credit_card_id','card_reference') comment='Unique identifier for a credit or debit card used to make a payment.',
		CARD_PAYMENTS.CARD_PAYMENT_ID as CARD_PAYMENT_ID with synonyms=('payment_id','transaction_id','card_transaction_number','payment_reference','payment_identifier','card_payment_reference') comment='Unique identifier for a card payment transaction.',
		CARD_PAYMENTS.CUSTOMER_ID as CUSTOMER_ID with synonyms=('client_id','account_holder_id','user_id','account_owner_id','patron_id') comment='Unique identifier for the customer who made the payment.',
		CARD_PAYMENTS.METHOD as METHOD with synonyms=('payment_method','payment_type','transaction_method','payment_mode','payment_channel','payment_option') comment='The payment method used for the transaction, either Automated Clearing House (ACH) or Debit card.',
		CARD_PAYMENTS.PAYMENT_DATE as PAYMENT_DATE with synonyms=('transaction_date','payment_timestamp','settlement_date','payment_made_date','date_paid','payment_completion_date') comment='Date on which the payment was made.',
		CARD_PAYMENTS.STATEMENT_ID as STATEMENT_ID with synonyms=('invoice_id','transaction_id','payment_statement_id','billing_id','account_statement_id','payment_reference_id') comment='Unique identifier for a specific card payment statement.',
		CARD_PAYMENTS.STATUS as STATUS with synonyms=('state','condition','situation','position','standing','category','classification','designation') comment='The status of the card payment, indicating whether the payment was successfully received or was returned due to insufficient funds, expired card, or other reasons.',
		CARD_STATEMENTS.CARD_ID as CARD_ID with synonyms=('card_number','account_id','account_number','card_account_id','payment_card_id') comment='Unique identifier for a specific credit or debit card.',
		CARD_STATEMENTS.DUE_DATE as DUE_DATE with synonyms=('payment_due_date','due_by_date','payment_deadline','invoice_due_date','bill_due_date','settlement_date') comment='The date by which the payment for the card statement is due.',
		CARD_STATEMENTS.STATEMENT_ID as STATEMENT_ID with synonyms=('statement_number','transaction_id','invoice_id','account_statement_id','record_id','entry_id') comment='Unique identifier for a specific card statement.',
		CARD_STATEMENTS.STATEMENT_PERIOD_END as STATEMENT_PERIOD_END with synonyms=('statement_period_close','end_of_statement_period','statement_cycle_end','billing_cycle_end','statement_close_date') comment='The date that marks the end of the statement period for a card account, typically the last day of the billing cycle.',
		CARD_STATEMENTS.STATEMENT_PERIOD_START as STATEMENT_PERIOD_START with synonyms=('start_date','period_begin','statement_begin_date','cycle_start','billing_cycle_start','period_start_date') comment='The date when the statement period begins, marking the start of the billing cycle for the card account.',
		CARD_TRANSACTIONS.AUTH_TIMESTAMP as AUTH_TIMESTAMP with synonyms=('auth_date','authorization_time','auth_time','timestamp_auth','auth_datetime','transaction_timestamp','auth_timestamp_utc') comment='The date and time when the card transaction was authorized.',
		CARD_TRANSACTIONS.CATEGORY as CATEGORY with synonyms=('type','classification','group','kind','genre','sort','class','designation') comment='The category of the transaction, indicating the type of merchant or service where the transaction took place, such as a grocery store, restaurant, or gas station.',
		CARD_TRANSACTIONS.CHANNEL as CHANNEL with synonyms=('medium','platform','method','medium_of_transaction','transaction_channel','payment_channel','sales_channel') comment='The channel through which the card transaction was made, either at a physical Point of Sale (POS) or through an Electronic Commerce (ECOM) platform.',
		CARD_TRANSACTIONS.CURRENCY as CURRENCY with synonyms=('money_unit','denomination','exchange_unit','tender_type','monetary_unit','coin_type','payment_currency','transaction_denomination') comment='The currency in which the transaction was made.',
		CARD_TRANSACTIONS.POST_DATE as POST_DATE with synonyms=('posting_date','transaction_date','payment_date','settlement_date','processing_date','date_posted') comment='Date when the transaction was posted to the account.',
		CARD_TRANSACTIONS.STATUS as STATUS with synonyms=('state','condition','situation','position','standing','outcome','result','phase') comment='The status of the card transaction, indicating whether it has been successfully posted to the account (Posted), is pending authorization (Authorized), or is being disputed by the cardholder (Disputed).',
		CREDIT_CARDS.ACCOUNT_ID as ACCOUNT_ID with synonyms=('account_number','account_no','account_identifier','account_code','account_reference') comment='Unique identifier for a customer''s credit card account.',
		CREDIT_CARDS.APPLICATION_ID as APPLICATION_ID with synonyms=('app_id','application_number','app_num','request_id','submission_id','registration_id') comment='Unique identifier for a credit card application.',
		CREDIT_CARDS.CARD_ID as CARD_ID with synonyms=('card_number','card_identifier','credit_card_id','card_key','account_card_id','unique_card_identifier') comment='Unique identifier for a credit card account.',
		CREDIT_CARDS.CARD_NUMBER_TOKEN as CARD_NUMBER_TOKEN with synonyms=('masked_card_number','tokenized_card_number','secure_card_number','encrypted_card_number','protected_card_number','card_number_hash') comment='A unique tokenized representation of a customer''s credit card number, with all but the last four digits masked for security and compliance purposes.',
		CREDIT_CARDS.CARD_PRODUCT as CARD_PRODUCT with synonyms=('card_type','card_category','product_name','card_description','card_offering','card_program','card_plan') comment='The type of credit card product offered, such as CashBack or Travel, which determines the rewards and benefits associated with the card.',
		CREDIT_CARDS.CUSTOMER_ID as CUSTOMER_ID with synonyms=('client_id','customer_number','account_holder_id','user_id','patron_id','client_number','account_owner_id') comment='Unique identifier for the customer who owns the credit card.',
		CREDIT_CARDS.OPEN_DATE as OPEN_DATE with synonyms=('activation_date','start_date','card_activation_date','account_opening_date','card_issue_date','effective_date') comment='Date when the credit card account was opened.',
		CREDIT_CARDS.STATUS as STATUS with synonyms=('state','condition','situation','position','standing','card_state','account_status') comment='The current state of the credit card account, indicating whether it is currently in use and available for transactions.',
		CREDIT_CARD_APPLICATIONS.CARD_PRODUCT as CARD_PRODUCT with synonyms=('card_type','credit_card_type','card_category','product_name','card_offer','card_program','card_scheme') comment='The type of credit card product applied for, such as CashBack, Travel, or Platinum, which determines the benefits and features associated with the card.',
		CREDIT_CARD_APPLICATIONS.CC_APPLICATION_ID as CC_APPLICATION_ID with synonyms=('application_id','credit_card_app_id','app_id','credit_app_number','application_number','cc_app_number') comment='Unique identifier for each credit card application submitted by a customer.',
		CREDIT_CARD_APPLICATIONS.CHANNEL as CHANNEL with synonyms=('medium','platform','source','medium_of_application','application_channel','submission_channel','application_medium','sales_channel') comment='The channel through which the credit card application was submitted, indicating whether the application was made online, in-person at a branch, or through a partner organization.',
		CREDIT_CARD_APPLICATIONS.CUSTOMER_ID as CUSTOMER_ID with synonyms=('client_id','customer_number','account_holder_id','user_id','account_number','client_number','patron_id') comment='Unique identifier for the customer applying for a credit card.',
		CREDIT_CARD_APPLICATIONS.DECISION_AT as DECISION_AT with synonyms=('decision_made_at','decision_date','approved_at','approved_date','resolved_at','resolved_date','outcome_date','outcome_time','verdict_at') comment='The date and time when the credit card application decision was made.',
		CREDIT_CARD_APPLICATIONS.REASON_CODE as REASON_CODE with synonyms=('decision_reason','rejection_code','approval_code','application_status_code','outcome_code','result_code','denial_reason','approval_reason') comment='The reason why the credit card application was approved or denied, with a value of "CreditScore" indicating that the decision was based on the applicant''s credit score.',
		CREDIT_CARD_APPLICATIONS.STATUS as STATUS with synonyms=('state','condition','situation','position','standing','outcome','result','decision','determination','resolution') comment='The current status of the credit card application, indicating whether the application has been approved or denied.',
		CREDIT_CARD_APPLICATIONS.SUBMITTED_AT as SUBMITTED_AT with synonyms=('SUBMISSION_TIMESTAMP','APPLICATION_DATE','REQUEST_TIMESTAMP','SUBMISSION_DATE','RECEIVED_AT','CREATED_AT','APPLICATION_TIMESTAMP') comment='Date and time when the credit card application was submitted.',
		MERCHANTS.CITY as CITY with synonyms=('town','municipality','metropolis','urban_area','location','municipality_name','geographical_location','urban_center') comment='The city where the merchant is located.',
		MERCHANTS.COUNTRY as COUNTRY with synonyms=('nation','land','territory','state','region','nationality','homeland','territory_name') comment='The country where the merchant is located.',
		MERCHANTS.MCC as MCC with synonyms=('merchant_category_code','merchant_type','industry_code','business_category','sic_code','merchant_group') comment='Merchant Category Code (MCC) is a four-digit number assigned to a business by credit card companies to classify the type of goods or services it provides, such as grocery stores (5411), gasoline stations (5541), and airlines (4511).',
		MERCHANTS.MERCHANT_ID as MERCHANT_ID with synonyms=('seller_id','vendor_id','retailer_id','supplier_id','merchant_key','business_id','store_id') comment='Unique identifier for a merchant in the system, used to distinguish between different merchants and track their transactions and activities.',
		MERCHANTS.MERCHANT_NAME as MERCHANT_NAME with synonyms=('merchant_title','business_name','company_name','store_name','vendor_name','supplier_name','retailer_name') comment='The name of the merchant or business that a transaction was made with.',
		MERCHANTS.STATE as STATE with synonyms=('province','region','territory','county','area','location','jurisdiction','district') comment='The two-letter code representing the state in which the merchant is located.',
		CUSTOMERS.ADDRESS_LINE1 as ADDRESS_LINE1 with synonyms=('street_address','street_number','house_number','mailing_address','physical_address','residence_address','primary_address','street_name_and_number') comment='The street address of the customer''s primary location.',
		CUSTOMERS.CITY as CITY with synonyms=('town','municipality','metropolis','urban_area','locality','settlement','burg','municipality_name') comment='The city where the customer is located.',
		CUSTOMERS.CREATED_AT as CREATED_AT with synonyms=('created_date','creation_date','creation_time','date_created','timestamp','registration_date','signup_date','joined_at','added_at') comment='Date and time when the customer account was created.',
		CUSTOMERS.CUSTOMER_ID as CUSTOMER_ID with synonyms=('customer_key','client_id','user_id','account_number','customer_number','client_number','account_id','user_number') comment='Unique identifier for each customer in the database, used to distinguish and track individual customer records.',
		CUSTOMERS.DOB as DOB with synonyms=('date_of_birth','birth_date','birthdate','birthday','date_of_origin') comment='Date of Birth of the customer.',
		CUSTOMERS.EMAIL as EMAIL with synonyms=('email_address','contact_email','user_email','customer_email','email_id') comment='The email address of the customer.',
		CUSTOMERS.FIRST_NAME as FIRST_NAME with synonyms=('given_name','first_name','forename','personal_name','christian_name') comment='The first name of the customer.',
		CUSTOMERS.LAST_NAME as LAST_NAME with synonyms=('surname','family_name','last_name_field','full_last_name','patronymic','family_surname') comment='The customer''s last name.',
		CUSTOMERS.PHONE as PHONE with synonyms=('telephone','mobile','cell','contact_number','phone_number') comment='The phone number associated with each customer.',
		CUSTOMERS.POSTAL_CODE as POSTAL_CODE with synonyms=('zip_code','postcode','zip','postal','mailing_code','geographic_code','area_code') comment='The postal code of the customer''s mailing address.',
		CUSTOMERS.SEGMENT as SEGMENT with synonyms=('category','group','classification','tier','section','division','subgroup','demographic') comment='Customer creditworthiness classification, categorizing customers into three segments: Prime (low credit risk), Near-Prime (moderate credit risk), and Subprime (high credit risk).',
		CUSTOMERS.STATE as STATE with synonyms=('province','region','territory','county','parish','prefecture','district','area','location','jurisdiction') comment='The two-letter abbreviation for the state where the customer resides.',
		CUSTOMER_ACCOUNTS.ACCOUNT_ID as ACCOUNT_ID with synonyms=('account_number','account_key','account_identifier','account_code','account_reference') comment='Unique identifier for a customer''s account.',
		CUSTOMER_ACCOUNTS.ACCOUNT_OPEN_DATE as ACCOUNT_OPEN_DATE with synonyms=('account_creation_date','account_start_date','date_account_opened','account_initiation_date','account_established_date') comment='Date when the customer account was opened.',
		CUSTOMER_ACCOUNTS.BRANCH_ID as BRANCH_ID with synonyms=('branch_code','location_id','office_id','department_id','site_id','facility_id') comment='Unique identifier for the branch where the customer account is located.',
		CUSTOMER_ACCOUNTS.CUSTOMER_ID as CUSTOMER_ID with synonyms=('client_id','customer_number','account_holder_id','patron_id','user_id') comment='Unique identifier for each customer account.',
		CUSTOMER_ACCOUNTS.STATUS as STATUS with synonyms=('state','condition','situation','position','standing','account_status','account_condition','current_state') comment='The current state of the customer''s account, indicating whether it is currently active and available for use.'
	)
	with extension (CA='{"tables":[{"name":"CARD_PAYMENTS","dimensions":[{"name":"CARD_ID","sample_values":["80001","80002","80003"]},{"name":"CARD_PAYMENT_ID","sample_values":["93001","93002","93003"]},{"name":"CUSTOMER_ID","sample_values":["1001","1002","1004"]},{"name":"METHOD","sample_values":["ACH","Debit"]},{"name":"STATEMENT_ID","sample_values":["92001","92002","92003"]},{"name":"STATUS","sample_values":["Received","Returned"]}],"facts":[{"name":"AMOUNT","sample_values":["200.00","50.00","40.00"]}],"time_dimensions":[{"name":"PAYMENT_DATE","sample_values":["2024-09-20","2024-09-18","2024-09-21"]}]},{"name":"CARD_STATEMENTS","dimensions":[{"name":"CARD_ID","sample_values":["80001","80002","80003"]},{"name":"STATEMENT_ID","sample_values":["92001","92002","92003"]}],"facts":[{"name":"MIN_PAYMENT_DUE","sample_values":["35.00","40.00","30.00"]},{"name":"STATEMENT_BALANCE","sample_values":["538.64","1245.30","164.78"]}],"time_dimensions":[{"name":"DUE_DATE","sample_values":["2024-09-25","2024-09-20","2024-09-22"]},{"name":"STATEMENT_PERIOD_END","sample_values":["2024-08-31","2024-09-30"]},{"name":"STATEMENT_PERIOD_START","sample_values":["2024-08-01","2024-09-01"]}]},{"name":"CARD_TRANSACTIONS","dimensions":[{"name":"CATEGORY","sample_values":["Grocery","Dining","Fuel"]},{"name":"CHANNEL","sample_values":["POS","ECOM"]},{"name":"CURRENCY","sample_values":["USD"]},{"name":"STATUS","sample_values":["Posted","Authorized","Disputed"]}],"facts":[{"name":"AMOUNT","sample_values":["82.45","56.20","88.00"]},{"name":"CARD_ID","sample_values":["80001","80002","80003"]},{"name":"CUSTOMER_ID","sample_values":["1001","1002","1004"]},{"name":"MERCHANT_ID","sample_values":["90001","90004","90005"]},{"name":"TRANSACTION_ID","sample_values":["91001","91003","91004"]}],"time_dimensions":[{"name":"AUTH_TIMESTAMP","sample_values":["2024-08-05T18:10:00.000+0000","2024-08-10T19:30:00.000+0000","2024-08-20T14:05:00.000+0000"]},{"name":"POST_DATE","sample_values":["2024-08-06","2024-08-11","2024-08-21"]}]},{"name":"CREDIT_CARDS","dimensions":[{"name":"ACCOUNT_ID","sample_values":["20001","20002","20004"]},{"name":"APPLICATION_ID","sample_values":["70001","70002","70004"]},{"name":"CARD_ID","sample_values":["80001","80002","80003"]},{"name":"CARD_NUMBER_TOKEN","sample_values":["4111-XXXX-XXXX-1234","4111-XXXX-XXXX-2345","4111-XXXX-XXXX-3456"]},{"name":"CARD_PRODUCT","sample_values":["CashBack","Travel"]},{"name":"CUSTOMER_ID","sample_values":["1001","1002","1004"]},{"name":"STATUS","sample_values":["Active"]}],"facts":[{"name":"APR","sample_values":["18.990","27.990","22.990"]},{"name":"CREDIT_LIMIT","sample_values":["15000.00","12000.00","8000.00"]},{"name":"CURRENT_BALANCE","sample_values":["1250.35","3420.00","610.50"]}],"time_dimensions":[{"name":"OPEN_DATE","sample_values":["2024-06-15","2024-07-05","2024-08-05"]}]},{"name":"CREDIT_CARD_APPLICATIONS","dimensions":[{"name":"CARD_PRODUCT","sample_values":["CashBack","Travel","Platinum"]},{"name":"CC_APPLICATION_ID","sample_values":["70001","70002","70003"]},{"name":"CHANNEL","sample_values":["Online","Branch","Partner"]},{"name":"CUSTOMER_ID","sample_values":["1001","1002","1003"]},{"name":"REASON_CODE","sample_values":["CreditScore"]},{"name":"STATUS","sample_values":["Approved","Denied"]}],"facts":[{"name":"APR_OFFERED","sample_values":["18.990","16.990","22.990"]},{"name":"CREDIT_LIMIT_REQUESTED","sample_values":["15000.00","12000.00","20000.00"]}],"time_dimensions":[{"name":"DECISION_AT","sample_values":["2024-06-10T14:30:00.000+0000","2024-07-02T16:05:00.000+0000","2024-07-15T17:25:00.000+0000"]},{"name":"SUBMITTED_AT","sample_values":["2024-06-10T09:45:00.000+0000","2024-07-02T11:20:00.000+0000","2024-07-15T13:10:00.000+0000"]}]},{"name":"MERCHANTS","dimensions":[{"name":"CITY","sample_values":["Austin","Phoenix","Denver"]},{"name":"COUNTRY","sample_values":["US"]},{"name":"MCC","sample_values":["5411","5541","4511"]},{"name":"MERCHANT_ID","sample_values":["90001","90002","90003"]},{"name":"MERCHANT_NAME","sample_values":["FreshMarket Grocery","FuelFast Station","Skyways Airlines"]},{"name":"STATE","sample_values":["TX","AZ","CO"]}]},{"name":"CUSTOMERS","dimensions":[{"name":"ADDRESS_LINE1","sample_values":["12 Oak St","99 Pine Ave","77 Maple Dr"]},{"name":"CITY","sample_values":["Austin","Phoenix","Denver"]},{"name":"CUSTOMER_ID","sample_values":["1001","1002","1003"]},{"name":"EMAIL","sample_values":["ava.johnson@example.com","ben.martinez@example.com","cara.lee@example.com"]},{"name":"FIRST_NAME","sample_values":["Ava","Ben","Cara"]},{"name":"LAST_NAME","sample_values":["Johnson","Martinez","Lee"]},{"name":"PHONE","sample_values":["555-111-0001","555-111-0002","555-111-0003"]},{"name":"POSTAL_CODE","sample_values":["73301","85001","80014"]},{"name":"SEGMENT","sample_values":["Prime","Subprime","Near-Prime"]},{"name":"STATE","sample_values":["TX","AZ","CO"]}],"time_dimensions":[{"name":"CREATED_AT","sample_values":["2025-08-28T13:25:32.184+0000"]},{"name":"DOB","sample_values":["1987-03-14","1991-07-22","1983-12-03"]}]},{"name":"CUSTOMER_ACCOUNTS","dimensions":[{"name":"ACCOUNT_ID","sample_values":["20001","20002","20003"]},{"name":"BRANCH_ID","sample_values":["BR001","BR002","BR003"]},{"name":"CUSTOMER_ID","sample_values":["1001","1002","1003"]},{"name":"STATUS","sample_values":["Active"]}],"time_dimensions":[{"name":"ACCOUNT_OPEN_DATE","sample_values":["2021-01-15","2022-05-03","2020-08-24"]}]}],"relationships":[{"name":"apps_customers"}],"verified_queries":[{"name":"what are Active cards, average credit limit, and average APR by product?","question":"what are Active cards, average credit limit, and average APR by product?","sql":"SELECT\\n  card_product,\\n  COUNT(card_id) AS active_cards,\\n  AVG(credit_limit) AS avg_credit_limit,\\n  AVG(apr) AS avg_apr,\\n  MIN(open_date) AS start_date,\\n  MAX(open_date) AS end_date\\nFROM\\n  credit_cards\\nWHERE\\n  status = ''Active''\\nGROUP BY\\n  card_product","use_as_onboarding_question":false,"verified_by":"Marie Duran","verified_at":1756424088},{"name":"Transaction volume and total amount by merchant category for August 2024; top 10 merchants by transaction volume","question":"Transaction volume and total amount by merchant category for August 2024; top 10 merchants by transaction volume","sql":"WITH august_transactions AS (\\n  SELECT\\n    ct.category,\\n    ct.merchant_id,\\n    COUNT(ct.transaction_id) AS transaction_volume,\\n    SUM(ct.amount) AS total_amount\\n  FROM\\n    card_transactions AS ct\\n  WHERE\\n    DATE_TRUNC(''MONTH'', ct.post_date) = ''2024-08-01''\\n  GROUP BY\\n    ct.category,\\n    ct.merchant_id\\n),\\ntop_merchants AS (\\n  SELECT\\n    merchant_id,\\n    transaction_volume,\\n    RANK() OVER (\\n      ORDER BY\\n        transaction_volume DESC NULLS LAST\\n    ) AS rnk\\n  FROM\\n    august_transactions\\n)\\nSELECT\\n  at.category,\\n  at.merchant_id,\\n  at.transaction_volume,\\n  at.total_amount\\nFROM\\n  august_transactions AS at\\nUNION ALL\\nSELECT\\n  NULL AS category,\\n  tm.merchant_id,\\n  tm.transaction_volume,\\n  NULL AS total_amount\\nFROM\\n  top_merchants AS tm\\nWHERE\\n  tm.rnk <= 10\\nORDER BY\\n  transaction_volume DESC NULLS LAST","use_as_onboarding_question":false,"verified_by":"Marie Duran","verified_at":1756424271}],"custom_instructions":"You are a data analyst for a credit card business"}');

USE DATABASE BANKING;
USE SCHEMA AUTO_LOANS_DEMO;

CREATE OR REPLACE SEMANTIC VIEW BANKING.AUTO_LOANS_DEMO.AUTO_LOANS_SEMANTIC_VIEW
	TABLES (
		CUSTOMERS primary key (CUSTOMER_ID),
		CUSTOMER_ACCOUNTS primary key (ACCOUNT_ID),
		LOANS primary key (LOAN_ID),
		LOAN_APPLICATIONS primary key (APPLICATION_ID),
		PAYMENTS primary key (PAYMENT_ID),
		VEHICLES primary key (VEHICLE_ID)
	)
	RELATIONSHIPS (
		CUSTOMERS_ACCOUNTS as CUSTOMER_ACCOUNTS(CUSTOMER_ID) references CUSTOMERS(CUSTOMER_ID),
		LOANS_ACCOUNTS as LOANS(ACCOUNT_ID) references CUSTOMER_ACCOUNTS(ACCOUNT_ID),
		LOANS_APPLICATIONS as LOANS(APPLICATION_ID) references LOAN_APPLICATIONS(APPLICATION_ID),
		CUSTOMERS_APPLICATIONS as LOAN_APPLICATIONS(CUSTOMER_ID) references CUSTOMERS(CUSTOMER_ID),
		LOANS_CUSTOMERS as LOAN_APPLICATIONS(CUSTOMER_ID) references CUSTOMERS(CUSTOMER_ID)
	)
	FACTS (
		LOANS.INTEREST_RATE as INTEREST_RATE with synonyms=('interest_percentage','annual_percentage_rate','apr','rate_of_interest','finance_rate','loan_rate') comment='The interest rate charged on a loan, expressed as a percentage.',
		LOANS.PRINCIPAL as PRINCIPAL with synonyms=('initial_amount','loan_amount','face_value','original_loan_amount','initial_investment','capital_sum') comment='The principal amount borrowed by a customer, representing the initial amount of the loan before any interest or fees are applied.',
		LOANS.TERM_MONTHS as TERM_MONTHS with synonyms=('loan_duration','loan_term','loan_length','repayment_period','loan_tenure','months_to_maturity') comment='The number of months over which a loan is to be repaid.',
		LOAN_APPLICATIONS.AMOUNT_REQUESTED as AMOUNT_REQUESTED with synonyms=('loan_amount','requested_loan','amount_applied','loan_value','requested_funds','applied_amount') comment='The amount of money that the applicant is requesting to borrow.',
		LOAN_APPLICATIONS.INTEREST_RATE_OFFERED as INTEREST_RATE_OFFERED with synonyms=('interest_rate_quote','offered_apr','quoted_interest_rate','proposed_interest_rate','offered_rate','interest_rate_proposed') comment='The interest rate offered to the borrower as part of the loan application, expressed as a percentage.',
		LOAN_APPLICATIONS.TERM_MONTHS as TERM_MONTHS with synonyms=('loan_duration','loan_term','loan_length','repayment_period','loan_tenure','months_to_repay') comment='The number of months over which the loan will be repaid.',
		PAYMENTS.AMOUNT_DUE as AMOUNT_DUE with synonyms=('outstanding_balance','amount_owing','amount_payable','payment_due_amount','amount_to_be_paid','unsettled_amount','pending_payment','due_amount','payable_amount') comment='The amount of payment due from a customer for a specific transaction or invoice.',
		PAYMENTS.AMOUNT_PAID as AMOUNT_PAID with synonyms=('payment_amount','paid_amount','amount_settled','payment_made','settled_amount','paid_sum') comment='The amount of payment made by a customer.',
		PAYMENTS.INTEREST_COMPONENT as INTEREST_COMPONENT with synonyms=('interest_amount','interest_payment','interest_portion','interest_charge','finance_charge','interest_fee') comment='The amount of interest paid on a loan or investment, representing the portion of the payment that is not applied to the principal amount.',
		PAYMENTS.LATE_FEE as LATE_FEE with synonyms=('late_charge','overdue_fee','penalty_amount','late_payment_fee','additional_fee','surcharge','overdue_charge') comment='The amount charged to a customer for making a payment after the due date.',
		PAYMENTS.PAST_DUE_DAYS as PAST_DUE_DAYS with synonyms=('overdue_days','days_overdue','days_past_due','delinquency_days','days_in_arrears') comment='The number of days a payment is past its due date.',
		PAYMENTS.PRINCIPAL_COMPONENT as PRINCIPAL_COMPONENT with synonyms=('principal_amount','capital_component','loan_principal','main_payment','core_payment','base_amount','primary_component','main_component') comment='The principal component of a payment, representing the amount applied towards the outstanding loan balance, excluding interest and fees.',
		VEHICLES.MILEAGE_AT_PURCHASE as MILEAGE_AT_PURCHASE with synonyms=('odometer_reading_at_purchase','initial_mileage','purchase_odometer','mileage_at_acquisition','starting_mileage','initial_odometer_reading') comment='The total mileage of the vehicle at the time of purchase.',
		VEHICLES.MODEL_YEAR as MODEL_YEAR with synonyms=('model_year','vehicle_year','car_year','production_year','manufacture_year','vehicle_age','model_age') comment='The model year of the vehicle, representing the year in which the vehicle was manufactured.',
		VEHICLES.MSRP as MSRP with synonyms=('Manufacturer Suggested Retail Price','Sticker Price','List Price','Base Price','Suggested Retail Price','Retail Price') comment='The Manufacturer''s Suggested Retail Price (MSRP) of each vehicle, representing the base price set by the manufacturer before any customizations, options, or destination fees are added.',
		VEHICLES.PURCHASE_PRICE as PURCHASE_PRICE with synonyms=('buy_price','sale_price','purchase_cost','acquisition_price','buying_price','vehicle_cost','purchase_amount') comment='The purchase price of a vehicle, representing the amount paid to acquire the vehicle.',
		VEHICLES.VEHICLE_ID as VEHICLE_ID with synonyms=('vehicle_key','vehicle_identifier','vehicle_number','vehicle_code','vehicle_unique_id','vehicle_reference_id') comment='Unique identifier for each vehicle in the fleet.'
	)
	DIMENSIONS (
		CUSTOMERS.ADDRESS_LINE1 as ADDRESS_LINE1 with synonyms=('street_address','street_number','house_number','mailing_address','residence_address','physical_address','location_address','primary_address') comment='The street address of the customer''s primary location.',
		CUSTOMERS.CITY as CITY with synonyms=('town','municipality','metropolis','urban_area','locality','settlement','burg','municipality_name') comment='The city where the customer is located.',
		CUSTOMERS.CREATED_AT as CREATED_AT with synonyms=('created_date','creation_date','creation_time','date_created','timestamp','registration_date','signup_date','joined_at','added_at') comment='Date and time when the customer account was created.',
		CUSTOMERS.CUSTOMER_ID as CUSTOMER_ID with synonyms=('customer_key','client_id','user_id','account_number','customer_number','client_number','account_id','user_number') comment='Unique identifier for each customer in the database, used to distinguish and track individual customer records.',
		CUSTOMERS.DOB as DOB with synonyms=('date_of_birth','birth_date','birthdate','birthday','dob_date') comment='Date of Birth of the customer.',
		CUSTOMERS.EMAIL as EMAIL with synonyms=('email_address','contact_email','customer_email','user_email','email_id') comment='The email address of the customer.',
		CUSTOMERS.FIRST_NAME as FIRST_NAME with synonyms=('given_name','first_name','forename','personal_name','christian_name') comment='The first name of the customer.',
		CUSTOMERS.LAST_NAME as LAST_NAME with synonyms=('surname','family_name','last_name_field','full_last_name','patronymic','family_surname') comment='The customer''s last name.',
		CUSTOMERS.PHONE as PHONE with synonyms=('telephone','mobile','cell','contact_number','phone_number') comment='The phone number associated with each customer.',
		CUSTOMERS.POSTAL_CODE as POSTAL_CODE with synonyms=('zip_code','postcode','zip','postal','mailing_code','geographic_code') comment='The postal code of the customer''s mailing address.',
		CUSTOMERS.SEGMENT as SEGMENT with synonyms=('category','group','classification','tier','section','division','subgroup','demographic') comment='Customer creditworthiness classification, categorizing customers into three segments: Prime (low credit risk), Near-Prime (moderate credit risk), and Subprime (high credit risk).',
		CUSTOMERS.STATE as STATE with synonyms=('province','region','territory','county','parish','prefecture','district','area','location','jurisdiction') comment='The two-letter abbreviation for the state where the customer resides.',
		CUSTOMER_ACCOUNTS.ACCOUNT_ID as ACCOUNT_ID with synonyms=('account_number','account_key','account_identifier','account_code','account_reference') comment='Unique identifier for a customer''s account.',
		CUSTOMER_ACCOUNTS.ACCOUNT_OPEN_DATE as ACCOUNT_OPEN_DATE with synonyms=('account_creation_date','account_start_date','date_account_opened','account_initiation_date','account_established_date') comment='Date when the customer account was opened.',
		CUSTOMER_ACCOUNTS.BRANCH_ID as BRANCH_ID with synonyms=('branch_code','location_id','office_id','department_id','regional_id','site_id','facility_id') comment='Unique identifier for the branch where the customer account is located.',
		CUSTOMER_ACCOUNTS.CUSTOMER_ID as CUSTOMER_ID with synonyms=('client_id','customer_number','account_holder_id','patron_id','user_id') comment='Unique identifier for each customer account.',
		CUSTOMER_ACCOUNTS.STATUS as STATUS with synonyms=('state','condition','situation','position','standing','account_status','account_condition','current_state') comment='The current state of the customer''s account, indicating whether it is currently active and available for use.',
		LOANS.ACCOUNT_ID as ACCOUNT_ID with synonyms=('account_number','account_no','account_identifier','account_code','account_reference') comment='Unique identifier for a customer''s account.',
		LOANS.APPLICATION_ID as APPLICATION_ID with synonyms=('app_id','loan_app_id','application_number','loan_application_id','submission_id') comment='Unique identifier for a loan application.',
		LOANS.CUSTOMER_ID as CUSTOMER_ID with synonyms=('client_id','customer_number','account_holder_id','borrower_id','client_number','patron_id') comment='Unique identifier for the customer who borrowed the loan.',
		LOANS.LOAN_ID as LOAN_ID with synonyms=('loan_number','loan_identifier','loan_key','account_loan_id','loan_reference_id','loan_unique_id') comment='Unique identifier for each loan in the system.',
		LOANS.LOAN_STATUS as LOAN_STATUS with synonyms=('loan_condition','loan_state','loan_phase','loan_position','loan_situation','loan_category','loan_stage') comment='The current status of the loan, indicating whether it is currently being repaid (Active) or has been fully repaid or defaulted (other values not listed).',
		LOANS.MATURITY_DATE as MATURITY_DATE with synonyms=('due_date','expiration_date','end_date','loan_expiration','repayment_date','termination_date','final_payment_date') comment='The date on which the loan is scheduled to be fully repaid, marking the end of the loan term.',
		LOANS.ORIGINATION_DATE as ORIGINATION_DATE with synonyms=('start_date','loan_initiation_date','loan_creation_date','loan_start','loan_begin_date','loan_commencement_date','loan_issue_date') comment='The date on which the loan was originated, marking the beginning of the loan period.',
		LOAN_APPLICATIONS.APPLICATION_ID as APPLICATION_ID with synonyms=('app_id','loan_id','application_number','request_id','submission_id','loan_request_id','application_reference') comment='Unique identifier for each loan application submitted by a customer.',
		LOAN_APPLICATIONS.CHANNEL as CHANNEL with synonyms=('medium','platform','source','origin','medium_of_submission','application_medium','submission_channel','application_source') comment='The channel through which the loan application was submitted, indicating whether the application was initiated by a car dealer, online through the company''s website, or in-person at a physical branch location.',
		LOAN_APPLICATIONS.CUSTOMER_ID as CUSTOMER_ID with synonyms=('client_id','customer_number','account_holder_id','user_id','account_number','client_number') comment='Unique identifier for the customer who submitted the loan application.',
		LOAN_APPLICATIONS.DECISION_AT as DECISION_AT with synonyms=('decision_made_at','decision_date','approved_at','approved_date','resolved_at','resolved_date','outcome_date','outcome_at','result_date','result_at') comment='The date and time when a decision was made on the loan application.',
		LOAN_APPLICATIONS.PRODUCT as PRODUCT with synonyms=('item','merchandise','goods','commodity','article','loan_type','financial_product','banking_product') comment='The type of loan product being applied for, indicating whether the loan is for a new vehicle purchase, a used vehicle purchase, or a refinancing of an existing loan.',
		LOAN_APPLICATIONS.REASON_CODE as REASON_CODE with synonyms=('decision_reason','rejection_code','approval_code','status_reason','outcome_code','result_code','explanation_code') comment='The reason why the loan application was approved or rejected based on the applicant''s credit score.',
		LOAN_APPLICATIONS.STATUS as STATUS with synonyms=('state','condition','situation','position','standing','outcome','result','decision','resolution','disposition') comment='The current state of the loan application, indicating whether it has been approved, denied, or is still pending review.',
		LOAN_APPLICATIONS.SUBMITTED_AT as SUBMITTED_AT with synonyms=('SUBMISSION_DATE','SUBMISSION_TIMESTAMP','APPLICATION_DATE','RECEIVED_AT','CREATED_AT','REQUEST_DATE','ENTRY_DATE','REGISTRATION_DATE') comment='Date and time when the loan application was submitted.',
		PAYMENTS.CUSTOMER_ID as CUSTOMER_ID with synonyms=('client_id','customer_number','account_holder_id','account_owner_id','user_id') comment='Unique identifier for the customer who made the payment.',
		PAYMENTS.LOAN_ID as LOAN_ID with synonyms=('loan_number','loan_reference','loan_identifier','account_id','credit_id','financing_id','mortgage_id') comment='Unique identifier for a loan, used to track and manage individual loan accounts.',
		PAYMENTS.PAYMENT_DATE as PAYMENT_DATE with synonyms=('payment_timestamp','transaction_date','settlement_date','payment_due_date','payment_made_date','date_paid','payment_completion_date','transaction_timestamp') comment='Date on which the payment was made.',
		PAYMENTS.PAYMENT_ID as PAYMENT_ID with synonyms=('payment_key','transaction_id','payment_reference','payment_identifier','invoice_number','payment_number','transaction_reference') comment='Unique identifier for each payment transaction.',
		PAYMENTS.PAYMENT_STATUS as PAYMENT_STATUS with synonyms=('payment_state','payment_condition','transaction_status','payment_outcome','payment_result','payment_resolution') comment='The status of a payment, indicating whether it was made on time, late, or missed.',
		VEHICLES.DEALER_ID as DEALER_ID with synonyms=('dealer_code','supplier_id','vendor_id','seller_id','retailer_id','distributor_id') comment='Unique identifier for the dealership that owns or sells the vehicle.',
		VEHICLES.LOAN_ID as LOAN_ID with synonyms=('loan_number','financing_id','credit_id','mortgage_id','financing_agreement_id','loan_agreement_number') comment='Unique identifier for a loan associated with a vehicle.',
		VEHICLES.MAKE as MAKE with synonyms=('manufacturer','brand','vehicle_brand','car_maker','auto_maker','vehicle_manufacturer') comment='The make of the vehicle, representing the manufacturer or brand of the vehicle.',
		VEHICLES.MODEL as MODEL with synonyms=('car_model','vehicle_type','make_model','auto_model','vehicle_make','car_type','automobile_model') comment='The vehicle model, which represents the specific make and model of a vehicle, such as a car, truck, or SUV, as designated by the manufacturer.',
		VEHICLES.VIN as VIN with synonyms=('vehicle_identification_number','vehicle_id_number','vehicle_serial_number','chassis_number','vehicle_code') comment='Unique Vehicle Identification Number (VIN) assigned to each vehicle by the manufacturer, used to identify and track individual vehicles.'
	)
	metrics (
		LOANS.LOAN_COUNT as COUNT(LOAN_ID) with synonyms=('number_of_loans','loan_volume','total_loans','loan_quantity','count_of_loans') comment='The total number of loans taken out by a customer.'
	)
	comment='Semantic model for Auto Loans chatbot (customers, loans, applications, payments, vehicles, accounts)'
	with extension (CA='{"tables":[{"name":"CUSTOMERS","dimensions":[{"name":"ADDRESS_LINE1","sample_values":["12 Oak St","99 Pine Ave","77 Maple Dr"]},{"name":"CITY","sample_values":["Austin","Phoenix","Denver"]},{"name":"CUSTOMER_ID","sample_values":["1001","1002","1003"]},{"name":"EMAIL","sample_values":["ava.johnson@example.com","ben.martinez@example.com","cara.lee@example.com"]},{"name":"FIRST_NAME","sample_values":["Ava","Ben","Cara"]},{"name":"LAST_NAME","sample_values":["Johnson","Martinez","Lee"]},{"name":"PHONE","sample_values":["555-111-0001","555-111-0002","555-111-0003"]},{"name":"POSTAL_CODE","sample_values":["73301","85001","80014"]},{"name":"SEGMENT","sample_values":["Prime","Subprime","Near-Prime"]},{"name":"STATE","sample_values":["TX","AZ","CO"]}],"time_dimensions":[{"name":"CREATED_AT","sample_values":["2025-08-28T13:25:32.184+0000"]},{"name":"DOB","sample_values":["1987-03-14","1991-07-22","1983-12-03"]}]},{"name":"CUSTOMER_ACCOUNTS","dimensions":[{"name":"ACCOUNT_ID","sample_values":["20001","20002","20003"]},{"name":"BRANCH_ID","sample_values":["BR001","BR002","BR003"]},{"name":"CUSTOMER_ID","sample_values":["1001","1002","1003"]},{"name":"STATUS","sample_values":["Active"]}],"time_dimensions":[{"name":"ACCOUNT_OPEN_DATE","sample_values":["2021-01-15","2022-05-03","2020-08-24"]}]},{"name":"LOANS","dimensions":[{"name":"ACCOUNT_ID","sample_values":["20001","20002","20003"]},{"name":"APPLICATION_ID","sample_values":["30001","30002","30003"]},{"name":"CUSTOMER_ID","sample_values":["1001","1002","1003"]},{"name":"LOAN_ID","sample_values":["40001","40002","40003"]},{"name":"LOAN_STATUS","sample_values":["Active"]}],"facts":[{"name":"INTEREST_RATE","sample_values":["4.250","7.750","5.490"]},{"name":"PRINCIPAL","sample_values":["35000.00","18000.00","22000.00"]},{"name":"TERM_MONTHS","sample_values":["72","60","48"]}],"metrics":[{"name":"LOAN_COUNT"}],"time_dimensions":[{"name":"MATURITY_DATE","sample_values":["2029-11-10","2029-01-25","2028-03-12"]},{"name":"ORIGINATION_DATE","sample_values":["2023-11-10","2024-01-25","2024-03-12"]}]},{"name":"LOAN_APPLICATIONS","dimensions":[{"name":"APPLICATION_ID","sample_values":["30001","30002","30003"]},{"name":"CHANNEL","sample_values":["Dealer","Online","Branch"]},{"name":"CUSTOMER_ID","sample_values":["1001","1002","1003"]},{"name":"PRODUCT","sample_values":["New Auto","Used Auto","Refinance"]},{"name":"REASON_CODE","sample_values":["CreditScore"]},{"name":"STATUS","sample_values":["Approved","Denied","Pending"]}],"facts":[{"name":"AMOUNT_REQUESTED","sample_values":["35000.00","18000.00","22000.00"]},{"name":"INTEREST_RATE_OFFERED","sample_values":["4.250","7.750","5.490"]},{"name":"TERM_MONTHS","sample_values":["72","60","48"]}],"time_dimensions":[{"name":"DECISION_AT","sample_values":["2023-11-02T15:30:00.000+0000","2024-01-18T14:10:00.000+0000","2024-03-05T16:05:00.000+0000"]},{"name":"SUBMITTED_AT","sample_values":["2023-11-02T10:15:00.000+0000","2024-01-18T09:05:00.000+0000","2024-03-05T13:20:00.000+0000"]}]},{"name":"PAYMENTS","dimensions":[{"name":"CUSTOMER_ID","sample_values":["1001","1002","1003"]},{"name":"LOAN_ID","sample_values":["40001","40002","40003"]},{"name":"PAYMENT_ID","sample_values":["60001","60002","60003"]},{"name":"PAYMENT_STATUS","sample_values":["OnTime","Late","Missed"]}],"facts":[{"name":"AMOUNT_DUE","sample_values":["550.00","400.00","520.00"]},{"name":"AMOUNT_PAID","sample_values":["550.00","560.00","400.00"]},{"name":"INTEREST_COMPONENT","sample_values":["130.00","128.00","125.00"]},{"name":"LATE_FEE","sample_values":["0.00","10.00"]},{"name":"PAST_DUE_DAYS","sample_values":["0","1","5"]},{"name":"PRINCIPAL_COMPONENT","sample_values":["420.00","422.00","310.00"]}],"time_dimensions":[{"name":"PAYMENT_DATE","sample_values":["2023-12-15","2024-01-15","2024-02-16"]}]},{"name":"VEHICLES","dimensions":[{"name":"DEALER_ID","sample_values":["DLR-TX-001","DLR-AZ-014","DLR-CO-207"]},{"name":"LOAN_ID","sample_values":["40001","40002","40003"]},{"name":"MAKE","sample_values":["Ford","Toyota","Honda"]},{"name":"MODEL","sample_values":["F-150","Camry","Civic"]},{"name":"VIN","sample_values":["1FTFW1EF1EFA12345","2C4RC1BG0ERB67890","3FA6P0H72FRG45678"]}],"facts":[{"name":"MILEAGE_AT_PURCHASE","sample_values":["12","24000","19000"]},{"name":"MODEL_YEAR","sample_values":["2023","2021","2020"]},{"name":"MSRP","sample_values":["54000.00","30000.00","25000.00"]},{"name":"PURCHASE_PRICE","sample_values":["38000.00","18500.00","21000.00"]},{"name":"VEHICLE_ID","sample_values":["50001","50002","50003"]}]}],"relationships":[{"name":"CUSTOMERS_ACCOUNTS"},{"name":"LOANS_ACCOUNTS"},{"name":"LOANS_APPLICATIONS"},{"name":"CUSTOMERS_APPLICATIONS"},{"name":"LOANS_CUSTOMERS"}],"verified_queries":[{"name":"How many auto loans were originated by month and average interest rate?","question":"How many auto loans were originated by month and average interest rate?","sql":"SELECT\\n  DATE_TRUNC(''MONTH'', origination_date) AS month,\\n  COUNT(loan_id) AS num_loans,\\n  AVG(interest_rate) AS avg_interest_rate\\nFROM\\n  loans\\nGROUP BY\\n  DATE_TRUNC(''MONTH'', origination_date)\\nORDER BY\\n  month DESC NULLS LAST","use_as_onboarding_question":false,"verified_by":"Marie Duran","verified_at":1756413221}],"module_custom_instructions":{"question_categorization":"Reject all questions asking about users. Direct users to their admin","sql_generation":"Ensure that all numeric calculations are rounded to the nearest 2 decimals"}}');

-- create agent --

CREATE OR REPLACE AGENT SNOWFLAKE_INTELLIGENCE.AGENTS.CONSUMER_BANK_AGENT
FROM SPECIFICATION
$$
{
    "models": {
      "orchestration": "auto"
    },
    "instructions": {
      "response": "Ask 1 clarifying question when intent is ambiguous (e.g., time period, filters, LOB).\n  - Default time grain to month and time range to last 12 months if not specified.\n  - Include a brief executive summary (1–3 sentences) before the table/chart.\n  - Show both table and a suitable chart when trends or distributions are implied.\n  - Display SQL used (collapsed by default if UI supports) and reference entities/measures.\n  - Formatting:\n      - Currency: $ with thousands separators; no decimals for whole-dollar aggregates.\n      - Percentages: 2 decimals (e.g., 7.32%).\n      - Dates: YYYY‑MM or YYYY‑MM‑DD depending on grain.\n  - Definitions: If a metric is not obvious (e.g., approval rate, 30+ DPD), state formula.\n  - PII/Privacy: Do not display email/phone unless explicitly requested by an authorized user intent.\n  - Error handling: If a measure/dimension is unavailable, explain and suggest the closest supported query.\n  - Follow‑ups: Offer 2–3 next questions that deepen the analysis (e.g., by channel, product, segment).\n  - Reproducibility: Keep filters explicit in the narrative (time range, LOBs, segments, geography).\n",
      "orchestration": "Step 1: Parse intent\n      - Identify LOB(s), time range, grain, measures, dimensions, and filters.\n      - If missing, ask a single clarifying question; otherwise apply defaults.\n  - Step 2: Map to semantic model\n      - Choose the relevant model(s) and entities.\n      - Resolve measures (e.g., approval_rate, delinquency_rate_30dpd, utilization) and required joins via defined relationships.\n  - Step 3: Construct the query plan\n      - Select time grain; add WHERE on time, LOB, and filters.\n      - Choose aggregations and limited dimensions; avoid high‑cardinality explosions.\n      - For cross‑LOB questions, compute sub‑metrics separately, then join or union at the customer level as defined by relationships.\n  - Step 4: Generate SQL via semantic model\n      - Use only model-exposed measures/dimensions; avoid raw columns unless requested.\n      - Include safe defaults (e.g., last 12 months) and clear aliases for readability.\n  - Step 5: Execute and validate\n      - Sanity-check result sizes; if empty or out-of-range, suggest adjusting filters/time.\n      - If a derived metric is undefined, provide the definition and compute from available measures.\n  - Step 6: Present results\n      - Start with a 1–3 sentence insight summary.\n      - Provide a compact table; add a time-series or bar chart when appropriate.\n      - Show SQL used and list key assumptions/filters.\n  - Step 7: Recommend next steps\n      - Offer 2–3 follow-up queries (e.g., deeper by channel/product/segment or drill into outliers).\n  - Guardrails & compliance\n      - Respect PII constraints; use customer-level details only with clear user intent.\n      - Never infer beyond the data; label any assumptions explicitly.\n      - Keep metric definitions transparent and consistent across sessions.",
      "sample_questions": [
        {
          "question": "total loans and total principal by month for the last 12 months"
        },
        {
          "question": "active cards, average credit limit, and average APR by product"
        },
        {
          "question": "customers with both an active auto loan and an active credit card"
        },
        {
          "question": "total exposure per customer (loan principal + card balance)"
        },
        {
          "question": "customers with a missed auto payment and a returned card payment in last 90 days"
        }
      ]
    },
    "tools": [
      {
        "tool_spec": {
          "type": "cortex_analyst_text_to_sql",
          "name": "Auto_CA",
          "description": "CUSTOMERS:\n- Database: BANKING, Schema: AUTO_LOANS_DEMO\n- This table stores comprehensive customer information including personal details, contact information, and demographic data. It serves as the central customer registry with unique identifiers and creditworthiness classifications.\n- The table supports customer segmentation through credit risk categories (Prime, Near-Prime, Subprime) and tracks customer lifecycle from account creation. Geographic distribution is captured through address fields for regional analysis.\n- LIST OF COLUMNS: CUSTOMER_ID (unique customer identifier - links to CUSTOMER_ID in other tables), FIRST_NAME, LAST_NAME, EMAIL, PHONE, ADDRESS_LINE1, CITY, STATE, POSTAL_CODE, SEGMENT (credit risk classification), CREATED_AT (account creation timestamp), DOB (date of birth)\n\nCUSTOMER_ACCOUNTS:\n- Database: BANKING, Schema: AUTO_LOANS_DEMO\n- This table manages customer account information and serves as a bridge between customers and their banking relationships. Each account has a unique identifier and is associated with a specific branch location.\n- The table tracks account status and opening dates, enabling analysis of account lifecycle and branch performance. It establishes the foundational relationship for all banking products and services.\n- LIST OF COLUMNS: ACCOUNT_ID (unique account identifier - links to ACCOUNT_ID in LOANS table), CUSTOMER_ID (links to CUSTOMER_ID in CUSTOMERS table), BRANCH_ID (branch location identifier), STATUS (account status), ACCOUNT_OPEN_DATE (account opening date)\n\nLOANS:\n- Database: BANKING, Schema: AUTO_LOANS_DEMO\n- This table contains active loan information including principal amounts, interest rates, and repayment terms. It represents the core lending products offered to customers for vehicle financing.\n- The table enables analysis of loan portfolio performance, interest rate trends, and maturity schedules. It connects loan applications to actual funded loans and tracks loan lifecycle from origination to maturity.\n- LIST OF COLUMNS: LOAN_ID (unique loan identifier - links to LOAN_ID in PAYMENTS and VEHICLES tables), CUSTOMER_ID (borrower identifier), ACCOUNT_ID (associated account), APPLICATION_ID (originating application - links to APPLICATION_ID in LOAN_APPLICATIONS), PRINCIPAL (loan amount), INTEREST_RATE, TERM_MONTHS (repayment period), LOAN_STATUS, ORIGINATION_DATE, MATURITY_DATE\n\nLOAN_APPLICATIONS:\n- Database: BANKING, Schema: AUTO_LOANS_DEMO\n- This table captures all loan application submissions including requested amounts, terms, and application channels. It tracks the complete application process from submission through decision-making.\n- The table enables analysis of application conversion rates, channel effectiveness, and decision patterns. It supports understanding of customer demand and lending criteria through approval/denial tracking.\n- LIST OF COLUMNS: APPLICATION_ID (unique application identifier - links to APPLICATION_ID in LOANS table), CUSTOMER_ID (applicant identifier), AMOUNT_REQUESTED, TERM_MONTHS (requested repayment period), INTEREST_RATE_OFFERED, PRODUCT (loan type: New Auto, Used Auto, Refinance), CHANNEL (application source: Dealer, Online, Branch), STATUS (Approved, Denied, Pending), REASON_CODE (decision rationale), SUBMITTED_AT, DECISION_AT\n\nPAYMENTS:\n- Database: BANKING, Schema: AUTO_LOANS_DEMO\n- This table records all payment transactions for loans including scheduled payments, amounts due, and payment performance. It tracks both successful payments and delinquencies with detailed breakdowns of principal and interest components.\n- The table enables analysis of payment behavior, delinquency patterns, and cash flow management. It supports risk assessment through payment timing and late fee tracking.\n- LIST OF COLUMNS: PAYMENT_ID (unique payment identifier), CUSTOMER_ID (payer identifier), LOAN_ID (associated loan), AMOUNT_DUE, AMOUNT_PAID, PRINCIPAL_COMPONENT (principal portion of payment), INTEREST_COMPONENT (interest portion of payment), LATE_FEE, PAYMENT_STATUS (OnTime, Late, Missed), PAST_DUE_DAYS, PAYMENT_DATE\n\nVEHICLES:\n- Database: BANKING, Schema: AUTO_LOANS_DEMO\n- This table contains detailed vehicle information including make, model, pricing, and identification numbers for vehicles financed through loans. It captures both new and used vehicle characteristics at the time of purchase.\n- The table enables analysis of vehicle portfolio composition, pricing trends, and dealer relationships. It supports collateral management and vehicle depreciation tracking through purchase price and mileage data.\n- LIST OF COLUMNS: VEHICLE_ID (unique vehicle identifier), LOAN_ID (financing loan identifier), VIN (vehicle identification number), MAKE (manufacturer), MODEL, MODEL_YEAR, MILEAGE_AT_PURCHASE, MSRP (manufacturer suggested retail price), PURCHASE_PRICE, DEALER_ID (selling dealer identifier)\n\nREASONING:\nThis semantic view represents a comprehensive auto lending ecosystem that tracks the complete customer journey from loan application through vehicle purchase and ongoing payment management. The tables are interconnected through customer, account, loan, and application identifiers, creating a unified view of the lending process. The relationships enable analysis across multiple dimensions including customer demographics, application channels, loan performance, payment behavior, and vehicle characteristics. This integrated structure supports both operational lending decisions and strategic portfolio analysis.\n\nDESCRIPTION:\nThe AUTO_LOANS_SEMANTIC_VIEW provides a comprehensive data model for auto lending operations within the BANKING.AUTO_LOANS_DEMO schema, encompassing the complete customer lifecycle from initial loan application through vehicle financing and payment management. The model connects customer demographics and creditworthiness segments with their loan applications submitted through various channels (dealer, online, branch), tracking approval decisions and terms offered. Approved applications flow into active loans with detailed terms, which are secured by specific vehicles with comprehensive specifications and pricing information. The payment tracking system monitors ongoing loan performance including principal and interest breakdowns, payment timing, and delinquency management, enabling comprehensive portfolio analysis and risk assessment across the entire auto lending operation."
        }
      },
      {
        "tool_spec": {
          "type": "cortex_analyst_text_to_sql",
          "name": "Credit_CA",
          "description": "Credit card cortex analyst"
        }
      }
    ],
    "tool_resources": {
      "Auto_CA": {
        "execution_environment": {
          "query_timeout": 30,
          "type": "warehouse",
          "warehouse": "BI_LARGE_WH"
        },
        "semantic_view": "BANKING.AUTO_LOANS_DEMO.AUTO_LOANS_SEMANTIC_VIEW"
      },
      "Credit_CA": {
        "execution_environment": {
          "query_timeout": 30,
          "type": "warehouse",
          "warehouse": "ANALYTICS_RIA_WH"
        },
        "semantic_view": "BANKING.CREDIT.CREDIT_SEMANTIC_VIEW"
      }
    }
  }
$$;