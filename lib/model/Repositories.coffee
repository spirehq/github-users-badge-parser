Promise = require 'bluebird'
Match = require 'mtr-match'

module.exports = class
	constructor: (mongodb) ->
		@mongodb = mongodb
		@collection = mongodb.collection("Repositories")

	upsert: (raw) ->
		object = @buildObject raw

		Promise.bind @
		.then -> @findByObject(object)
		.then (found) -> if found then @update(object) else @insert(object)

	insert: (object) ->
		@collection.insert object

	update: (object) ->
		@collection.update {url: object.url}, {$set: {updatedAt: new Date()}}

	findByObject: (object) ->
		@collection.findOne {url: object.url}

	buildObject: (data) ->
		Match.check data, Match.ObjectIncluding
			html_url: String

		now = new Date()

		url: data.html_url
		users: 0
		createdAt: now
		updatedAt: now
