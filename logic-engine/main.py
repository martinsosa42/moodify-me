from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from vaderSentiment.vaderSentiment import SentimentIntensityAnalyzer
import spotipy
from spotipy.oauth2 import SpotifyClientCredentials
import os
from dotenv import load_dotenv

load_dotenv()

app = FastAPI(title="Moodify Me - Logic Engine", version="1.0.0")

sp = spotipy.Spotify(auth_manager=SpotifyClientCredentials(
    client_id=os.getenv("SPOTIFY_CLIENT_ID"),
    client_secret=os.getenv("SPOTIFY_CLIENT_SECRET"),
))

analyzer = SentimentIntensityAnalyzer()


class MoodRequest(BaseModel):
    text: str
    limit: int = 10


class TrackOut(BaseModel):
    id: str
    name: str
    artist: str
    preview_url: str | None
    valence: float
    energy: float
    danceability: float


class MoodResponse(BaseModel):
    sentiment: str
    compound: float
    valence: float
    energy: float
    danceability: float
    tracks: list[TrackOut]


def compound_to_label(compound: float) -> str:
    if compound >= 0.05:
        return "positive"
    elif compound <= -0.05:
        return "negative"
    return "neutral"


def score_to_audio_features(compound: float) -> dict:
    valence = round((compound + 1) / 2, 2)
    if compound >= 0.5:
        energy, danceability = 0.8, 0.75
    elif compound >= 0.05:
        energy, danceability = 0.6, 0.6
    elif compound >= -0.05:
        energy, danceability = 0.5, 0.5
    elif compound >= -0.5:
        energy, danceability = 0.4, 0.4
    else:
        energy, danceability = 0.25, 0.3
    return {"valence": valence, "energy": energy, "danceability": danceability}


@app.post("/analyze", response_model=MoodResponse)
async def analyze_mood(req: MoodRequest):
    if not req.text.strip():
        raise HTTPException(status_code=422, detail="El texto no puede estar vacío.")

    scores = analyzer.polarity_scores(req.text)
    compound = scores["compound"]
    features = score_to_audio_features(compound)
    label = compound_to_label(compound)

    # Mapa de géneros según sentimiento
    genre_queries = {
        "positive": ["pop feliz", "dance pop", "happy hits"],
        "neutral":  ["indie chill", "lo-fi", "ambient focus"],
        "negative": ["sad songs", "acoustic melancholic", "blues"],
    }

    query = genre_queries[label][0]

    try:
        results = sp.search(q=query, type="track", limit=req.limit, market="AR")
        raw_tracks = results["tracks"]["items"]
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"Error Spotify: {str(e)}")

    # Obtener audio features
    track_ids = [t["id"] for t in raw_tracks]
    try:
        audio_features = sp.audio_features(track_ids) or []
    except Exception:
        audio_features = []

    af_map = {af["id"]: af for af in audio_features if af}

    tracks = []
    for track in raw_tracks:
        af = af_map.get(track["id"], {})
        tracks.append(TrackOut(
            id=track["id"],
            name=track["name"],
            artist=track["artists"][0]["name"],
            preview_url=track.get("preview_url"),
            valence=af.get("valence", 0.0),
            energy=af.get("energy", 0.0),
            danceability=af.get("danceability", 0.0),
        ))

    return MoodResponse(
        sentiment=label,
        compound=compound,
        tracks=tracks,
        **features,
    )


@app.get("/health")
async def health():
    return {"status": "ok", "service": "logic-engine"}