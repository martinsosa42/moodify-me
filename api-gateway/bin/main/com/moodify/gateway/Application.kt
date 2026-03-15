package com.moodify.gateway
 
import io.ktor.server.application.*
import io.ktor.server.engine.*
import io.ktor.server.netty.*
import io.ktor.server.plugins.contentnegotiation.*
import io.ktor.server.plugins.callloging.*
import io.ktor.server.plugins.cors.routing.*
import io.ktor.serialization.kotlinx.json.*
import io.ktor.http.*
import org.slf4j.event.Level
 
fun main() {
    embeddedServer(Netty, port = 8080, module = Application::module).start(wait = true)
}
 
fun Application.module() {
    install(ContentNegotiation) { json() }
    install(CallLogging) { level = Level.INFO }
    install(CORS) {
        anyHost()
        allowMethod(HttpMethod.Post)
        allowMethod(HttpMethod.Get)
        allowHeader(HttpHeaders.ContentType)
    }
    configureRouting()
}