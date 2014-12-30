chai = require('chai')
require("mocha-as-promised")
chai.use require('chai-as-promised')
nock = require('nock')
request = require('supertest')
sinon = require('sinon')
chai.use require('sinon-chai')
chai.Should()
Q = require('q')
pt = require('./../models/issuetrackers/pivotaltracker')

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
  app.use(bodyParser.json())
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
          .reply(200, {review_request: {id: "1234", bugs_closed: ["1/stories/1"]}})

          rbReq.end (err, res) ->
            if err then throw err
            setTimeout ->
              routes.issueTrackers.pivotaltracker.linkReviewRequest
                .should.have.been.called
              done()
            , 0


  describe "/rb/review-request-closed", ->

    afterEach ->
      nock.cleanAll()

    describe "when a POST request is received", ->

      payload = null
      rbReq = null

      beforeEach ->
        payload = JSON.stringify({
          review_request_id: 42
          type: 'D'
        })

        rbReq = request(app)
          .post('/rb/review-request-closed')
          .type("form")
          .send("payload=#{payload}")

        # Stub out the discarding logic (is tested in the RB module).
        for id, tracker of routes.issueTrackers
          _sb.stub(tracker, 'discardReviewRequest').returns Q()

      it "calls the discardReviewRequest method on RB model", (done) ->
        nock("#{RB_URL}:443")
          .get("/api/review-requests/42/")
          .reply(200, {review_request: {id: "1234", bugs_closed: ["SF-1"]}})

          rbReq.end (err, res) ->
            if err then throw err
            setTimeout ->
              routes.issueTrackers.jira.discardReviewRequest
                .should.have.been.calledWith('SF-1', "1234")
              done()
            , 100

  describe "/pt/activity", ->

    _client = null

    beforeEach ->
      _client = {
        getStory: sinon.stub()
        updateStory: sinon.stub()
      }
      pt.useClient(_client)

    afterEach ->
      nock.cleanAll()

    describe "when a story label change activity is received", ->

      it "emits 'labels' event", (done) ->
        story = {
          id: 1
          project_id: 1
        }

        _client.getStory.returns(Q(story))

        original_labels = ['foo']
        original_label_ids = [10]
        new_labels = ['foo', 'bar']
        new_label_ids = [10, 11]

        body = {
          kind: 'story_update_activity'
          changes: [
            {
              kind: 'story',
              id: 1,
              original_values: {
                labels: original_labels
                label_ids: original_label_ids
              }
              new_values: {
                labels: new_labels
                label_ids: new_label_ids
              }
            }
          ]
          project: {
            id: 1
          }
        }

        event = {
          story: story,
          original_labels: original_labels
          original_label_ids: original_label_ids
          new_labels: new_labels
          new_label_ids: new_label_ids
        }

        _sb.stub(pt.activity, 'emit').returns()

        request(app)
          .post('/pt/activity')
          .send(body)
          .expect(202)
          .end (err, res) ->
            if err then throw err
            setTimeout ->
              _client.getStory.should.have.been.calledWith(1, 1)
              pt.activity.emit.should.have.been.calledWith('labels', event)
              done()
            , 100
