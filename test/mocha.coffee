process.env.ROOT_DIR ?= process.cwd()

chai = require "chai"
global.should = chai.should()
#chai.config.includeStack = true

chaiAsPromised = require "chai-as-promised"
chai.use(chaiAsPromised)

chaiThings = require "chai-things"
chai.use(chaiThings)

chaiSinon = require "sinon-chai"
chai.use(chaiSinon)

global.sinon = require("sinon")

Promise = require "bluebird"
Promise.longStackTraces()

global.nock = require "nock"
global.nock.back.fixtures = "#{process.env.ROOT_DIR}"
# override default to be "lockdown" instead of "dryrun", otherwise we run into rate limits pretty soon
# run "NOCK_BACK_MODE=record mocha path/to/your/test.coffee" manually to record API responses
global.nock.back.setMode(process.env.NOCK_BACK_MODE or "lockdown")
