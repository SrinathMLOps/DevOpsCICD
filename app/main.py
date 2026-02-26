from fastapi import FastAPI
from fastapi.responses import JSONResponse
import os
import socket

app = FastAPI(
    title="FastAPI CI/CD Demo",
    description="Production-grade FastAPI application with Jenkins CI/CD to EKS",
    version="1.0.0"
)

@app.get("/")
async def root():
    """Root endpoint"""
    return {
        "message": "Welcome to FastAPI CI/CD Pipeline!",
        "status": "running",
        "environment": os.getenv("ENVIRONMENT", "development"),
        "hostname": socket.gethostname()
    }

@app.get("/health")
async def health_check():
    """Health check endpoint for Kubernetes probes"""
    return JSONResponse(
        status_code=200,
        content={
            "status": "healthy",
            "service": "fastapi-cicd",
            "hostname": socket.gethostname()
        }
    )

@app.get("/ready")
async def readiness_check():
    """Readiness check endpoint"""
    return JSONResponse(
        status_code=200,
        content={
            "status": "ready",
            "service": "fastapi-cicd"
        }
    )

@app.get("/info")
async def app_info():
    """Application information"""
    return {
        "app_name": "FastAPI CI/CD Demo",
        "version": "1.0.0",
        "environment": os.getenv("ENVIRONMENT", "development"),
        "hostname": socket.gethostname(),
        "python_version": "3.9+"
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
