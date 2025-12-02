"""
Cortex Analyst App for Insurance Claim Audits
==============================================
This Streamlit application allows users to audit insurance claims using
natural language queries powered by Snowflake Cortex Analyst. It features
claim detail retrieval, an integrated AI-powered Q&A chat, and image
analysis from a Snowflake stage, all within a streamlined interface.
"""

# --- Imports ---
import streamlit as st
import pandas as pd
import json
import os
from typing import Dict, List, Optional, Tuple

# Snowflake-specific imports
import _snowflake  # Required for Snow API requests and file URLs in Streamlit in Snowflake
from snowflake.snowpark.context import get_active_session
from snowflake.snowpark.exceptions import SnowparkSQLException

import tempfile
import os


# --- App Configuration ---
st.set_page_config(layout="wide", page_title="Insurance Claim Audit POC")

# Constants for Cortex Analyst API
API_ENDPOINT = "/api/v2/cortex/analyst/message"
API_TIMEOUT = 60000  # in milliseconds

# Configuration for Snowflake objects
AVAILABLE_SEMANTIC_MODELS_PATHS = [
    "INSURANCE_CLAIMS_DEMO.LOSS_CLAIMS.LOSS_EVIDENCE/loss_claims.yaml"
]
CLAIMS_TABLE_NAME = "INSURANCE_CLAIMS_DEMO.LOSS_CLAIMS.CLAIMS"
CLAIM_LINES_TABLE_NAME = "INSURANCE_CLAIMS_DEMO.LOSS_CLAIMS.CLAIM_LINES"
CLAIM_NOTES_TABLE_NAME = "INSURANCE_CLAIMS_DEMO.LOSS_CLAIMS.PARSED_CLAIM_NOTES" 
CLAIM_IMAGES_STAGE_NAME = "INSURANCE_CLAIMS_DEMO.LOSS_CLAIMS.LOSS_EVIDENCE"


# --- Snowflake Session Initialization ---
try:
    session = get_active_session()
except Exception as e:
    st.error(f"Could not get active Snowpark session: {e}")
    st.stop()


# --- Data Retrieval Functions ---
@st.cache_data(ttl=3600)
def get_claim_numbers() -> List[str]:
    """Fetches distinct claim numbers from the Snowflake CLAIMS table."""
    try:
        # Update the column name from "CLAIM_NO" to "CLAIM_NO"
        df = session.table(CLAIMS_TABLE_NAME).select("CLAIM_NO").distinct().to_pandas()
        return sorted(df["CLAIM_NO"].tolist())
    except Exception as e:
        st.error(f"Error fetching claim numbers: {e}")
        return []

@st.cache_data(ttl=3600)
def get_claim_details(claim_number: str) -> Dict:
    """Fetches comprehensive details for a given claim number."""
    details = {"claim_details": "Error fetching details.", "audit_questions": [], "loss_description": None}
    try:
        # Fetch main claim details using the new table name and column.
        claims_df = session.table(CLAIMS_TABLE_NAME).filter(f"CLAIM_NO = '{claim_number}'").to_pandas()
        if claims_df.empty:
            details["claim_details"] = "No main claim details found."
            return details

        claim_info = claims_df.iloc[0]
        
        details["loss_description"] = claim_info.get('LOSS_DESCRIPTION', 'N/A')

        details_text = (
            f"**Claim Number:** {claim_info.get('CLAIM_NO', 'N/A')}\n"
            f"**Line of Business:** {claim_info.get('LINE_OF_BUSINESS', 'N/A')}\n"
            f"**Claim Status:** {claim_info.get('CLAIM_STATUS', 'N/A')}\n"
            f"**Cause of Loss:** {claim_info.get('CAUSE_OF_LOSS', 'N/A')}\n"
            f"**Loss Description:** {claim_info.get('LOSS_DESCRIPTION', 'N/A')}\n\n"
        )
        
        # Fetch parsed claim notes using the new table and column.
        notes_df = session.table(CLAIM_NOTES_TABLE_NAME).filter(f"CLAIM_NO = '{claim_number}'").to_pandas()
        if not notes_df.empty:
            details_text += "**Claim Notes:**\n"
            for _, row in notes_df.iterrows():
                details_text += f"- Content: {row.get('EXTRACTED_CONTENT', 'N/A')}\n"
        else:
            details_text += "No parsed claim notes found.\n"
        
        details["claim_details"] = details_text
        
        details["audit_questions"] = [
            f"For claim {claim_number}, was a payment issued to the vendor 3-5 calendar days after the invoice was received? If yes, please provide details.",
            f"For claim {claim_number}, was a payment issued to the vendor 8-13 calendar days after the invoice was received? If yes, please provide details.",
            f"For claim {claim_number}, was a payment issued to the vendor 14-29 calendar days after the invoice was received? If yes, please provide details.",
            f"For claim {claim_number}, was a payment issued to the vendor 30+ calendar days after the invoice was received? If yes, please provide details.",
            f"For claim {claim_number}, did the total payment amount for that claim exceed the total reserved amount for that claim? Please respond yes or no and provide more details if yes",
            f"For claim {claim_number}, was a payment made in excess of the performer authority? Please respond yes or no and provide more details if yes."
        ]
        return details
    except Exception as e:
        st.error(f"Error fetching claim details: {e}")
        return details

