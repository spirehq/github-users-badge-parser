https = require 'https'
Promise = require 'bluebird'
_ = require 'underscore'
requestAsync = Promise.promisify((require "request"), {multiArgs: true})
RepositoriesClass = require './model/Repositories.coffee'
promiseRetry = require 'promise-retry'

module.exports = class
	constructor: (settings, dependencies) ->
		@settings = settings
		@logger = dependencies.logger
		@Repositories = new RepositoriesClass(dependencies.mongodb)
		@url = 'https://api.github.com/repositories'
		@previousRss = process.memoryUsage().rss
		@maxRss = process.memoryUsage().rss
		
	run: ->
		@_request()

	_request: ->
		return if not @url
		currentRss = process.memoryUsage().rss
		@maxRss = Math.max(@maxRss, currentRss)
		@logger.info "RepositoriesLoader:_request", @url, "(memory @ max: #{parseInt(@maxRss / 1024, 10)} KB, current: #{parseInt(currentRss / 1024, 10)} KB; change: #{if currentRss > @previousRss then "+" else ""}#{parseInt((currentRss - @previousRss) / 1024, 10)} KB)"
		@previousRss = currentRss
		process.nextTick =>
			Promise.bind(@)
			.then ->
				promiseRetry (retry, number) =>
					@_requestAsync()
					.catch (error) ->
						@logger.warn "RepositoriesLoader:_request:retry", _.extend({attempt: number, url: @url, error: error.stack}, error.details)
						retry()
				, @retryOptions
			.then ->
				@_request()

	_requestAsync: ->
		Promise.bind @
		.then -> requestAsync(
			url: @url
			headers:
				'User-Agent': ''
				'Authorization': "token #{@settings.github.token}"
		)
		.spread (response, body) ->
			switch response.statusCode
				when 200
					Promise.bind(@)
					.then -> @parse(body)
					.map (repository) -> @Repositories.upsert(repository)
					.return [response, body]
				else
					error = new Error("RepositoriesLoader:_requestAsync:invalidStatusCode")
					error.details =
						statusCode: response.statusCode
						headers: response.headers
						body: body
					throw error
		.spread (response, body) ->
			@_getNextRepositoryPage(response)

	parse: (data) ->
		Promise.try -> JSON.parse data

	_getNextRepositoryPage: (response) ->
		# example '<https://api.github.com/repositories?since=367>; rel="next", <https://api.github.com/repositories{?since}>; rel="first"'
		link = response.headers.link
		if link
			@url = link.match(/^<(.+\/repositories.+)>; rel="next"/)[1]
		else
			@url = "" # this will break the loop

