# Business Registration Time Predictor — API

FastAPI service wrapping the best model trained in
`summative/linear_regression/multivariate.ipynb` (RandomForestRegressor,
selected by lowest test RMSE against SGDRegressor, LinearRegression, and
DecisionTreeRegressor on the World Bank Doing Business indicators).

## Run locally

```bash
cd summative/API
uv venv
uv pip install -r requirements.txt
uv run uvicorn prediction:app --reload
```

Then open **http://127.0.0.1:8000/docs** for Swagger UI.

## Deploy to Render (free tier)

1. Push this repo to GitHub (public or Render-connected private repo).
2. Go to https://dashboard.render.com/ → **New** → **Blueprint**, and point it
   at this repo. Render will read `render.yaml` in this folder and configure
   the service automatically (build command, start command, Python version).
   - Alternatively: **New** → **Web Service** → select the repo → set
     **Root Directory** to `summative/API`, **Build Command** to
     `pip install -r requirements.txt`, and **Start Command** to
     `uvicorn prediction:app --host 0.0.0.0 --port $PORT`.
3. Once deployed, Render gives you a public URL like
   `https://business-registration-predictor.onrender.com`.
4. Swagger UI is automatically available at that URL + `/docs`, e.g.
   `https://business-registration-predictor.onrender.com/docs` — this is the
   URL to paste into the assignment README and to point the Flutter app's
   `kPredictEndpoint` at (`.../predict`).

## Endpoints

| Method | Path       | Purpose                                                       |
|--------|-----------|----------------------------------------------------------------|
| GET    | `/`        | Basic liveness message                                        |
| GET    | `/health`  | Health check                                                   |
| POST   | `/predict` | Returns `{"predicted_days": <float>}` given the 4 input fields |
| POST   | `/retrain` | Retrains and overwrites the model on newly supplied labeled rows |

### `/predict` request body

```json
{
  "procedures": 6,
  "cost_pct_income": 12.5,
  "paid_in_capital_pct": 0,
  "gdp_per_capita": 850
}
```

All four fields are required, typed as floats, and range-checked by
Pydantic (e.g. `procedures` must be between 1 and 20) — out-of-range or
missing values return HTTP 422 with a description of what failed, which
Swagger UI will show you directly.

### `/retrain` request body

```json
{
  "rows": [
    {"procedures": 6, "cost_pct_income": 12.5, "paid_in_capital_pct": 0, "gdp_per_capita": 850, "days_to_start": 27.0},
    { "...": "at least 10 rows total" }
  ]
}
```

Retrains a fresh `RandomForestRegressor` + `StandardScaler` on the supplied
rows and overwrites `best_model.pkl` / `scaler.pkl` in place — the next
`/predict` call uses the retrained model immediately, no redeploy needed.

## CORS

`allow_origins=["*"]` with only `GET`/`POST` allowed and credentials
disabled. Reasoning: the Flutter mobile client doesn't send a browser
`Origin` header at all (CORS is a browser-only mechanism), so this setting
only affects browser-based callers — chiefly Swagger UI itself and anyone
testing the API from a web page. Since this endpoint is public,
read-mostly, and carries no user session or credential to leak, a
permissive-but-method-scoped policy is appropriate here. A production
service handling authenticated/private data should instead pin
`allow_origins` to a specific known frontend domain.
