package com.moodify.gateway

import io.ktor.client.*
import io.ktor.client.call.*
import io.ktor.client.engine.cio.*
import io.ktor.client.plugins.contentnegotiation.*
import io.ktor.client.request.*
import io.ktor.http.*
import io.ktor.serialization.kotlinx.json.*
import io.ktor.server.application.*
import io.ktor.server.request.*
import io.ktor.server.response.*
import io.ktor.server.routing.*
import kotlinx.serialization.Serializable

// ── Data classes (contratos JSON) ─────────────────────────────────────────────

@Serializable
data class MoodRequest(
    val mood: String,
    val uid: String? = null,
    val limit: Int = 10,
)

@Serializable
data class LogicEngineRequest(
    val text: String,
    val limit: Int,
)

@Serializable
data class TrackOut(
    val id: String,
    val name: String,
    val artist: String,
    val preview_url: String?,
    val valence: Double,
    val energy: Double,
    val danceability: Double,
)

@Serializable
data class LogicEngineResponse(
    val sentiment: String,
    val compound: Double,
    val valence: Double,
    val energy: Double,
    val danceability: Double,
    val tracks: List<TrackOut>,
)

@Serializable
data class GatewayResponse(
    val sentiment: String,
    val compound: Double,
    val tracks: List<TrackOut>,
)

@Serializable
data class ErrorResponse(val error: String)

// ── HTTP Client compartido ────────────────────────────────────────────────────

val httpClient = HttpClient(CIO) {
    install(ContentNegotiation) { json() }
}

val logicEngineUrl = System.getenv("LOGIC_ENGINE_URL") ?: "http://localhost:8000"

// ── Routing ───────────────────────────────────────────────────────────────────

fun Application.configureRouting() {
    routing {

        get("/health") {
            call.respond(mapOf("status" to "ok", "service" to "api-gateway"))
        }

        // POST /mood  ← recibe petición desde Flutter
        post("/mood") {
            val request = runCatching { call.receive<MoodRequest>() }.getOrNull()
                ?: return@post call.respond(
                    HttpStatusCode.BadRequest,
                    ErrorResponse("Cuerpo de petición inválido"),
                )

            if (request.mood.isBlank()) {
                return@post call.respond(
                    HttpStatusCode.UnprocessableEntity,
                    ErrorResponse("El campo 'mood' no puede estar vacío"),
                )
            }

            // Reenvía al Logic Engine (Python)
            val engineResponse = runCatching {
                httpClient.post("$logicEngineUrl/analyze") {
                    contentType(ContentType.Application.Json)
                    setBody(LogicEngineRequest(text = request.mood, limit = request.limit))
                }.body<LogicEngineResponse>()
            }.getOrElse { e ->
                return@post call.respond(
                    HttpStatusCode.BadGateway,
                    ErrorResponse("Error al comunicarse con el Logic Engine: ${e.message}"),
                )
            }

            call.respond(
                HttpStatusCode.OK,
                GatewayResponse(
                    sentiment = engineResponse.sentiment,
                    compound = engineResponse.compound,
                    tracks = engineResponse.tracks,
                ),
            )
        }
    }
}
