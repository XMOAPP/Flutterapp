FROM dart:stable AS build

WORKDIR /app
COPY pubspec.yaml ./
RUN dart pub get

COPY bin ./bin
COPY lib ./lib
RUN dart compile exe bin/server.dart -o /app/server

FROM debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=build /app/server /app/server

ENV PORT=3000
EXPOSE 3000

CMD ["/app/server"]
