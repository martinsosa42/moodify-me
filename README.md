# 🎵 Moodify Me

Aplicación políglota que genera playlists de Spotify basadas en tu estado de ánimo.

```
Flutter (Dart)  →  API Gateway (Kotlin/Ktor)  →  Logic Engine (Python/FastAPI)  →  Spotify API
```

---

## Estructura del proyecto

```
moodify-me/
├── flutter-app/              # Interfaz móvil (Dart/Flutter)
│   ├── lib/
│   │   └── main.dart
│   └── pubspec.yaml
│
├── api-gateway/              # Gateway central (Kotlin/Ktor)
│   ├── src/main/kotlin/com/moodify/gateway/
│   │   ├── Application.kt
│   │   └── Routing.kt
│   ├── build.gradle.kts
│   └── Dockerfile
│
├── logic-engine/             # Análisis de sentimiento + Spotify (Python/FastAPI)
│   ├── main.py
│   ├── requirements.txt
│   └── Dockerfile
│
├── docker-compose.yml        # Levanta Ktor + FastAPI
└── .env.example              # Variables de entorno a completar
```

---

## Guía rápida — Conectar los 3 componentes en local

### Paso 1 — Credenciales de Spotify

1. Entrá a https://developer.spotify.com/dashboard y creá una aplicación.
2. Copiá el **Client ID** y el **Client Secret**.
3. En la raíz del proyecto:

```bash
cp .env.example .env
# Editá .env y pegá tus credenciales
```

---

### Paso 2 — Levantar el backend con Docker Compose

```bash
docker compose up --build
```

Esto levanta:
- **Logic Engine** en `http://localhost:8000`
- **API Gateway** en `http://localhost:8080`

Verificá que estén corriendo:

```bash
curl http://localhost:8000/health
# → {"status":"ok","service":"logic-engine"}

curl http://localhost:8080/health
# → {"status":"ok","service":"api-gateway"}
```

Probá el flujo completo desde la terminal:

```bash
curl -X POST http://localhost:8080/mood \
  -H "Content-Type: application/json" \
  -d '{"mood": "estoy relajado pero productivo", "limit": 5}'
```

---

### Paso 3 — Correr la app Flutter

```bash
cd flutter-app
flutter pub get
flutter run
```

> La app apunta a `http://localhost:8080` por defecto.
> Si corrés en un emulador Android, reemplazá `localhost` por `10.0.2.2`.

---

## Contratos de API

### Flutter → API Gateway

```
POST /mood
{
  "mood": "string",   // texto libre del usuario
  "limit": 10         // cantidad de canciones (default: 10)
}
```

### API Gateway → Logic Engine

```
POST /analyze
{
  "text": "string",
  "limit": 10
}
```

### Logic Engine → API Gateway (y de vuelta a Flutter)

```json
{
  "sentiment": "positive | neutral | negative",
  "compound": 0.72,
  "tracks": [
    {
      "id": "spotify_track_id",
      "name": "Song Name",
      "artist": "Artist Name",
      "preview_url": "https://...",
      "valence": 0.85,
      "energy": 0.78,
      "danceability": 0.71
    }
  ]
}
```

---

## Desarrollo sin Docker

### Logic Engine (Python)

```bash
cd logic-engine
python -m venv venv && source venv/bin/activate
pip install -r requirements.txt
cp ../.env.example .env   # completá las credenciales
uvicorn main:app --reload --port 8000
```

### API Gateway (Kotlin)

```bash
cd api-gateway
./gradlew run
# Corre en :8080, apunta a http://localhost:8000 por defecto
```
