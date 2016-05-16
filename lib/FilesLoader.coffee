https = require 'https'
Promise = require 'bluebird'
requestAsync = Promise.promisify((require "request"), {multiArgs: true})
FilesClass = require './model/Files.coffee'
RepositoriesClass = require './model/Repositories.coffee'
_ = require 'underscore'
promiseRetry = require 'promise-retry'
sprintf = require("sprintf-js").sprintf

moment = require "moment"
require "moment-duration-format"

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
		@networkCounter = 0
		@networkTime = 0
		@maxNetworkTime = 0
		@mongoCounter = 0
		@mongoTime = 0
		@maxMongoTime = 0
		@previousRss = process.memoryUsage().rss
		@maxRss = process.memoryUsage().rss
		@retryOptions =
			factor: 1
			minTimeout: 30000
		@pollingInterval = 50 # ms

		@repositories = [] # filled in init()
		@exhausted = false

	init: ->
		@repositories = (null for i in [0..(Math.min(100, @to - @from) - 1)]) # 100 null's
		@cursor = @Repositories.find({}).limit(@to - @from).skip(@from)
		@reportInterval = Math.ceil((@to - @from) / 100 / 10)	# every 0.1%
		@current = @from
		# do NOT return the cursor itself (because of its own .then method)!
		true

	run: ->
		Promise.bind(@)
		.then -> @logger.info "FilesLoader:started"
		.then ->
			new Promise (resolve, reject) =>
				process.nextTick => @initRepositoryLoader().catch(reject)
				process.nextTick => @initFileLoaderThreads().catch(reject)
				process.nextTick => @initExitConditionChecker().then(resolve).catch(reject) # needed to call "resolve"
		.then -> @logger.info "FilesLoader:finished", "(request time: #{@networkTime}ms, processing time: #{@mongoTime}ms, max request time: #{@maxNetworkTime}ms)"

	initRepositoryLoader: ->
		@while(
			(=> @shouldRun() and not @exhausted),
			(=> @loadRepositories().delay(@pollingInterval))
		)

	loadRepositories: ->
#		console.log "loadRepositories"
		@while(
			(=> @shouldRun() and not @exhausted and ~@repositories.indexOf(null)), # extra "not @exhausted" condition is necessary if there are less than 100 repositories in DB
			(=> @loadRepository())
		)

	loadRepository: ->
#		console.log "loadRepository"
		Promise.bind @
		.then -> @cursor.next()
#		.tap -> console.log "cursor.next"
		# race condition here. Two process.nextTick callbacks may call next, which will result in two cursor.next calls
		# true solution: don't call .next() until the previous one had finished; but that's not possible, because .next() returns a promise
		# need sync "dealing" of next objects
		.then (repository) ->
			# cursor returns "undefined" when exhausted (but only once)
			if repository
				index = @repositories.indexOf(null)
#				console.log "Loaded #{repository._id} at #{index}"
				if ~index
					@repositories[index] = repository
				else
					error = new Error("FilesLoader:loadRepositories:indexNotFound")
					error.details =
						index: index
						repositories: @repositories
					throw error
			else
				@exhausted = true
				console.log @repositories.length
				console.log "@exhausted = true"

	initFileLoaderThreads: ->
		Promise.map(
			[0..(@repositories.length - 1)],
			(index) =>
				@while(
					(=> @shouldRun()),
					(=> @loadFile(index).delay(@pollingInterval))
				)
		)

	loadFile: (index) ->
#		console.log "loadFile at #{index}"
		return Promise.bind(@) if not @repositories[index] # it's possible for loadFile to be called before loadRepositories
		Promise.bind(@)
		.then -> @handleRepository(@repositories[index])
		.then ->
			@current++
			@usage() if (@current % @reportInterval) is 0
			@repositories[index] = null

	usage: ->
		currentRss = process.memoryUsage().rss
		@maxRss = Math.max(@maxRss, currentRss)

		completed = (@current - @begin) / (@end - @begin)
		timeSpent = new Date().getTime() - @startedAt
		estimatedFinishedAt = timeSpent / completed - timeSpent

		@logger.info "FilesLoader:run", "#{@current}/#{@to}", "finishing in #{moment.duration(estimatedFinishedAt).format("h[h] mm[m] ss[s]")}", "(network time @ mean: #{parseInt(@networkTime / @networkCounter, 10)}ms, max: #{@maxNetworkTime}ms; mongo time @ mean: #{parseInt(@mongoTime / @mongoCounter, 10)}ms, max: #{@maxMongoTime}ms; current: #{@current}, begin: #{@begin}, end: #{@end}, completed: #{sprintf("%.2f", completed * 100)}%, timeSpent: #{moment.duration(timeSpent).format("h[h] mm[m] ss[s]")}, memory: #{parseInt(currentRss / 1024, 10)} / #{parseInt(@maxRss / 1024, 10)} KB)"
		@previousRss = currentRss

	handleRepository: (repository) ->
		networkStartedAt = undefined
		mongoStartedAt = undefined

		Promise.bind @
		.tap -> networkStartedAt = new Date()
		.then -> @_getPackageFile repository
		.tap -> diff = new Date() - networkStartedAt; @networkTime += diff; @maxNetworkTime = Math.max(@maxNetworkTime, diff); @networkCounter++
		.tap -> mongoStartedAt = new Date()
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
		.tap -> diff = new Date() - mongoStartedAt; @mongoTime += diff; @maxMongoTime = Math.max(@maxMongoTime, diff); @mongoCounter++
		.thenReturn(true)

	parse: (body) ->
		body = body.replace(/,(\s*)(]|})/g, '$1$2') # fix trailing comma for arrays/objects (unable to parse it!)
		Promise.try -> JSON.parse body
		.catch (error) => # swallow the error # @logger.warn "FilesLoader:parse:invalidJSON", {body: body}

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

	initExitConditionChecker: ->
		@while(
			(=> @shouldRun()),
			(=> Promise.delay(500))
		)

	shouldRun: ->
		not @exhausted or _.without(@repositories, null).length

	while: (condition, action) ->
		new Promise (resolve, reject) =>
			iterate = ->
				if !condition()
					return resolve()
				action().catch(reject).then(-> process.nextTick(iterate))
			process.nextTick(iterate)
