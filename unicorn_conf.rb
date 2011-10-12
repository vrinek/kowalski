# nuke workers after 30 seconds instead of 60 seconds (the default)
timeout 500

# feel free to point this anywhere accessible on the filesystem
pid ".pid"

# By default, the Unicorn logger will write to stderr.
# Additionally, some applications/frameworks log to stderr or stdout,
# so prevent them from going to /dev/null when daemonized here:
stderr_path "logs/sinatra.log"
stdout_path "logs/sinatra.log"