@st.cache_data(ttl=3600)
def list_images_in_stage(stage_name: str) -> List[str]:
    """Lists image files in a specified Snowflake stage."""
    try:
        df = session.sql(f"LS @{stage_name}").to_pandas()
        if '"name"' in df.columns:
            full_paths = df['"name"'].tolist()
            return sorted([path.split('/')[-1] for path in full_paths])
        else:
            st.warning(f"Could not find 'name' column in stage listing for @{stage_name}.")
            return []
    except Exception as e:
        st.error(f"Error listing images in stage @{stage_name}: {e}")
        return []

@st.cache_data(show_spinner=False)
def get_query_exec_result(query: str) -> Tuple[Optional[pd.DataFrame], Optional[str]]:
    """Executes a SQL query and returns a DataFrame or an error message."""
    try:
        df = session.sql(query).to_pandas()
        return df, None
    except SnowparkSQLException as e:
        return None, str(e)


# --- Cortex API & Chat Logic Functions ---
def get_analyst_response(messages: List[Dict]) -> Tuple[Optional[Dict], Optional[str]]:
    """Sends chat history to the Cortex Analyst API and returns the response."""
    request_body = {
        "messages": messages,
        "semantic_model_file": f"@{st.session_state.selected_semantic_model_path}",
    }
    try:
        with st.spinner("Waiting for Analyst's response..."):
            resp = _snowflake.send_snow_api_request(
                "POST",           # method
                API_ENDPOINT,     # path
                {},               # headers
                {},               # params
                request_body,     # body
                None,             # request_guid
                API_TIMEOUT       # timeout
            )
        parsed_content = json.loads(resp["content"])
        if resp["status"] < 400:
            return parsed_content, None
        else:
            error_msg = f"API Error (Code: {resp['status']}): {parsed_content.get('message', 'Unknown error')}"
            return parsed_content, error_msg
    except Exception as e:
        return None, f"An unexpected error occurred during the API call: {e}"

@st.cache_data(ttl=3600)
def get_image_from_stage(stage_name: str, file_name: str) -> Optional[bytes]:
    """
    Downloads an image file from a Snowflake stage to a temporary local directory,
    reads it into memory, and returns its bytes.
    """
    try:
        with tempfile.TemporaryDirectory() as temp_dir:
            session.file.get(f"@{stage_name}/{file_name}", temp_dir)
            local_file_path = os.path.join(temp_dir, file_name)
            with open(local_file_path, "rb") as f:
                image_bytes = f.read()
            return image_bytes
    except Exception as e:
        st.error(f"Error fetching image '{file_name}' from stage @{stage_name}: {e}")
        return None
        
def process_user_input(prompt: str):
    """Adds a user prompt to the chat history and triggers a rerun."""
    if not prompt:
        return
    st.session_state.messages.append({"role": "user", "content": [{"type": "text", "text": prompt}]})
    st.rerun()

def get_and_process_analyst_response():
    """Fetches the analyst response for the last user message and updates the state."""
    response, error_msg = get_analyst_response(st.session_state.messages)
    if error_msg:
        analyst_message = {"role": "analyst", "content": [{"type": "text", "text": f"🚨 {error_msg}"}]}
    elif response and "message" in response and "content" in response["message"]:
        analyst_message = {"role": "analyst", "content": response["message"]["content"]}
    else:
        analyst_message = {"role": "analyst", "content": [{"type": "text", "text": "Sorry, I received an empty response."}]}
    st.session_state.messages.append(analyst_message)

def get_image_summary(image_file: str, stage: str) -> str:
    """Uses Snowflake Cortex to generate a summary for an image in a stage."""
    prompt = "Summarize the key insights from the attached image in 100 words."
    sql_query = f"""
    SELECT SNOWFLAKE.CORTEX.COMPLETE('claude-3-5-sonnet',
        '{prompt}',
        TO_FILE('@{stage}/{image_file}'));
    """
    try:
        with st.spinner(f"AI is analyzing {image_file}..."):
            result_df = session.sql(sql_query).to_pandas()
            if not result_df.empty and result_df.iloc[0, 0]:
                return result_df.iloc[0, 0]
            else:
                return "No summary could be generated."
    except Exception as e:
        st.error(f"Error generating image summary: {e}")
        st.info("This error can occur if the Cortex function is not enabled, the model name is incorrect, or the stage path is invalid.")
        return "An error occurred during summary generation."

