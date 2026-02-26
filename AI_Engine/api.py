from fastapi import FastAPI, Depends, HTTPException, Security
from fastapi.security.api_key import APIKeyHeader
from starlette import status
from pydantic import BaseModel
import joblib
import pandas as pd
import os
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

API_KEY_NAME = "X-API-Key"
api_key_header = APIKeyHeader(name=API_KEY_NAME, auto_error=False)

def get_api_key(api_key: str = Security(api_key_header)):
    expected_key = os.getenv("AI_SECRET_KEY")
    # If no key is set in .env (unlikely if done correctly), we allow for now but warn
    if not expected_key:
        return api_key
    if api_key == expected_key:
        return api_key
    raise HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Invalid or missing API Key",
    )

app = FastAPI(title="Hybrid EA - AI Prediction Server")

# Helper to load models on startup
def load_ml_model(name):
    models_dir = os.getenv("MODELS_DIR", "models")
    path = os.path.join(models_dir, f"{name}_model.pkl")
    if os.path.exists(path):
        print(f"Loaded model: {path}")
        return joblib.load(path)
    else:
        print(f"WARNING: Model {path} not found. Please run train.py first! Running with dummy predictions.")
        return None

# Dictionary to hold our models in memory
models = {
    "swing": load_ml_model("swing"),
    "scalping": load_ml_model("scalping")
}

# Define the exact JSON structure sent by MQL5's FeatureExtractor
class MarketFeatures(BaseModel):
    atr: float
    adx: float
    spread: float
    ema_slope: float
    volume: int
    hour: int

def get_prediction(model_name: str, features: MarketFeatures):
    model = models.get(model_name)
    
    if model is None:
        # Fallback if model doesn't exist yet
        return {"probability": 0.50}
        
    # Convert incoming JSON dict to DataFrame matching training format
    X_live = pd.DataFrame([features.dict()])
    
    # predict_proba returns array like [[prob_class_0, prob_class_1]]
    # We want prob_class_1 (the probability of success / high quality setup)
    probability = model.predict_proba(X_live)[0][1]
    
    print(f"[{model_name.upper()}] Input: {features.dict()} -> Probability: {probability:.4f}")
    
    # Return as standard float so MQL5 can easily parse it
    return {"probability": float(probability)}

# ---------------- API ENDPOINTS ---------------- #

@app.get("/")
def health_check():
    return {"status": "AI Server is running!", "models_loaded": {k: (v is not None) for k, v in models.items()}}

@app.post("/predict_swing")
def predict_swing(features: MarketFeatures, api_key: str = Depends(get_api_key)):
    return get_prediction("swing", features)

@app.post("/predict_scalping")
def predict_scalping(features: MarketFeatures, api_key: str = Depends(get_api_key)):
    return get_prediction("scalping", features)

# To run this server, use the command in your terminal:
# uvicorn api:app --host 127.0.0.1 --port 5000 --reload
