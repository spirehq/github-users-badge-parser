https = require 'https'

module.exports = class
	constructor: (settings) ->
		@settings = settings

	getRepositories: (handle) ->
		new Promise (resolve, reject) =>
			response = ''

			req = https.get
				hostname: 'api.github.com'
				headers:
					"User-Agent": ''
					"Authorization": "token #{@settings.token}"
				path: "/repositories"
				, (res) ->
					response = ''

					res.on 'data', (chunk) =>
						response += chunk

					res.on 'end', =>
						response = JSON.parse response
						resolve handle response

			req.on 'error', (e) ->
				console.error e
				reject {error: e}

			req.end()
