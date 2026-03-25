# syntax=docker/dockerfile:1

ARG RUBY_VERSION=3.4.8
FROM ruby:${RUBY_VERSION}-slim

WORKDIR /app

ENV RACK_ENV="production" \
    PORT="9292" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test" \
    LEWISMD_SHARE_STORAGE_PATH="/var/lib/lewismd-share"

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      build-essential \
      ca-certificates \
      curl \
      libxml2-dev \
      libxslt1-dev \
      pkg-config && \
    rm -rf /var/lib/apt/lists/*

COPY Gemfile Gemfile.lock ./
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git

COPY . .

RUN groupadd --system --gid 10001 shareapi && \
    useradd --system --uid 10001 --gid 10001 --create-home --shell /bin/bash shareapi && \
    mkdir -p /var/lib/lewismd-share /app/tmp && \
    chown -R shareapi:shareapi /var/lib/lewismd-share /app

USER 10001:10001

EXPOSE 9292

CMD ["bundle", "exec", "puma", "-C", "config/puma.rb", "config.ru"]
