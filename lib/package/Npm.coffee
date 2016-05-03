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
		.then (body) ->
			if body
				@parse body
				.then (json) => @updateFile(repository, json)
				.catch (error) => @logger.warn "Npm:parse:invalidJSON", {body: body}
		.catch (error) -> @logger.error error.message, _.extend({stack: error.stack.split("\n")}, error.details)

	parse: (body) ->
		body = body.replace(/,(\s*)(]|})/g, '$1$2') # fix trailing comma for arrays/objects (unable to parse it!)
		Promise.try -> JSON.parse body

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
			Promise.bind(@)
			.then -> @_requestAsync options
			.catch (error) ->
				@logger.warn "Npm:_request:retry", {number: number, url: options.url}
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
					error = new Error("Npm:_requestAsync:invalidStatusCode")
					error.details =
						statusCode: response.statusCode
						headers: response.headers
						body: body
					throw error
