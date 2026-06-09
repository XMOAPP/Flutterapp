FROM dart:stable AS build

WORKDIR /app
COPY pubspec.yaml ./
RUN dart pub get

COPY bin ./bin
RUN dart compile exe bin/server.dart -o /app/server

FROM debian:bookworm-slim

WORKDIR /app
COPY --from=build /app/server /app/server

ENV PORT=3000
EXPOSE 3000

CMD ["/app/server"]
