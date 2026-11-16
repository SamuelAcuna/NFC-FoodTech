# Etapa 1: compilar con Flutter 3.47.7 (misma version que en local).
# Parte de la imagen de cirruslabs (trae git, curl y unzip; no usa apt-get,
# que falla en redes que bloquean deb.debian.org) e instala encima la version
# exacta desde GitHub.
FROM ghcr.io/cirruslabs/flutter:stable AS build
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
