https = require 'https'
Promise = require 'bluebird'
requestAsync = Promise.promisify((require "request"), {multiArgs: true})
FilesClass = require './model/Files.coffee'
RepositoriesClass = require './model/Repositories.coffee'
_ = require 'underscore'
promiseRetry = require 'promise-retry'

FILE = 'package.json'
MANAGER = 'npm'

module.exports = class
	constructor: (settings, dependencies) ->
		@settings = settings
		@logger = dependencies.logger
		@Files = new FilesClass(dependencies.mongodb)
		@Repositories = new RepositoriesClass(dependencies.mongodb)
		@from = 0
		@to = 1
		@networkTime = 0
		@maxNetworkTime = 0
		@mongoTime = 0
		@previousRss = process.memoryUsage().rss
		@maxRss = process.memoryUsage().rss
		@retryOptions =
			factor: 1
			minTimeout: 30000

		@exhausted = false
		@threads = 100
		@concurrency = @threads
		@lock = false

	init: ->
		@cursor = @Repositories.find({}).limit(@to - @from).skip(@from)
		@reportInterval = Math.ceil((@to - @from) / 100 / 10)  # every 0.1%
		@current = @from
		# do NOT return the cursor itself (because of its own .then method)!
		true

	run: ->
		new Promise (resolve, reject) =>
			@next(resolve, reject)

	next: (resolve, reject) ->
		if @concurrency > 0
			@concurrency--

			if not @lock
				Promise.bind @
				.tap -> @lock = true
				.then ->
					@cursor.next()
					.catch (error) ->
						throw error if error.message isnt "cursor is exhausted"
				.finally -> @lock = false
				.then (repository) ->
					# cursor returns "undefined" when exhausted (but only once)
					if repository
						# plan the next iteration
						process.nextTick => @next(resolve, reject)

						Promise.bind @
						.then -> @handleRepository(repository)
						.then ->
							@current++
							@usage() if (@current % @reportInterval) is 0
						.finally ->
							@free(resolve)
							process.nextTick => @next(resolve, reject) if not @exhausted
					else
						@exhausted = true
						@free(resolve)

	usage: ->
		currentRss = process.memoryUsage().rss
		@maxRss = Math.max(@maxRss, currentRss)
		@logger.info "FilesLoader:run", "#{@current}/#{@to}", "(memory @ max: #{parseInt(@maxRss / 1024, 10)} KB, current: #{parseInt(currentRss / 1024, 10)} KB; change: #{if currentRss > @previousRss then "+" else ""}#{parseInt((currentRss - @previousRss) / 1024, 10)} KB)"
		@previousRss = currentRss

		completed = (@current - @begin) / (@end - @begin)
		timeSpent = new Date().getTime() - @timestamp

		estimated = timeSpent / completed - timeSpent
		seconds = Math.floor(estimated / 1000) % 60
		minutes = Math.floor(estimated / 1000 / 60) % 60
		hours = Math.floor(estimated / 1000 / 60 / 60)
		@logger.info "Estimated time: #{hours}h #{minutes}m #{seconds}s (current: #{@current}, begin: #{@begin}, completed: #{completed}, timeSpent:#{timeSpent}), estimated:#{estimated}"

	free: (resolve) ->
		@concurrency++
		if @exhausted and (@concurrency is @threads)
			@logger.info "FilesLoader:finished. Request time #{@networkTime}ms, processing time #{@mongoTime}ms, max request time #{@maxNetworkTime}"
			resolve()

	handleRepository: (repository) ->
		requestTime = undefined
		processingTime = undefined

		Promise.bind @
		.tap -> requestTime = new Date()
		.then -> @_getPackageFile repository
		.tap -> diff = new Date() - requestTime; @networkTime += diff; @maxNetworkTime = Math.max(@maxNetworkTime, diff)
		.tap -> processingTime = new Date()
		.then (body) ->
			if body
				@parse body
				.then (json) =>
					if json
						promiseRetry (retry, number) =>
							@updateFile(repository, json)
							.catch (error) ->
								retry(error)
		.catch (error) ->
			@logger.error error.message, _.extend({stack: error.stack}, error.details)
			process.exit(1) # to catch and retry from outside
		.tap -> @mongoTime += new Date() - processingTime
		.thenReturn(true)

	parse: (body) ->
		body = body.replace(/,(\s*)(]|})/g, '$1$2') # fix trailing comma for arrays/objects (unable to parse it!)
		Promise.try -> JSON.parse body
		.catch (error) => @logger.warn "FilesLoader:parse:invalidJSON", {body: body}

	updateFile: (repository, content) ->
		packages = _.uniq _.union _.keys(content['dependencies'] or {}), _.keys(content['devDependencies'] or {})
		@Files.insert @Files.buildObject
			name: FILE
			manager: MANAGER
			url: repository.url
			packages: packages

	_getPackageFile: (repository) ->
		url = repository.url.replace("github.com", "raw.githubusercontent.com") + "/master/#{FILE}"
		@_request {url}

	_request: (options) ->
		promiseRetry (retry, number) =>
			Promise.bind(@)
			.then -> @_requestAsync options
			.catch (error) ->
				# GitHub always returns statusCode=500 on the following files:
				# https://raw.githubusercontent.com/sergeyzavadski/libpropeller/master/package.json
				# https://raw.githubusercontent.com/lukelove/Pipes/master/package.json
				if number > 5 and error.details?.statusCode is 500 # sometimes GitHub just can't serve the file
					@logger.warn "FilesLoader:_request:skip", _.extend({url: options.url})
					return
				@logger.warn "FilesLoader:_request:retry", _.extend({attempt: number, url: options.url, error: error.stack}, error.details)
				retry(error)
		, @retryOptions

	_requestAsync: (options) ->
		Promise.bind @
		.then -> requestAsync(options)
		.spread (response, body) ->
			switch response.statusCode
				when 200
					return body
				when 404
					return ""
				else
					error = new Error("FilesLoader:_requestAsync:invalidStatusCode")
					error.details =
						statusCode: response.statusCode
						headers: response.headers
						body: body
					throw error
