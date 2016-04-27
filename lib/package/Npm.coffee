https = require 'https'
Promise = require 'bluebird'
PackagesClass = require '../model/Packages.coffee'
FilesClass = require '../model/Files.coffee'
_ = require 'underscore'

FILE = 'package.json'
MANAGER = 'npm'

module.exports = class
	constructor: (dependencies) ->
		@Packages = new PackagesClass(dependencies.mongodb)
		@Files = new FilesClass(dependencies.mongodb)

	run: (repository) ->
		Promise.bind @
		.then -> @_getPackageFile repository
		.then (content) ->
			if content
				content = JSON.parse content
				@Packages.upsert {name: content['name'], manager: MANAGER, url: repository.html_url}
				packages = _.union _.keys(content['dependencies']), _.keys(content['devDependencies'])
				@Files.upsert
					name: FILE
					manager: MANAGER
					url: repository.html_url
					packages: packages

	_getPackageFile: (repository) ->
		new Promise (resolve, reject) =>
			root = repository['full_name']
			path = "/#{root}/master/#{FILE}"
			@_fileRequest {path}, resolve, reject

	_fileRequest: (options, resolve, reject) ->
		request = https.get _.extend(
				hostname: 'raw.githubusercontent.com'
			, options)
		, (response) =>
			if response.statusCode is 200
				accumulator = ''
				response.on 'data', (chunk) -> accumulator += chunk
				response.on 'end', -> resolve accumulator
				response.on 'error', (error) -> console.error error; reject {error}
			else
				resolve null

		request.on 'error', (error) -> console.error error; reject {error}
		request.end()
