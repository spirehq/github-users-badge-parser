onDeath = require("death")({SIGHUP: true, uncaughtException: true})

# In nomine SIGINT, SIGTERM, SIGQUIT, amen
module.exports = (name, dependencies) ->
  onDeath (signal, error) ->
    params = {}
    params.signal = signal
    params.stack = error.stack if error
    dependencies.logger.error("#{name}:died", params)
    process.exit(1)
