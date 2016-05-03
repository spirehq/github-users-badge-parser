https = require 'https'
Promise = require 'bluebird'
requestAsync = Promise.promisify((require "request"), {multiArgs: true})
PackagesClass = require '../model/Packages.coffee'
FilesClass = require '../model/Files.coffee'
_ = require 'underscore'
promiseRetry = require 'promise-retry'

FILE = 'package.json'
MANAGER = 'npm'

module.exports = class
	constructor: (dependencies) ->
		@logger = dependencies.logger
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
		data = data.replace(/,(\s*)(]|})/g, '$1$2') # fix trailing comma for arrays/objects (unable to parse it!)
		Promise.try -> JSON.parse data

	updatePackage: (repository, content) ->
		@Packages.upsert {name: content['name'], manager: MANAGER, url: repository.html_url}

	updateFile: (repository, content) ->
		packages = _.uniq _.union _.keys(content['dependencies'] or {}), _.keys(content['devDependencies'] or {})
		@Files.upsert
			name: FILE
			manager: MANAGER
			url: repository.html_url
			packages: packages

	_getPackageFile: (repository) ->
		root = repository['full_name']
		url = "https://raw.githubusercontent.com/#{root}/master/#{FILE}"
		@_request {url}

	_request: (options) ->
		promiseRetry (retry, number) =>
			@_requestAsync options
			.catch (e) -> console.log "Retry Npm #{number}", e; retry()
		, @retryOptions

	_requestAsync: (options) ->
		requestAsync(options)
		.spread (response, body) ->
			switch response.statusCode
				when 200
					return body
				when 404
					return ""
				else
					@logger.error "Npm: request error, status code: #{response.statusCode}"
					@logger.error response.headers
					@logger.error body
					throw new Error()
