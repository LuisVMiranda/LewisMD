# frozen_string_literal: true

max_threads_count = Integer(ENV.fetch("LEWISMD_SHARE_PUMA_MAX_THREADS", "5"))
threads max_threads_count, max_threads_count

environment ENV.fetch("RACK_ENV", "production")
port ENV.fetch("PORT", "9292")

workers = Integer(ENV.fetch("WEB_CONCURRENCY", "1"))
workers workers if workers > 1

preload_app!

plugin :tmp_restart
