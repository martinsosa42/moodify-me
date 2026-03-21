# ── Stage 1: Build ───────────────────────────────────────────────────────────
FROM gradle:8.8-jdk21 AS build
WORKDIR /app

# Copiamos solo los archivos de dependencias primero (mejor cache de capas)
COPY build.gradle.kts settings.gradle.kts ./
RUN gradle dependencies --no-daemon || true

# Copiamos el código fuente y compilamos
COPY src ./src
RUN gradle shadowJar --no-daemon -x test

# ── Stage 2: Runtime ──────────────────────────────────────────────────────────
FROM eclipse-temurin:21-jre-jammy
WORKDIR /app

# Usuario no-root por seguridad
RUN addgroup --system appgroup && adduser --system --ingroup appgroup appuser

COPY --from=build /app/build/libs/*-all.jar app.jar

RUN chown appuser:appgroup app.jar
USER appuser

EXPOSE 8080

# Healthcheck interno del contenedor
HEALTHCHECK --interval=20s --timeout=5s --start-period=40s --retries=3 \
  CMD wget -qO- http://localhost:8080/health || exit 1

ENTRYPOINT ["java", \
  "-XX:+UseContainerSupport", \
  "-XX:MaxRAMPercentage=75.0", \
  "-jar", "app.jar"]
