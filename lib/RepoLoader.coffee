https = require 'https'
Promise = require 'bluebird'
_ = require 'underscore'

module.exports = class
	constructor: (settings) ->
		@settings = settings

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
				response.on 'data', (chunk) => accumulator += chunk
				response.on 'end', =>
					accumulator = JSON.parse accumulator
					resolve Promise.join(handler(accumulator), next)

			request.on 'error', (e) ->
				console.error e
				reject {error: e}

			request.end()
