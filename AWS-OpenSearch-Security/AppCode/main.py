from fastapi import FastAPI, HTTPException
from opensearchpy import OpenSearch, RequestsHttpConnection
from requests_aws4auth import AWS4Auth
import boto3
import os
import asyncio
from datetime import datetime
import uvicorn

# -------------------------
# FastAPI app
# -------------------------
app = FastAPI(title="OpenSearch API Service")

# -------------------------
# Environment Variable
# -------------------------
OPENSEARCH_ENDPOINT = os.getenv("OPENSEARCH_ENDPOINT")
if not OPENSEARCH_ENDPOINT:
    raise RuntimeError("OPENSEARCH_ENDPOINT environment variable is required")

# -------------------------
# AWS Credentials (ECS Task Role)
# -------------------------
session = boto3.Session()
credentials = session.get_credentials()
region = "ap-south-1"

awsauth = AWS4Auth(
    credentials.access_key,
    credentials.secret_key,
    region,
    "es",
    session_token=credentials.token
)

# -------------------------
# OpenSearch Client
# -------------------------
client = OpenSearch(
    hosts=[{"host": OPENSEARCH_ENDPOINT, "port": 443}],
    http_auth=awsauth,
    use_ssl=True,
    verify_certs=True,
    connection_class=RequestsHttpConnection,
    timeout=30
)

# -------------------------
# Background Health Monitor
# -------------------------
async def check_opensearch_health_periodically():
    while True:
        try:
            health = client.cluster.health()
            status = health.get("status", "unknown")
            print(f"[{datetime.utcnow().isoformat()}] OpenSearch Health: {status.upper()}")
        except Exception as e:
            print(f"[{datetime.utcnow().isoformat()}] OpenSearch Health FAILED: {str(e)}")
        await asyncio.sleep(60)

# -------------------------
# Startup Event
# -------------------------
@app.on_event("startup")
async def startup_event():
    asyncio.create_task(check_opensearch_health_periodically())
    print("FastAPI started – OpenSearch health monitoring active")

# -------------------------
# APIs
# -------------------------
@app.get("/")
def read_root():
    return {"message": "FastAPI service connected to OpenSearch via IAM role"}

@app.get("/health")
def health_check():
    return {"status": "healthy", "service": "fastapi-opensearch"}

@app.get("/opensearch/health")
def get_opensearch_health():
    try:
        health = client.cluster.health()
        return {"opensearch_health": health}
    except Exception as e:
        raise HTTPException(status_code=503, detail=str(e))

@app.get("/opensearch/indices")
def list_indices():
    try:
        indices = client.cat.indices(format="json")
        return {
            "indices": [
                {
                    "index": idx["index"],
                    "health": idx.get("health", "unknown"),
                    "status": idx.get("status", "unknown"),
                    "docs_count": int(idx.get("docs.count", 0)),
                    "store_size": idx.get("store.size", "0b"),
                    "pri": idx.get("pri", "1"),
                }
                for idx in indices
            ]
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# -------------------------
# App Entry Point
# -------------------------
def main():
    uvicorn.run(app, host="0.0.0.0", port=8080)

if __name__ == "__main__":
    main()
