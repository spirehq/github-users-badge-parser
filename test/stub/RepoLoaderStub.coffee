RepoLoader = require '../../lib/RepoLoader.coffee'

MAX_PAGES  = 3

module.exports = class extends RepoLoader
	constructor: ->
		super

		@limit = MAX_PAGES
		
	_getNextRepositoryPage: ->
		super if --@limit
