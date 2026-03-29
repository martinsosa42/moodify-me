from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded
from spotipy import Spotify, SpotifyClientCredentials
from groq import Groq
import os
import json
import logging
from dotenv import load_dotenv

load_dotenv()

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# ── App & Middleware ──────────────────────────────────────────────────────────

limiter = Limiter(key_func=get_remote_address)

app = FastAPI(title="Synapsify - Logic Engine", version="3.3.0")

app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

app.add_middleware(
    CORSMiddleware,
    allow_origins=[os.getenv("ALLOWED_ORIGIN", "http://localhost:3000")],
    allow_methods=["GET", "POST"],
    allow_headers=["Content-Type"],
)

# ── Clientes ──────────────────────────────────────────────────────────────────

sp_public = Spotify(auth_manager=SpotifyClientCredentials(
    client_id=os.getenv("SPOTIFY_CLIENT_ID"),
    client_secret=os.getenv("SPOTIFY_CLIENT_SECRET"),
))

groq_client = Groq(api_key=os.getenv("GROQ_API_KEY"))

# ── Schemas ───────────────────────────────────────────────────────────────────

# [FIX] limit acotado entre 1 y 50 — evita abusos y errores con audio_features()
class MoodRequest(BaseModel):
    text: str
    limit: int = Field(default=10, ge=1, le=50)
    accessToken: str | None = None
    userId: str | None = None


class TrackOut(BaseModel):
    id: str
    name: str
    artist: str
    preview_url: str | None
    valence: float
    energy: float
    danceability: float


class MoodResponse(BaseModel):
    interpretation: str
    query_used: str
    tracks: list[TrackOut]
    playlistId: str | None = None
    playlistUrl: str | None = None

# ── Prompt ────────────────────────────────────────────────────────────────────

SYSTEM_PROMPT = """Sos un experto en música que convierte descripciones en lenguaje natural 
en parámetros de búsqueda para la API de Spotify.

El usuario describe lo que quiere escuchar. Tu trabajo es interpretar ese pedido y devolver 
un JSON con los parámetros óptimos para buscar en Spotify.

IMPORTANTE: Respondé ÚNICAMENTE con un JSON válido, sin texto adicional, sin markdown, 
sin explicaciones. Solo el JSON puro.

El JSON debe tener exactamente esta estructura:
{
  "search_query": "string - query optimizada para Spotify search en inglés",
  "search_type": "track",
  "market": "AR",
  "interpretation": "string - en español, qué entendiste del pedido en máximo 1 oración",
  "target_energy": número entre 0.0 y 1.0 o null,
  "target_valence": número entre 0.0 y 1.0 o null,
  "target_danceability": número entre 0.0 y 1.0 o null,
  "target_tempo": número en BPM o null
}

Guía de parámetros de audio:
- energy: 0.0 = muy tranquilo/ambient, 1.0 = muy intenso/explosivo
- valence: 0.0 = triste/oscuro, 1.0 = alegre/eufórico  
- danceability: 0.0 = no bailable, 1.0 = muy bailable
- tempo: en BPM (techno ~140, hip-hop ~90, jazz ~120, pop ~120)

Ejemplos:
- "Jazz suave para estudiar de noche" → query: "jazz study lofi night", energy: 0.3, valence: 0.4
- "Canciones de Travis Scott" → query: "Travis Scott", energy: null, valence: null
- "Progressive para un atardecer" → query: "progressive house sunset melodic", energy: 0.65, valence: 0.6
- "Rock argentino de los 90" → query: "rock argentino 90s", energy: 0.7
- "Techno para correr" → query: "techno running workout", energy: 0.9, tempo: 140
"""

# [FIX] Whitelist de mercados válidos — evita prompt injection en el campo market
VALID_MARKETS = {
    "AR", "US", "ES", "MX", "BR", "CO", "CL", "PE", "UY", "PY",
    "GB", "DE", "FR", "IT", "JP", "AU", "CA", "NZ", "ZA",
}


def _clamp_float(value, lo: float = 0.0, hi: float = 1.0):
    """Retorna el valor si está en rango válido, None si no."""
    try:
        v = float(value)
        return v if lo <= v <= hi else None
    except (TypeError, ValueError):
        return None


# [FIX] Validación del JSON de Groq para mitigar prompt injection
def validate_groq_params(params: dict) -> dict:
    query = str(params.get("search_query", "")).strip()[:200]
    if not query:
        raise ValueError("search_query vacío o ausente en la respuesta del modelo.")

    market = params.get("market", "AR")
    if market not in VALID_MARKETS:
        market = "AR"

    tempo = params.get("target_tempo")
    try:
        tempo = float(tempo) if tempo is not None else None
        if tempo is not None and not (40 <= tempo <= 220):
            tempo = None
    except (TypeError, ValueError):
        tempo = None

    return {
        "search_query":        query,
        "market":              market,
        "interpretation":      str(params.get("interpretation", ""))[:300],
        "target_energy":       _clamp_float(params.get("target_energy")),
        "target_valence":      _clamp_float(params.get("target_valence")),
        "target_danceability": _clamp_float(params.get("target_danceability")),
        "target_tempo":        tempo,
    }