def get_similarity_score(text1: str, text2: str) -> Optional[float]:
    """Calculates the AI_SIMILARITY score between two text inputs."""
    # The AI_SIMILARITY function is called directly with the input strings.
    sql_query = f"""
    SELECT SNOWFLAKE.CORTEX.AI_SIMILARITY(
        '{text1.replace("'", "''")}',
        '{text2.replace("'", "''")}'
    );
    """
    try:
        with st.spinner("Calculating similarity score..."):
            result_df = session.sql(sql_query).to_pandas()
            if not result_df.empty and result_df.iloc[0, 0]:
                return result_df.iloc[0, 0]
            else:
                return None
    except Exception as e:
        st.error(f"Error calculating similarity score: {e}")
        return None

# --- UI Display Functions ---
def display_sql_query(sql: str):
    """Displays an expander with the SQL query and the results in a table and chart."""
    with st.expander("Show SQL Query", expanded=False):
        st.code(sql, language="sql")

    with st.expander("Show Results", expanded=True):
        df, err_msg = get_query_exec_result(sql)
        if err_msg:
            st.error(f"Could not execute query: {err_msg}")
            return
        if df.empty:
            st.info("Query returned no data.")
            return

        data_tab, chart_tab = st.tabs(["Data 📄", "Chart 📈"])
        with data_tab:
            st.dataframe(df, use_container_width=True)
        with chart_tab:
            st.line_chart(df)

def display_message(message: Dict, index: int):
    """Displays a single chat message, handling text, suggestions, and SQL."""
    for item in message["content"]:
        if item["type"] == "text":
            st.markdown(item["text"])
        elif item["type"] == "suggestions":
            for i, suggestion in enumerate(item["suggestions"]):
                if st.button(suggestion, key=f"suggestion_{index}_{i}"):
                    process_user_input(suggestion)
        elif item["type"] == "sql":
            display_sql_query(item["statement"])

def display_conversation():
    """Renders the entire conversation history."""
    for i, message in enumerate(st.session_state.messages):
        with st.chat_message(message["role"]):
            display_message(message, i)


# --- Main Application ---

# 1. Initialize Session State
if "messages" not in st.session_state:
    st.session_state.messages = []
if "selected_claim" not in st.session_state:
    st.session_state.selected_claim = ""
if "selected_semantic_model_path" not in st.session_state:
    st.session_state.selected_semantic_model_path = AVAILABLE_SEMANTIC_MODELS_PATHS[0]

# 2. Define callback to reset chat when claim selection changes
def on_claim_change():
    """Resets the chat message history when a new claim is selected."""
    st.session_state.messages = []

# 3. Check if the last message was from the user, if so, get the analyst response
if st.session_state.messages and st.session_state.messages[-1]["role"] == "user":
    get_and_process_analyst_response()

# 4. Render UI
st.title("Insurance Claim Audit POC 🕵️")

tab1, tab2 = st.tabs(["Claims Audit & Chat", "Image Audit"])

