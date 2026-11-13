# Etapa 1: compilar con la misma version de Flutter que se usa en local (3.47.7).
# Se clona desde GitHub porque las imagenes publicas no tienen ese tag exacto.
FROM debian:bookworm-slim AS build
RUN apt-get update \
 && apt-get install -y --no-install-recommends git curl unzip xz-utils zip ca-certificates \
 && rm -rf /var/lib/apt/lists/*
ARG FLUTTER_VERSION=3.47.7
RUN git clone --depth 1 --branch ${FLUTTER_VERSION} https://github.com/flutter/flutter.git /opt/flutter
ENV PATH="/opt/flutter/bin:${PATH}"
RUN flutter --disable-analytics && flutter precache --web

WORKDIR /app
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get
COPY . .
# Solo la clave publicable (anon/publishable); nunca la service_role.
ARG SUPABASE_URL
ARG SUPABASE_ANON_KEY
RUN flutter build web --release \
    --dart-define=SUPABASE_URL=${SUPABASE_URL} \
    --dart-define=SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY}

# Etapa 2: servir los archivos estaticos
FROM nginx:1.27-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/build/web /usr/share/nginx/html
EXPOSE 80
