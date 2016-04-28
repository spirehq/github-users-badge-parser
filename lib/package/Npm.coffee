https = require 'https'
Promise = require 'bluebird'
PackagesClass = require '../model/Packages.coffee'
FilesClass = require '../model/Files.coffee'
_ = require 'underscore'
promiseRetry = require 'promise-retry'

FILE = 'package.json'
MANAGER = 'npm'

module.exports = class
	constructor: (dependencies) ->
		@Packages = new PackagesClass(dependencies.mongodb)
		@Files = new FilesClass(dependencies.mongodb)
		@retryOptions = 
			factor: 1
			minTimeout: 30000

	run: (repository) ->
		Promise.bind @
		.then -> @_getPackageFile repository
		.then (content) ->
			if content
				@parse content
				.then (json) => Promise.join @updatePackage(repository, json), @updateFile(repository, json)
				.catch (e) -> console.log "Error in Npm module. Skip this repository", e, content

	parse: (data) ->
		data = data.replace(/,(\s*)]/, '$1]') # fix trailing comma for arrays (unable to parse it!)
		Promise.try -> JSON.parse data

	updatePackage: (repository, content) ->
		@Packages.upsert {name: content['name'], manager: MANAGER, url: repository.html_url}

	updateFile: (repository, content) ->
		packages = _.union _.keys(content['dependencies'] or {}), _.keys(content['devDependencies'] or {})
		@Files.upsert
			name: FILE
			manager: MANAGER
			url: repository.html_url
			packages: packages

	_getPackageFile: (repository) ->
		new Promise (resolve, reject) =>
			root = repository['full_name']
			path = "/#{root}/master/#{FILE}"
			@_request {path}, resolve, reject

	_request: (options, resolve, reject) ->
		promiseRetry (retry, number) =>
			@_promisedRequest options, resolve, reject
			.catch (e) -> console.log "Retry Npm #{number}", e; retry()
		, @retryOptions

	_promisedRequest: (options, resolve, reject) ->
		request = https.get _.extend(
				hostname: 'raw.githubusercontent.com'
			, options)
		, (response) =>
			if response.statusCode is 200
				accumulator = ''
				response.on 'data', (chunk) -> accumulator += chunk
				response.on 'end', -> resolve accumulator
				response.on 'error', (error) -> console.error "Error in Npm", error; reject {error}
			else
				resolve null

		request.on 'error', (error) -> console.error console.error "Error in Npm (outer)", error; reject {error}
		request.end()
