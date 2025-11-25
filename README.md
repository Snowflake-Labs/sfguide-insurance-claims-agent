## 🛡️ Insurance Claims Agent Demo

This repository showcases a powerful insurance claims agent built using **Snowflake Cortex** services. 

It processes claims data, handles both structured and unstructured information, and allows users to gain insights through natural language.

### ✨ Key Features & Technology

This demo leverages the following Snowflake tools to deliver an intelligent claims processing solution:

* **Snowflake Cortex Analyst (using Semantic Views), Cortex Search, AISQL, and Agents:** Used for sophisticated data analysis and query generation.
* **Snowflake Intelligence:** Serves as the UI which enables users to ask complex questions about claims.
* **Multimodal Analysis:** Describes and compares claims images with the claim description to verify if **supporting evidence aligns with the reported incident**.
* **Audio Transcription:** Transcribes text from an audio or video file with optional timestamps and speaker labels.

### 🔗 Data Integration

A core capability is the ability to join **unstructured** and **structured** data, providing a complete view of each claim.

* **Structured Data:** Claims, financial transactions, and authorization records.
* **Unstructured Data:** Claim file notes, state insurance guidelines, invoices, claim photo eveidens, and audio call files.

---

<img width="1069" height="748" alt="Screenshot 2025-11-05 at 2 40 51 PM" src="https://github.com/user-attachments/assets/e92c1fb4-fe6e-42df-8cdc-96c582ad8c50" />

## 🛠️ Setup Instructions

Follow these steps to set up the environment and run the demo.

### Step 1: Initialize Database Objects

1.  Run the `setup.sql` file. This script creates the necessary database objects:
    * **Database:** `ins_co`
    * **Schema:** `loss_claims`
    * **Stage:** `loss_evidence`
    * **Tables:**
        * `Claims`
        * `Claim Lines`
        * `Financial Transactions`
        * `Authorization`
        * `Parsed_invoices`
        * `Parsed_guidelines`
        * `Parsed_claim_notes`
        * `GUIDELINES_CHUNK_TABLE`
        * `NOTES_CHUNK_TABLE`

### Step 2: Upload Evidence Files

1.  Upload the following files to the **`loss_evidence`** stage:
    * `1899_claim_evidence1.jpeg`
    * `1899_claim_evidence2.jpeg`
    * `Claim_Notes.pdf`
    * `Guidelines.pdf`
    * `invoice.png`
    * `Gemini_generated_3.jpeg`
    * `ins_co_1899_call.wav`

### Step 3: Configure Cortex Analyst

1.  The setup script automatically creates a **`Models`** stage.
2.  Upload the following `.sql` file to create a semantic view:
    * `CA_INS_CO`
3.  **Create a Cortex Analyst** using the uploaded `.sql` configuration file.

### Step 4: Deploy the Interface

Choose one of the following methods for deploying the user interface:

#### Option A: Streamlit in Snowflake

1.  Create a new **Streamlit application** within the `ins_co` database and `loss_claims` schema.
2.  Paste the contents of the **`streamlit.py`** file into the Streamlit in Snowflake (SIS) editor.

#### Option B: Snowflake Intelligence Agent

1.  Create an **Agent** and use it directly within Snowflake Intelligence.
2.  Run **Custom_tools.sql**.
3.  Run the **Tools config**.
4.  Run the **Agents config**.


### Sample Questions this demo helps answer:

1.  Payment Processing Time: What percentage of payments were issued to the vendor within the following timeframes after invoice receipt?

    * 3–5 calendar days

    * 8–13 calendar days

    * 14–29 calendar days

    * 30+ calendar days

2.  Reserve Rationale Presence: Was a reserve rationale documented in the claim file notes?

3.  Reserve Rationale Sufficiency: Did the reserve rationale adequately explain the reserve figure(s) set?

4.  Reserve Extension Timeliness: Was the reserve extension requested in a timely manner?

5.  Payment Over Reserve: Was a payment issued in excess of the current reserve amount on an open claim?

6.  Authority Violation (Reserves/Payments): Were the reserving or payment amounts in excess of the examiner's authority?

7.  Authority Compliance: When the claim exceeded the examiner's authority, were all elements of authority properly handled?

8.  Payment Compliance: Was the payment made according to the state guidelines?

9.  Settlement Timeliness: According to the state guidelines, was the claim settled within the required timelines?

10.  Al driven summary of the image

11.  Invoice data extraction and validating with the payments made

12.  Confirm that the images shown here align with the claim made

🎯 ### Who Should Care? (Target Audience)

| Role/Department | Value Proposition |
| :--- | :--- |
| **Claims Adjusters/Examiners** | **Faster, More Accurate Decisions.** The agent instantly synthesizes information from all sources (structured data, notes, images, guidelines), providing a fast, data-driven assessment. The image comparison feature is valuable for fraud detection and evidence verification. |
| **Claims Managers / VPs of Claims** | **Operational Efficiency and Consistency.** Demonstrates how to reduce the claim cycle time, ensure consistent application of company/state guidelines (by querying the `Parsed_guidelines` table), and handle higher claim volumes without proportional staff increases. |
| **Special Investigations Unit (SIU) / Anti-Fraud** | **Advanced Fraud Detection.** The system's ability to join structured data with unstructured files (like call transcripts for tone analysis) and compare image evidence against claim descriptions is a powerful tool for flagging suspicious or inconsistent claims. |
| **IT & Data Science / Data Engineering** | **Leveraging Modern Data Architecture.** This demo validates the use case for **Snowflake Cortex** and demonstrates that the data platform can handle unstructured data (PDFs, images, audio) alongside core transactional data, increasing the value of their data investment. |
| **Compliance & Legal Teams** | **Auditability and Compliance.** By combining structured data with parsed state guidelines, the system helps ensure claims decisions are compliant with regulations, providing a clear, auditable trail for every decision. |
| **Chief Operating Officer (COO)** | **Cost Reduction and Customer Experience.** Automating document ingestion and accelerating the decision process directly reduces operational costs and leads to faster, more positive interactions for policyholders. |