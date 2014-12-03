chai = require('chai')
require("mocha-as-promised")
chai.use require('chai-as-promised')
nock = require('nock')
request = require('supertest')
sinon = require('sinon')
chai.use require('sinon-chai')
chai.Should()
Q = require('q')


describe "parseStoryId", ->

  rb = require('./index')

  it "returns story id for GitFlow-1-style review requests", ->
    rb.parseStoryId({
      branch: "feature/123456/human-readable-string"
    }).should.equal("123456")

  it "returns story id for superseded SalsaFlow-style review requests", ->
    rb.parseStoryId({
      branch: "TEST-1"
    }).should.equal("TEST-1")

  it "returns story id for new SalsaFlow-style review requests", ->
    rb.parseStoryId({
      bugs_closed: ['TEST-1']
    }).should.equal("TEST-1")

  it "returns `null` for review requests with no bugs and no branch", ->
    (rb.parseStoryId({
      bugs_closed: []
      branch: ''
    }) == null).should.be.true

  it "returns `null` for review requests with multiple bugs", ->
    (rb.parseStoryId({
      bugs_closed: ['TEST-1', 'TEST-2']
    }) == null).should.be.true