def interpret_with_groq(text: str) -> dict:
    """Usa Groq para convertir lenguaje natural en parámetros de Spotify."""
    response = groq_client.chat.completions.create(
        model="llama-3.3-70b-versatile",
        messages=[
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": f"Pedido del usuario: {text}"}
        ],
        max_tokens=500,
        temperature=0.3,
    )

    raw = response.choices[0].message.content.strip()

    # Limpiar si el modelo agrega backticks por accidente
    if "```" in raw:
        parts = raw.split("```")
        for part in parts:
            part = part.strip()
            if part.startswith("json"):
                part = part[4:].strip()
            if part.startswith("{"):
                raw = part
                break

    # [FIX] JSON parse con error controlado — no expone stack interno al cliente
    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError:
        logger.error("Groq devolvió JSON inválido: %s", raw[:200])
        raise ValueError("El modelo devolvió una respuesta con formato inválido.")

    return validate_groq_params(parsed)


# ── Helpers Spotify ───────────────────────────────────────────────────────────

def search_tracks(sp: Spotify, params: dict, limit: int) -> list[TrackOut]:
    query = params.get("search_query", "")
    market = params.get("market", "AR")

    results = sp.search(q=query, type="track", limit=limit, market=market)
    raw_tracks = results["tracks"]["items"]

    if not raw_tracks:
        return []

    track_ids = [t["id"] for t in raw_tracks]

    try:
        audio_features = sp.audio_features(track_ids) or []
    except Exception:
        audio_features = []

    af_map = {af["id"]: af for af in audio_features if af}

    target_energy = params.get("target_energy")
    target_valence = params.get("target_valence")
    target_danceability = params.get("target_danceability")

    scored_tracks = []
    for track in raw_tracks:
        if not track.get("id") or not track.get("name"):
            continue
        if not track.get("artists"):
            continue
        af = af_map.get(track["id"], {})
        valence = af.get("valence", 0.5)
        energy = af.get("energy", 0.5)
        danceability = af.get("danceability", 0.5)

        targets = [
            (target_energy, energy),
            (target_valence, valence),
            (target_danceability, danceability),
        ]
        active = [(t, v) for t, v in targets if t is not None]

        if active:
            match_score = sum(1 - abs(t - v) for t, v in active) / len(active)
        else:
            match_score = 1.0

        scored_tracks.append((match_score, TrackOut(
            id=track["id"],
            name=track["name"],
            artist=track["artists"][0]["name"],
            preview_url=track.get("preview_url"),
            valence=valence,
            energy=energy,
            danceability=danceability,
        )))

    scored_tracks.sort(key=lambda x: x[0], reverse=True)
    return [t for _, t in scored_tracks]


def save_playlist(sp: Spotify, text: str,
                  track_ids: list[str], interpretation: str) -> tuple[str, str]:
    # [FIX] userId obtenido desde el token — no se acepta del cliente
    user_id = sp.me()["id"]
    playlist = sp.user_playlist_create(
        user=user_id,
        name=f"Synapsify: {text[:40]}",
        public=False,
        description=f"Generada por Synapsify · {interpretation}",
    )
    sp.playlist_add_items(playlist["id"], [f"spotify:track:{tid}" for tid in track_ids])
    return playlist["id"], playlist["external_urls"]["spotify"]


# ── Endpoints ─────────────────────────────────────────────────────────────────

@app.post("/analyze", response_model=MoodResponse)
@limiter.limit("10/minute")  # [FIX] Rate limiting por IP
async def analyze_mood(req: MoodRequest, request: Request):
    if not req.text.strip():
        raise HTTPException(status_code=422, detail="El texto no puede estar vacío.")

    # 1. Groq interpreta el pedido
    try:
        params = interpret_with_groq(req.text)
    except ValueError as e:
        raise HTTPException(status_code=502, detail=str(e))
    except Exception:
        logger.exception("Error inesperado al llamar a Groq")
        raise HTTPException(status_code=502, detail="Error al interpretar el pedido.")

    interpretation = params.get("interpretation", req.text)
    query_used = params.get("search_query", req.text)

    # 2. Elegimos el cliente de Spotify
    sp = Spotify(auth=req.accessToken) if req.accessToken else sp_public

    # 3. Buscamos canciones
    try:
        tracks = search_tracks(sp, params, req.limit)
    except Exception:
        logger.exception("Error al buscar en Spotify")
        raise HTTPException(status_code=502, detail="Error al buscar canciones en Spotify.")

    if not tracks:
        raise HTTPException(status_code=404,
                            detail="No se encontraron canciones para ese pedido.")

    # 4. Guardamos playlist si hay sesión activa
    # [FIX] userId ya no viene del cliente — se obtiene del token en save_playlist()
    playlist_id, playlist_url = None, None
    if req.accessToken:
        try:
            playlist_id, playlist_url = save_playlist(
                sp=sp,
                text=req.text,
                track_ids=[t.id for t in tracks],
                interpretation=interpretation,
            )
        except Exception:
            logger.exception("No se pudo guardar la playlist")

    return MoodResponse(
        interpretation=interpretation,
        query_used=query_used,
        tracks=tracks,
        playlistId=playlist_id,
        playlistUrl=playlist_url,
    )


@app.get("/health")
async def health():
    return {"status": "ok", "service": "synapsify-logic-engine", "version": "3.3.0"}