with tab1:
    st.header("Claims Audit")

    with st.expander("How Text is Processed and Queried ⚙️"):
        st.markdown("""
        This application uses two key Cortex features to work with unstructured text data like claim notes or compliance documents.
        """)
        st.subheader("1. Document Intelligence: `PARSE_DOCUMENT`")
        st.markdown("""
        **Goal:** Extract text from unstructured documents, like scanned PDFs of claim notes, for analysis.

        **How it Works:** The `SNOWFLAKE.CORTEX.PARSE_DOCUMENT` function uses Optical Character Recognition (OCR) to read text from files stored in a Snowflake stage. This converts images of text into actual text data that can be stored and queried.
        """)
        st.code("""
-- This AISQL command reads a PDF from a stage and extracts its text content.
SELECT TO_VARCHAR(
    SNOWFLAKE.CORTEX.PARSE_DOCUMENT(
        '@C_CHUBB.loss_claims.loss_evidence', -- Stage Name
        'Claim_Notes.pdf',                   -- File Name
        {'mode': 'OCR'})                     -- OCR Mode
    ) AS ocr_text;
        """, language="sql")
        
        st.subheader("2. Unstructured Text Search: `Cortex Search Service`")
        st.markdown("""
        **Goal:** Perform fast, semantic searches across large volumes of text, such as all claim notes or state compliance guidelines.

        **How it Works:** While Cortex Analyst is for structured data, Cortex Search is for unstructured text. You would first create a Search Service on a table column containing text (e.g., from `PARSE_DOCUMENT`). Then, you can ask questions, and the service will find the most relevant text snippets from thousands of documents.
        """)
        st.code("""
-- Step 1: Create a search service on a text column
CREATE SNOWFLAKE.CORTEX.SEARCH_SERVICE claim_notes_search
    ON (notes_table.note_content);

-- Step 2: Query the service to find relevant information
SELECT SNOWFLAKE.CORTEX.SEARCH(
    'claim_notes_search',                       -- Service Name
    'Find notes related to water damage'        -- User Query
);
        """, language="sql")

    claim_numbers = get_claim_numbers()
    
    selected_claim = st.selectbox(
        "Select a Claim Number:", 
        options=[""] + claim_numbers, 
        key="selected_claim",
        on_change=on_claim_change
    )

    if selected_claim:
        # --- Claim Details and Predefined Questions ---
        data = get_claim_details(selected_claim)
        st.text_area("Claim Details Summary", data["claim_details"], height=250, disabled=True)
        st.markdown("---")
        
        col1, col2 = st.columns([3, 1])
        with col1:
             st.selectbox(
                "Select a predefined question to ask the Audit Agent:",
                options=data["audit_questions"],
                key="selected_question_text"
            )
        with col2:
            st.markdown("<br>", unsafe_allow_html=True) # Align button vertically
            if st.button("Ask Predefined Question", use_container_width=True):
                process_user_input(st.session_state.selected_question_text)
        
        st.markdown("---")

        # --- Integrated Chat Interface ---
        st.subheader("Audit Chat")
        with st.expander("How this Chat Works: Cortex Analyst ⚙️"):
            st.markdown("""
            **Goal:** Allow users to ask questions about structured data in plain English, without writing SQL.

            **How it Works:** This chat is powered by Cortex Analyst. It uses a **Semantic Model** (a YAML file) that describes the database tables, columns, and their relationships. When you ask a question, Analyst:
            1.  Understands your intent.
            2.  Consults the semantic model to find the relevant data.
            3.  Generates a complex SQL query automatically.
            4.  Executes the query and returns the answer in a human-readable format.
            This eliminates the need for users to be SQL experts.
            """)
        display_conversation()

        if prompt := st.chat_input("Ask a follow-up question..."):
            process_user_input(prompt)
    else:
        st.info("Please select a claim number to begin the audit.")


with tab2:
    st.header("Image Audit")

    with st.expander("How Image Audits Work: Multimodal `COMPLETE` ⚙️"):
        st.markdown("""
        **Goal:** Understand the content of images, such as photos of property damage, and generate a text summary.

        **How it Works:** The `SNOWFLAKE.CORTEX.COMPLETE` function can analyze both text and images. By providing a prompt and a file from a stage, we can ask a large language model (LLM) to describe what it 'sees' in the image.
        """)
        st.code("""
-- This command asks a multimodal model to summarize an image file.
SELECT SNOWFLAKE.CORTEX.COMPLETE(
    'claude-3-sonnet',                               -- Model Name
    'Summarize the key insights from this image...', -- User Prompt
    TO_FILE('@CLAIM_IMAGES/damage_photo.jpg')        -- Image File from Stage
);
        """, language="sql")

    image_files = list_images_in_stage(CLAIM_IMAGES_STAGE_NAME)
    
    if not image_files:
        st.warning(f"No image files found in stage @{CLAIM_IMAGES_STAGE_NAME}.")
    else:
        selected_image = st.selectbox("Select an Image File:", options=[""] + image_files)
        
        if selected_image and st.session_state.selected_claim:
            # Display the selected image from the stage
            image_bytes = get_image_from_stage(CLAIM_IMAGES_STAGE_NAME, selected_image)
            if image_bytes:
                st.image(
                    image_bytes,
                    caption=f"Displaying: {selected_image}",
                    use_container_width=True
                )
            
            # Button to generate the summary for the displayed image
            if st.button("Generate Image Summary & Similarity"):
                # Get the image summary
                image_summary = get_image_summary(selected_image, CLAIM_IMAGES_STAGE_NAME)
                
                # Get the loss description from the main claim details
                claim_details = get_claim_details(st.session_state.selected_claim)
                claim_description = claim_details.get("loss_description")

                # Display the summary and description for comparison
                st.subheader("AI-Generated Image Summary:")
                st.write(image_summary)

                st.subheader("Claim Description:")
                st.write(claim_description)
                
                # Calculate and display the similarity score
                if claim_description and image_summary:
                    similarity_score = get_similarity_score(claim_description, image_summary)
                    if similarity_score is not None:
                        st.subheader("Similarity Score:")
                        st.metric(
                            label="Image Summary vs. Claim Description",
                            value=f"{similarity_score:.2f}",
                            help="A score of 1.0 indicates a perfect semantic match."
                        )
                else:
                    st.info("Both an image summary and a claim description are needed to calculate a similarity score.")
        elif selected_image and not st.session_state.selected_claim:
            st.info("Please select a claim from the 'Claims Audit & Chat' tab to compare against the image.")