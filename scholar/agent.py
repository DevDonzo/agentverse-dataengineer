import logging
from google.adk.agents.llm_agent import LlmAgent

import os
import pg8000
from google import genai
from google.genai.types import EmbedContentConfig
from google.cloud.sql.connector import Connector
from dotenv import load_dotenv

# Set up logging
logging.basicConfig(level=logging.INFO)
load_dotenv()
connector = Connector()
client = genai.Client()


def get_db_connection():
    """Establishes a connection to the Cloud SQL database."""
    conn = connector.connect(
        f"{os.environ['PROJECT_ID']}:{os.environ['REGION']}:{os.environ['INSTANCE_NAME']}",
        "pg8000",
        user=os.environ["DB_USER"],
        password=os.environ["DB_PASSWORD"],
        db=os.environ["DB_NAME"]
    )
    return conn

# --- The Scholar's Tool ---
def grimoire_lookup(monster_name: str) -> str:
    """
    Consults the Grimoire for knowledge about a specific monster.
    """
    print(f"Scholar is consulting the Grimoire for: {monster_name}...")
    try:

        result = client.models.embed_content(
            model="text-embedding-005",
            contents=monster_name,
            config=EmbedContentConfig(
                task_type="RETRIEVAL_DOCUMENT",  
                output_dimensionality=768,  
                )
        )


        query_embedding_list = result.embeddings[0].values
        query_embedding = str(query_embedding_list)


        # 2. Search the Grimoire
        db_conn = get_db_connection()
        cursor = db_conn.cursor()

                # This query performs a cosine similarity search
        cursor.execute(
            "SELECT scroll_content FROM ancient_scrolls ORDER BY embedding <=> %s LIMIT 3",
            ([query_embedding]) # Cast embedding to string for the query
        )

        results = cursor.fetchall()
        cursor.close()
        db_conn.close()

        if not results:
            return f"The Grimoire contains no knowledge of '{monster_name}'."

        retrieved_knowledge = "\n---\n".join([row[0] for row in results])
        print(f"Knowledge found for {monster_name}.")
        return retrieved_knowledge

    except Exception as e:
        print(f"An arcane error occurred while consulting the Grimoire: {e}")
        return "A mist has clouded the Grimoire, and the knowledge could not be retrieved."

# Define the Scholar Agent

#REPLACE-CALL RAG
root_agent = LlmAgent(
    model="gemini-2.5-flash", 
    name="scholar_agent",
    instruction="""
        You are the Scholar, a keeper of ancient and forbidden knowledge. Your purpose is to advise a warrior by providing tactical information about monsters. Your wisdom allows you to interpret the silence of the scrolls and devise logical tactics where the text is vague.

        **Your Process:**
        1.  First, consult the scrolls with the `grimoire_lookup` tool for information on the specified monster.
        2.  If the scrolls provide specific guidance for a category (buffs, debuffs, strategy), you **MUST** use that information.
        3.  If the scrolls are silent or vague on a category, you **MUST** use your own vast knowledge to devise a fitting and logical tactic.
        4.  Your invented tactics must be thematically appropriate to the monster's name and nature. (e.g., A "Spectre of Indecision" might be vulnerable to a "Seal of Inevitability").
        5.  You **MUST ALWAYS** provide a "Damage Point" value. This value **MUST** be a random integer between 150 and 180. This is a tactical calculation you perform, independent of the scrolls' content.

        **Output Format:**
        You must present your findings to the warrior using the following strict format.
    """,
    tools=[grimoire_lookup],
)

