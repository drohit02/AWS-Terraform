from fastapi import FastAPI
import psutil
import requests
import uvicorn
import os

app = FastAPI(title="Service A")

# Read other service URL from ENV
SERVICE_B_URL = os.getenv("SERVICE_B_URL", "http://localhost:8202/service-b/status")

# 1. Own status API
@app.get("/service-a/status")
def get_own_status():
    cpu_percent = psutil.cpu_percent(interval=1)
    memory = psutil.virtual_memory()
    return {
        "service": "A",
        "cpu_percent": cpu_percent,
        "memory_percent": memory.percent,
        "status": "running"
    }

# 2. Call Service B's status API
@app.get("/service-a/other-status")
def get_other_status():
    try:
        response = requests.get(SERVICE_B_URL, timeout=5)
        response.raise_for_status()
        return {"service_b_response": response.json()}
    except requests.exceptions.RequestException as e:
        return {"error": str(e)}

# 3. Main runner
def main():
    uvicorn.run(app, host="0.0.0.0", port=8081)

if __name__ == "__main__":
    main()
