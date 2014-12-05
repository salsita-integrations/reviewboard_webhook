chai = require('chai')
require("mocha-as-promised")
chai.use require('chai-as-promised')
nock = require('nock')
request = require('supertest')
sinon = require('sinon')
chai.use require('sinon-chai')
chai.Should()
Q = require('q')
_ = require('lodash')

config = require('config')

_sb = null

beforeEach ->
  _sb = sinon.sandbox.create()

afterEach ->
  _sb.restore()


__jira = {
  getRemoteLinks: ->
  findIssue: ->
  transitionIssue: ->
  deleteRemoteLink: ->
}
require('jira').JiraApi = -> __jira


describe "JIRA issue tracker", ->

  jira = require('./jira')

  describe "areAllReviewsApproved", ->

    it "returns true when all linked remote review requests are approved", ->
      links = [object: status: resolved: true]
      _sb.stub(__jira, 'getRemoteLinks').yields(null, links)
      jira.areAllReviewsApproved('TEST-1').should.eventually.be.true

    it "returns false when any linked remote review requests is not approved", ->
      links = [
        object: status: resolved: false,
        object: status: resolved: true
      ]
      _sb.stub(__jira, 'getRemoteLinks').yields(null, links)
      jira.areAllReviewsApproved('TEST-1').should.eventually.be.false

  describe "transitionToNextState", ->

    it "returns a rejected promise if the issue is in an invalid state", ->
      issue = {
        fields:
          issuetype:
            id: 42
          status:
            id: "INVALID STATE ID"
            name: "test state"
      }
      _sb.stub(__jira, 'findIssue').yields(null, issue)
      jira.transitionToNextState('TEST-1').should.be.rejected

    it "transitions the issue when state is valid", ->
      rules = config.services.jira.transitions
      stateId = _.first _.keys rules
      issue = {
        fields:
          issuetype:
            id: stateId
          status:
            id: rules[stateId].required_state
            name: "test state"
      }
      _sb.stub(__jira, 'findIssue').yields(null, issue)
      _sb.stub(__jira, 'transitionIssue').yields(null, {})
      jira.transitionToNextState('TEST-1').then ->
        __jira.transitionIssue.should.have.been.calledWith(
          'TEST-1', {transition: id: rules[stateId].transition})

  describe "discardReviewRequest", ->

    it "deletes the linked remote issue", ->
      links = [globalId: 'http://global.linked.issue.id', object: title: "r1234"]
      _sb.stub(__jira, 'getRemoteLinks').yields(null, links)
      _sb.stub(__jira, 'deleteRemoteLink').yields(null, {})

      jira.discardReviewRequest('SF-1', '1234')
        .then ->
          __jira.deleteRemoteLink.should.have.been.calledWith(
            'SF-1', 'http://global.linked.issue.id')
