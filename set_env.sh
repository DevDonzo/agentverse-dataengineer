#!/bin/bash

# This script sets various Google Cloud related environment variables.
# It must be SOURCED to make the variables available in your current shell.
# Example: source ./set_env.sh

# --- Configuration ---
# Set your base configuration here
PROJECT_FILE="~/project_id.txt"
GOOGLE_CLOUD_LOCATION="us-central1"
REPO_NAME="agentverse-repo"
INSTANCE_NAME="grimoire-spellbook"
DB_USER="postgres"
DB_PASSWORD="1234qwer" # Consider using a more secure method for passwords
DB_NAME="arcane_wisdom"
AGENT_NAME="scholar"
# ---------------------


echo "--- Setting Google Cloud Environment Variables ---"

# --- Authentication Check ---
echo "Checking gcloud authentication status..."
# Run a command that requires authentication. Redirect output so it's clean.
if gcloud auth print-access-token > /dev/null 2>&1; then
  echo "gcloud is authenticated."
else
  echo "Error: gcloud is not authenticated."
  echo "Please log in by running: gcloud auth login"
  # Use 'return' instead of 'exit' because the script is meant to be sourced.
  return 1
fi
# --- --- --- --- --- ---


# 1. Check if project file exists and set Project ID
PROJECT_FILE_PATH=$(eval echo $PROJECT_FILE) # Expand potential ~
if [ ! -f "$PROJECT_FILE_PATH" ]; then
  echo "Error: Project file not found at $PROJECT_FILE_PATH"
  echo "Please create $PROJECT_FILE_PATH containing your Google Cloud project ID."
  return 1
fi
PROJECT_ID_FROM_FILE=$(cat "$PROJECT_FILE_PATH")
echo "Setting gcloud config project to: $PROJECT_ID_FROM_FILE"
gcloud config set project "$PROJECT_ID_FROM_FILE" --quiet

# --- Export Core GCP Identifiers ---
export PROJECT_ID=$(gcloud config get project)
export GOOGLE_CLOUD_PROJECT="$PROJECT_ID" # Often used by client libraries
export PROJECT_NUMBER=$(gcloud projects describe ${PROJECT_ID} --format="value(projectNumber)")
export SERVICE_ACCOUNT_NAME=$(gcloud compute project-info describe --format="value(defaultServiceAccount)")

echo "Exported PROJECT_ID=$PROJECT_ID"
echo "Exported PROJECT_NUMBER=$PROJECT_NUMBER"
echo "Exported SERVICE_ACCOUNT_NAME=$SERVICE_ACCOUNT_NAME"
echo "Exported GOOGLE_CLOUD_PROJECT=$GOOGLE_CLOUD_PROJECT"

# --- Export Location and Region ---
export GOOGLE_CLOUD_LOCATION="$GOOGLE_CLOUD_LOCATION"
export REGION="$GOOGLE_CLOUD_LOCATION" # Use the same value for REGION
echo "Exported GOOGLE_CLOUD_LOCATION=$GOOGLE_CLOUD_LOCATION"
echo "Exported REGION=$REGION"

# --- Export Application-Specific Variables ---

# Cloud Storage
export BUCKET_NAME="${PROJECT_ID}-reports"
echo "Exported BUCKET_NAME=$BUCKET_NAME"

# Dataflow
export DF_JOB_NAME="grimoire-initial-scribing-$(date +%Y%m%d-%H%M%S)"
echo "Exported DF_JOB_NAME=$DF_JOB_NAME"

# Vertex AI / GenAI
export GOOGLE_GENAI_USE_VERTEXAI="TRUE"
echo "Exported GOOGLE_GENAI_USE_VERTEXAI=$GOOGLE_GENAI_USE_VERTEXAI"

# Cloud SQL / Database
export INSTANCE_NAME="$INSTANCE_NAME"
export DB_USER="$DB_USER"
export DB_PASSWORD="$DB_PASSWORD"
export DB_NAME="$DB_NAME"
echo "Exported INSTANCE_NAME=$INSTANCE_NAME"
echo "Exported DB_USER=$DB_USER"
echo "Exported DB_NAME=$DB_NAME"


# Artifact Registry & Cloud Run
export REPO_NAME="$REPO_NAME"
# export IMAGE_NAME="grimoire-inscriber" # This was the first value, now unused.
export IMAGE_NAME="scholar-agent" # This is the second, active value.
export AGENT_NAME="$AGENT_NAME"
export IMAGE_TAG="latest"
export IMAGE_PATH="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/${IMAGE_NAME}:${IMAGE_TAG}"
export SERVICE_NAME="scholar-agent"
export PUBLIC_URL="https://scholar-agent-${PROJECT_NUMBER}.${REGION}.run.app"

echo "Exported REPO_NAME=$REPO_NAME"
echo "Exported IMAGE_NAME=$IMAGE_NAME"
echo "Exported AGENT_NAME=$AGENT_NAME"
echo "Exported IMAGE_PATH=$IMAGE_PATH"
echo "Exported SERVICE_NAME=$SERVICE_NAME"
echo "Exported PUBLIC_URL=$PUBLIC_URL"


echo ""
echo "--- Environment setup complete ---"