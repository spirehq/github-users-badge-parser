https = require 'https'
Promise = require 'bluebird'
_ = require 'underscore'
RepositoriesClass = require './model/Repositories.coffee'
Npm = require './package/Npm.coffee'

module.exports = class
	constructor: (settings, dependencies) ->
		@settings = settings
		@Repositories = new RepositoriesClass(dependencies.mongodb)
		@handlers = [
			new Npm(dependencies)
		]
		
	syncRepositories: ->
		@getRepositories (repositories) => Promise.resolve(repositories).bind(@).map @handleRepository

	handleRepository: (repository) ->
		Promise.all [
			@Repositories.upsert repository
			Promise.all(handler.run repository for handler in @handlers)
		]
			
	getRepositories: (handler) ->
		@_request {path: '/repositories'}, handler

	_getNextRepositoryPage: (response, handler) ->
		# example '<https://api.github.com/repositories?since=367>; rel="next", <https://api.github.com/repositories{?since}>; rel="first"'
		link = response.headers.link

		if link
			url = link.match(/^<.+(\/repositories.+)>; rel="next"/)[1]
			@_request {path: url}, handler if url

	_request: (options, handler) ->
		new Promise (resolve, reject) =>
			request = https.get _.extend(
				hostname: 'api.github.com'
				headers:
					'User-Agent': ''
					'Authorization': "token #{@settings.token}"
				, options)
			, (response) =>
				next = @_getNextRepositoryPage response, handler
				accumulator = ''
				response.on 'data', (chunk) -> accumulator += chunk
				response.on 'end', ->
					accumulator = JSON.parse accumulator
					resolve Promise.join(handler(accumulator), next)

			request.on 'error', (error) -> console.error error; reject {error}
			request.end()
