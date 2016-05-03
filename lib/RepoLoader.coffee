https = require 'https'
Promise = require 'bluebird'
	_ = require 'underscore'
RepositoriesClass = require './model/Repositories.coffee'
Npm = require './package/Npm.coffee'
promiseRetry = require 'promise-retry'

module.exports = class
	constructor: (settings, dependencies) ->
		@settings = settings
		@logger = dependencies.logger
		@Repositories = new RepositoriesClass(dependencies.mongodb)
		@handlers = [
			new Npm(dependencies)
		]
		@path = '/repositories'
		@previousRss = process.memoryUsage().rss
		@maxRss = process.memoryUsage().rss
		
	syncRepositories: ->
		@getRepositories (repositories) => Promise.resolve(repositories).bind(@).map @handleRepository

	handleRepository: (repository) ->
		Promise.all [
			@Repositories.upsert repository
			Promise.all(handler.run repository for handler in @handlers)
		]
			
	getRepositories: (handler) ->
		@_request {}, handler

	_getNextRepositoryPage: (response, handler) ->
		# example '<https://api.github.com/repositories?since=367>; rel="next", <https://api.github.com/repositories{?since}>; rel="first"'
		link = response.headers.link
		if link
			@path = link.match(/^<.+(\/repositories.+)>; rel="next"/)[1]
		else
			@path = "" # this will break the loop

	_request: (options, handler) ->
		return if not @path
		currentRss = process.memoryUsage().rss
		@maxRss = Math.max(@maxRss, currentRss)
		@logger.info "RepoLoader:processing", @path, "(memory @ max: #{parseInt(@maxRss / 1024, 10)} KB, current: #{parseInt(currentRss / 1024, 10)} KB; change: #{if currentRss > @previousRss then "+" else ""}#{parseInt((currentRss - @previousRss) / 1024, 10)} KB)"
		@previousRss = currentRss
		opts = _.defaults({path: @path}, options)
		process.nextTick =>
			Promise.bind(@)
			.then ->
				promiseRetry (retry, number) =>
					@_requestAsync opts, handler
					.catch (e) -> console.log "Retry RepoLoader #{number}", e; retry()
				, @retryOptions
			.then ->
				@_request(opts, handler)

	_requestAsync: (options, handler) ->
		# use "next" here to increase performance (avoid rate limitation!!)
		#next = @_getNextRepositoryPage response, handler

		new Promise (resolve, reject) =>
			request = https.get _.extend(
				hostname: 'api.github.com'
				headers:
					'User-Agent': ''
					'Authorization': "token #{@settings.token}"
				, options)
			, (response) =>
				accumulator = ''
				response.on 'data', (chunk) -> accumulator += chunk
				response.on 'end', =>
					@parse accumulator
					.then (json) ->
						resolve handler(json).then -> @_getNextRepositoryPage response, handler
					.catch (e) ->
						console.log "Error in RepoLoader. Skip this page", e
						resolve @_getNextRepositoryPage response, handler
				response.on 'error', (error) -> console.error "Error in RepoLoader", error; reject {error}

			request.on 'error', (error) -> console.error "Error in RepoLoader (outer)", error; reject {error}
			request.end()

	parse: (data) ->
		Promise.try -> JSON.parse data
