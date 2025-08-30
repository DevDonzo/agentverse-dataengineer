# filename: batch_inscribe_pipeline.py

import argparse
import logging
import apache_beam as beam
from apache_beam.options.pipeline_options import PipelineOptions
from apache_beam.io import fileio
from apache_beam.options.pipeline_options import GoogleCloudOptions 
from google.cloud.sql.connector import Connector
from google import genai
from google.genai.types import EmbedContentConfig
import pg8000

class EmbedTextBatch(beam.DoFn):
    """Takes a batch of texts and generates embeddings using Vertex AI."""
    def __init__(self, project_id, region):
        self.project_id = project_id
        self.region = region
    def setup(self):
        self.client = genai.Client()
    def process(self, batch: list[tuple[str, str]]):
        if not batch: return
        filenames = [item[0] for item in batch]
        contents = [item[1] for item in batch]
        try:
            # 1. Generate the embedding for the monster's name
            result = self.client.models.embed_content(
                model="text-embedding-005",
                contents=contents,
                config=EmbedContentConfig(
                    task_type="RETRIEVAL_DOCUMENT",  
                    output_dimensionality=768, 
                )
            )
            
           
            for filename, content, embedding_object in zip(filenames, contents, result.embeddings):
                if content.strip():
                    yield (content.strip(), embedding_object.values)
        except Exception as e:
            logging.error(f"Could not process batch for files {filenames}: {e}")
            for filename, content in zip(filenames, contents):
                yield beam.pvalue.TaggedOutput('failed', (filename, str(e)))

class WriteEssenceToSpellbook(beam.DoFn):
    """Writes a scroll's content and its vector essence to Cloud SQL."""
    # CHANGED: The __init__ method now accepts a password directly
    def __init__(self, project_id, region, instance_name, db_name, db_password):
        self.project_id = project_id
        self.region = region
        self.instance_name = instance_name
        self.db_name = db_name
        self.db_password = db_password 

    def setup(self):
        
        self.connector = Connector()
        self.conn = self.connector.connect(
            f"{self.project_id}:{self.region}:{self.instance_name}", "pg8000",
            user="postgres",
            password=self.db_password,
            db=self.db_name
        )
        self.cursor = self.conn.cursor()

    def process(self, element: tuple[str, list[float]]):
        scroll_text, vector = element
        try:
            vector_string = str(vector)
            self.cursor.execute(
                "INSERT INTO ancient_scrolls (scroll_content, embedding) VALUES (%s, %s)",
                (scroll_text, vector_string))
            self.conn.commit()
        except Exception as e:
            logging.error(f"Failed to write scroll to spellbook: {e}. Rolling back.")
            self.conn.rollback() 

    def teardown(self):
        
        self.conn.close()
        self.connector.close()

def run(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--input_pattern", required=True, help="GCS path for input files")
    parser.add_argument("--instance_name", required=True, help="Cloud SQL instance connection name")
    parser.add_argument("--db_name", default="arcane_wisdom", help="PostgreSQL database name")
    # ADDED: Argument for the password, with the requested default
    parser.add_argument("--db_password", default="1234qwer", help="PostgreSQL password")

    known_args, pipeline_args = parser.parse_known_args(argv)
    pipeline_options = PipelineOptions(pipeline_args, save_main_session=True)
    
    project = pipeline_options.view_as(GoogleCloudOptions).project
    region = pipeline_options.view_as(GoogleCloudOptions).region

    with beam.Pipeline(options=pipeline_options) as pipeline:
        files = (
            pipeline
            | "MatchFiles" >> fileio.MatchFiles(known_args.input_pattern)
            | "ReadMatches" >> fileio.ReadMatches()
            | "ExtractContent" >> beam.Map(lambda f: (f.metadata.path, f.read_utf8()))
        )

        embeddings = (
            files
            | "BatchScrolls" >> beam.BatchElements(min_batch_size=1, max_batch_size=2)
            | "DistillBatch" >> beam.ParDo(
                  EmbedTextBatch(project_id=project, region=region)
              ).with_outputs('failed', main='processed')
        )

        _ = (
            embeddings.processed
            | "WriteToSpellbook" >> beam.ParDo(
                  WriteEssenceToSpellbook(
                      project_id=project,
                      region = "us-central1",
                      instance_name=known_args.instance_name,
                      db_name=known_args.db_name,
                      db_password=known_args.db_password
                  )
              )
        )
        
        _ = (
            embeddings.failed
            | "LogFailures" >> beam.Map(lambda e: logging.error(f"Embedding failed for file {e[0]}: {e[1]}"))
        )

if __name__ == '__main__':
    logging.getLogger().setLevel(logging.INFO)
    run()