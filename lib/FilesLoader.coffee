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
		@limit = 100
		@skip = 0
		@retryOptions = 
			factor: 1
			minTimeout: 30000
		@previousRss = process.memoryUsage().rss
		@maxRss = process.memoryUsage().rss

	run: ->
		currentRss = process.memoryUsage().rss
		@maxRss = Math.max(@maxRss, currentRss)
		@logger.info "FilesLoader:run", @skip, "(memory @ max: #{parseInt(@maxRss / 1024, 10)} KB, current: #{parseInt(currentRss / 1024, 10)} KB; change: #{if currentRss > @previousRss then "+" else ""}#{parseInt((currentRss - @previousRss) / 1024, 10)} KB)"
		@previousRss = currentRss
		Promise.bind @
		.then -> @Repositories.find().limit(@limit).skip(@skip)
		.map @handleRepository
		.then (results) ->
			return if not results.length
			@skip += @limit
			process.nextTick => @run()

	handleRepository: (repository) ->
		Promise.bind @
		.then -> @_getPackageFile repository
		.then (body) ->
			if body
				@parse body
				.then (json) => @updateFile(repository, json)
				.catch (error) => @logger.warn "Npm:parse:invalidJSON", {body: body}
		.catch (error) -> @logger.error error.message, _.extend({stack: error.stack}, error.details)
		.thenReturn(true)

	parse: (body) ->
		body = body.replace(/,(\s*)(]|})/g, '$1$2') # fix trailing comma for arrays/objects (unable to parse it!)
		Promise.try -> JSON.parse body

	updateFile: (repository, content) ->
		packages = _.uniq _.union _.keys(content['dependencies'] or {}), _.keys(content['devDependencies'] or {})
		@Files.upsert
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
				@logger.warn "Npm:_request:retry", _.extend({attempt: number, url: options.url, error: error.stack}, error.details)
				retry()
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