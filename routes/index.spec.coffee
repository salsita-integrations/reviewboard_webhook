chai = require('chai')
require("mocha-as-promised")
chai.use require('chai-as-promised')
nock = require('nock')
request = require('supertest')
sinon = require('sinon')
chai.use require('sinon-chai')
chai.Should()
Q = require('q')

config = require('config')

RB_URL = config.services.reviewboard.url


_sb = null

beforeEach ->
  _sb = sinon.sandbox.create()

afterEach ->
  _sb.restore()

describe "routes", ->

  routes = require('./index')
  express = require('express')
  bodyParser = require('body-parser')

  app = express()
  app.use(bodyParser.urlencoded())

  app.use '/', routes.router

  describe "/rb/review-request-published", ->

    afterEach ->
      nock.cleanAll()

    describe "when a POST request is received", ->

      payload = null
      rbReq = null

      beforeEach ->
        payload = JSON.stringify({
          new: false
          review_request_id: 42
        })

        rbReq = request(app)
          .post('/rb/review-request-published')
          .type("form")
          .send("payload=#{payload}")

        for id, tracker of routes.issueTrackers
          _sb.stub(tracker, 'linkReviewRequest').returns Q()

      it "sends HTTP 422 if review request cannot be determined", (done) ->
        request(app)
          .post('/rb/review-request-published')
          .send({})
          .expect(422, done)

      it "links review request with a JIRA story", (done) ->
        nock("#{RB_URL}:443")
          .get("/api/review-requests/42/")
          .reply(200, {review_request: {id: "1234", bugs_closed: ["SF-1"]}})

          rbReq.end (err, res) ->
            if err then throw err
            setTimeout ->
              routes.issueTrackers.jira.linkReviewRequest
                .should.have.been.called
              done()
            , 100

      it "links review request with a PT story", (done) ->
        nock("#{RB_URL}:443")
          .get("/api/review-requests/42/")
          .reply(200, {review_request: {id: "1234", bugs_closed: ["123456"]}})
        
          rbReq.end (err, res) ->
            if err then throw err
            setTimeout ->
              routes.issueTrackers.pivotaltracker.linkReviewRequest
                .should.have.been.called
              done()
            , 0


describe "parseStoryId", ->

  routes = require('./index')

  it "returns story id for GitFlow-1-style review requests", ->
    routes.parseStoryId({
      branch: "feature/123456/human-readable-string"
    }).should.equal("123456")

  it "returns story id for superseded SalsaFlow-style review requests", ->
    routes.parseStoryId({
      branch: "TEST-1"
    }).should.equal("TEST-1")

  it "returns story id for new SalsaFlow-style review requests", ->
    routes.parseStoryId({
      bugs_closed: ['TEST-1']
    }).should.equal("TEST-1")

  it "returns `null` for review requests with no bugs and no branch", ->
    (routes.parseStoryId({
      bugs_closed: []
      branch: ''
    }) == null).should.be.true

  it "returns `null` for review requests with multiple bugs", ->
    (routes.parseStoryId({
      bugs_closed: ['TEST-1', 'TEST-2']
    }) == null).should.be.true
