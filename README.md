# Business Registration Time Predictor

**Mission & problem:** IremboGov and similar e-government platforms exist to
make citizen-government transactions faster. This project predicts how many
days it takes to legally start a business in a given economy, using World
Bank Doing Business indicators (procedures, cost, paid-in capital, GDP per
capita) as a measurable proxy for regulatory/government service-delivery
efficiency. A model of what drives long registration times is a model of
where government workflow bottlenecks live.

**Live API (Swagger UI):** https://business-registration-predictor.onrender.com/docs

**Video demo:** https://youtu.be/YREmhyUVZqg

## Running the mobile app

```bash
cd summative/FlutterApp
flutter pub get
flutter run
```

First, set the deployed API URL in `lib/main.dart` (`kPredictEndpoint`)

## Running the API locally

```bash
cd summative/API
uv venv && uv pip install -r requirements.txt
uv run uvicorn prediction:app --reload
```

Open `http://127.0.0.1:8000/docs` for Swagger UI.

## Data source note

The notebook attempts a live pull from the World Bank Indicators API first
and falls back to a clearly-labeled synthetic placeholder only if that API
is unreachable from the execution environment (see the notebook's first
markdown cell for full detail). No code changes are needed to use real data
— just run it somewhere with normal internet access.
