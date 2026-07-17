FROM --platform=$TARGETPLATFORM elixir:1.16-alpine AS build

ENV ERL_FLAGS="+JPperf true"
ENV MIX_ENV=prod
RUN mix local.hex --force && \
    mix local.rebar --force

WORKDIR /app

COPY mix.exs mix.lock ./

RUN mix deps.get --only prod

COPY . .

RUN mix compile
RUN mix release



FROM --platform=$TARGETPLATFORM erlang:24-alpine
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

RUN apk add --no-cache ca-certificates libsasl libstdc++ lz4-libs zlib ncurses-libs openssl bash libcrypto3 curl

WORKDIR /app
RUN chown nobody /app
ENV MIX_ENV="prod"

COPY --from=build --chown=nobody:root /app/_build/prod/rel/open_plaato_keg ./

RUN mkdir -p /db && chown nobody /db

USER nobody

CMD ["./bin/open_plaato_keg", "start"]