"""
Task 2: FastAPI service for the Business Registration Time Predictor.

Loads the best model saved by summative/linear_regression/multivariate.ipynb
(RandomForestRegressor, selected on lowest test RMSE against SGDRegressor,
LinearRegression, and DecisionTreeRegressor) and serves it behind a single
/predict endpoint, plus a /retrain endpoint for when new data becomes
available.

Run locally:
    uv run uvicorn prediction:app --reload

Swagger UI (auto-generated docs + test console): http://127.0.0.1:8000/docs
"""

import os
from typing import List

import joblib
import numpy as np
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from sklearn.ensemble import RandomForestRegressor
from sklearn.model_selection import train_test_split
from sklearn.metrics import mean_squared_error, r2_score

MODEL_PATH = os.path.join(os.path.dirname(__file__), "best_model.pkl")
SCALER_PATH = os.path.join(os.path.dirname(__file__), "scaler.pkl")

model = joblib.load(MODEL_PATH)
scaler = joblib.load(SCALER_PATH)

app = FastAPI(
    title="Business Registration Time Predictor API",
    description=(
        "Predicts the number of days required to legally start a business "
        "in a given economy, based on World Bank Doing Business indicators "
        "(procedures, cost, paid-in capital, GDP per capita). Built as a "
        "mission-aligned regression example for e-government service-delivery "
        "efficiency."
    ),
    version="1.0.0",
)

# ---------------------------------------------------------------------------
# CORS
#
# Reasoning:
# - This API is consumed by a mobile Flutter app, which does not send a
#   browser "Origin" header, so CORS does not restrict the mobile client at
#   all -- CORS is a browser-enforced mechanism.
# - CORS *does* matter for two browser-based use cases we want to support:
#   (1) the Swagger UI served at /docs on this same origin, and
#   (2) anyone testing the API directly from a browser-based HTTP client or
#       a future web front end.
# - We therefore allow all origins for GET/POST on this read-mostly,
#   no-auth, publicly-documented demo endpoint (there is no user session,
#   cookie, or credential to leak), but we explicitly restrict the allowed
#   HTTP methods and disable credentialed requests, so this is intentionally
#   permissive-but-scoped rather than a blanket "allow everything".
# - If this were serving private/authenticated data, allow_origins would be
#   pinned to a specific known frontend domain instead of "*".
# ---------------------------------------------------------------------------
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["GET", "POST"],
    allow_headers=["*"],
)


class PredictionInput(BaseModel):
    procedures: float = Field(
        ..., ge=1, le=20,
        description="Number of legal/administrative procedures required to register a business.",
    )
    cost_pct_income: float = Field(
        ..., ge=0, le=500,
        description="Cost of registration as a percentage of income per capita.",
    )
    paid_in_capital_pct: float = Field(
        ..., ge=0, le=500,
        description="Required paid-in minimum capital, as a percentage of income per capita.",
    )
    gdp_per_capita: float = Field(
        ..., ge=50, le=150000,
        description="GDP per capita in current US dollars.",
    )

    class Config:
        json_schema_extra = {
            "example": {
                "procedures": 6,
                "cost_pct_income": 12.5,
                "paid_in_capital_pct": 0,
                "gdp_per_capita": 850,
            }
        }


class PredictionOutput(BaseModel):
    predicted_days: float


class RetrainRow(BaseModel):
    procedures: float = Field(..., ge=1, le=20)
    cost_pct_income: float = Field(..., ge=0, le=500)
    paid_in_capital_pct: float = Field(..., ge=0, le=500)
    gdp_per_capita: float = Field(..., ge=50, le=150000)
    days_to_start: float = Field(..., ge=0, description="Ground-truth target for retraining.")


class RetrainRequest(BaseModel):
    rows: List[RetrainRow] = Field(..., min_length=10, description="New labeled data to retrain on.")


class RetrainResponse(BaseModel):
    message: str
    n_rows_used: int
    train_rmse: float
    test_rmse: float
    test_r2: float


def _features_from_row(procedures, cost_pct_income, paid_in_capital_pct, gdp_per_capita):
    log_gdp = np.log1p(gdp_per_capita)
    return [procedures, cost_pct_income, paid_in_capital_pct, log_gdp]


@app.get("/")
def root():
    return {"message": "Business Registration Time Predictor API. Visit /docs for Swagger UI."}


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/predict", response_model=PredictionOutput)
def predict(payload: PredictionInput):
    try:
        row = np.array([_features_from_row(
            payload.procedures,
            payload.cost_pct_income,
            payload.paid_in_capital_pct,
            payload.gdp_per_capita,
        )])
        row_scaled = scaler.transform(row)
        prediction = float(model.predict(row_scaled)[0])
    except Exception as exc:  # pragma: no cover
        raise HTTPException(status_code=500, detail=f"Prediction failed: {exc}")

    return PredictionOutput(predicted_days=round(prediction, 2))


@app.post("/retrain", response_model=RetrainResponse)
def retrain(payload: RetrainRequest):
    """
    Retrains the model from scratch on newly supplied labeled data (e.g. a
    fresh export from IremboGov or an updated World Bank release) and
    overwrites best_model.pkl + scaler.pkl in place, so subsequent /predict
    calls use the retrained model immediately -- no redeploy required.
    """
    global model, scaler

    X_raw = np.array([
        _features_from_row(r.procedures, r.cost_pct_income, r.paid_in_capital_pct, r.gdp_per_capita)
        for r in payload.rows
    ])
    y = np.array([r.days_to_start for r in payload.rows])

    X_train, X_test, y_train, y_test = train_test_split(X_raw, y, test_size=0.2, random_state=42)

    new_scaler = scaler.__class__()
    X_train_scaled = new_scaler.fit_transform(X_train)
    X_test_scaled = new_scaler.transform(X_test)

    new_model = RandomForestRegressor(n_estimators=200, max_depth=8, random_state=42)
    new_model.fit(X_train_scaled, y_train)

    train_pred = new_model.predict(X_train_scaled)
    test_pred = new_model.predict(X_test_scaled)

    joblib.dump(new_model, MODEL_PATH)
    joblib.dump(new_scaler, SCALER_PATH)

    model = new_model
    scaler = new_scaler

    return RetrainResponse(
        message="Model retrained and saved successfully.",
        n_rows_used=len(payload.rows),
        train_rmse=float(mean_squared_error(y_train, train_pred) ** 0.5),
        test_rmse=float(mean_squared_error(y_test, test_pred) ** 0.5),
        test_r2=float(r2_score(y_test, test_pred)),
    )
