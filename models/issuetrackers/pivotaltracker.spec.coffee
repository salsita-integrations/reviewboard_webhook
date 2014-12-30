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

implementedLabel = config.services.pivotaltracker.implementedLabel
reviewedLabel = config.services.reviewboard.approvedLabel
passedLabel = config.services.pivotaltracker.testingPassedLabel
failedLabel = config.services.pivotaltracker.testingFailedLabel

pt = require('./pivotaltracker')

_client = null

beforeEach ->
  _client = {
    getStory: sinon.stub()
    updateStory: sinon.stub()
  }
  pt.useClient(_client)


describe "Pivotal Tracker issue tracker", ->

  describe "linkReviewRequest", ->

    it "creates the links section in the story description when it is missing", ->
      story = {
        id: 1
        project_id: 1
        description: 'Just implement this and that.'
      }

      update = {
        description: """
Just implement this and that.

----- Review Board Review Requests -----
review 12345 is pending [link](https://review.salsitasoft.com/r/12345)
----------------------------------------
"""
      }

      _client.getStory.returns(Q(story))
      _client.updateStory.returns(Q())

      pt.linkReviewRequest('1/stories/1', '12345', true).then ->
        _client.updateStory.should.have.been.calledWith(1, 1, update)

    it "adds a new link to the existing links section when a RR is published", ->
      story = {
        id: 1
        project_id: 1
        description: """
Just implement this and that.

----- Review Board Review Requests -----
review 12345 is approved [link](https://review.salsitasoft.com/r/12345)
review 23456 is approved [link](https://review.salsitasoft.com/r/23456)
review 34567 is approved [link](https://review.salsitasoft.com/r/34567)
----------------------------------------
"""
      }

      update = {
        description: """
Just implement this and that.

----- Review Board Review Requests -----
review 12345 is approved [link](https://review.salsitasoft.com/r/12345)
review 23456 is approved [link](https://review.salsitasoft.com/r/23456)
review 34567 is approved [link](https://review.salsitasoft.com/r/34567)
review 45678 is pending [link](https://review.salsitasoft.com/r/45678)
----------------------------------------
"""
      }

      _client.getStory.returns(Q(story))
      _client.updateStory.returns(Q())

      pt.linkReviewRequest('1/stories/1', '45678', true).then ->
        _client.updateStory.should.have.been.calledWith(1, 1, update)

    it "does not do anything when the link is already there", ->
      story = {
        description: """
Just implement this and that.

----- Review Board Review Requests -----
review 12345 is approved [link](https://review.salsitasoft.com/r/12345)
review 23456 is approved [link](https://review.salsitasoft.com/r/23456)
review 34567 is pending [link](https://review.salsitasoft.com/r/34567)
----------------------------------------
"""
      }

      _client.getStory.returns(Q(story))
      _client.updateStory.returns(Q())

      pt.linkReviewRequest('1/stories/1', '34567', false).then ->
        _client.updateStory.should.have.not.been.called


  describe "areAllReviewsApproved", ->

    it "returns true when all linked remote review requests are approved", ->
      story = {
        labels: [implementedLabel]
        description: """
Just implement this and that.

----- Review Board Review Requests -----
review 12345 is approved [link](https://review.salsitasoft.com/r/12345)
review 23456 is approved [link](https://review.salsitasoft.com/r/23456)
review 34567 is approved [link](https://review.salsitasoft.com/r/34567)
----------------------------------------
"""
      }

      _client.getStory.returns(Q(story))

      pt.areAllReviewsApproved('1/stories/1').should.eventually.be.true

    it "returns false when any linked remote review requests is not approved", ->
      story = {
        labels: [implementedLabel]
        description: """
Just implement this and that.

----- Review Board Review Requests -----
review 12345 is approved [link](https://review.salsitasoft.com/r/12345)
review 23456 is approved [link](https://review.salsitasoft.com/r/23456)
review 34567 is pending [link](https://review.salsitasoft.com/r/34567)
----------------------------------------
"""
      }

      _client.getStory.returns(Q(story))

      pt.areAllReviewsApproved('1/stories/1').should.eventually.be.false

  it "returns false when the story is not marked as implemented", ->
    story = {
        labels: ['some random label']
    }

    _client.getStory.returns(Q(story))

    pt.areAllReviewsApproved('1/stories/1').should.eventually.be.false

  describe "markReviewAsApproved", ->

    it "marks a pending review request as approved", ->
      story = {
        id: 1
        project_id: 1
        description: """
Just implement this and that.

----- Review Board Review Requests -----
review 12345 is approved [link](https://review.salsitasoft.com/r/12345)
review 23456 is pending [link](https://review.salsitasoft.com/r/23456)
review 34567 is approved [link](https://review.salsitasoft.com/r/34567)
----------------------------------------
"""
      }

      update = {
        description: """
Just implement this and that.

----- Review Board Review Requests -----
review 12345 is approved [link](https://review.salsitasoft.com/r/12345)
review 23456 is approved [link](https://review.salsitasoft.com/r/23456)
review 34567 is approved [link](https://review.salsitasoft.com/r/34567)
----------------------------------------
"""
      }

      _client.getStory.returns(Q(story))
      _client.updateStory.returns(Q())

      pt.markReviewAsApproved('1/stories/1', '23456').then ->
        _client.updateStory.should.have.been.calledWith(1, 1, update)


  describe "transitionToNextState", ->

    it "adds the 'reviewed' label for a story that is started", ->
      story = {
        id: 1
        project_id: 1
        current_state: 'started'
        labels: [
          {id: 1}
          {id: 2}
          {id: 3}
        ]
      }

      update = {
        labels: [
          {id: 1}
          {id: 2}
          {id: 3}
          {name: reviewedLabel}
        ]
      }

      _client.getStory.returns(Q(story))
      _client.updateStory.returns(Q())

      pt.transitionToNextState('1/stories/1').then ->
        _client.updateStory.should.have.been.calledWith(1, 1, update)

    it "does not add the 'reviewed' label when it is already there", ->
      story = {
        id: 1
        project_id: 1
        current_state: 'started'
        labels: [
          {id: 1}
          {id: 2}
          {id: 3}
          {name: reviewedLabel}
        ]
      }

      _client.getStory.returns(Q(story))
      _client.updateStory.returns(Q())

      pt.transitionToNextState('1/stories/1').then ->
        _client.updateStory.should.have.not.been.called

    it "delivers a story that is finished", ->
      story = {
        id: 1
        project_id: 1
        current_state: 'finished'
      }

      update = {
        current_state: 'delivered'
      }

      _client.getStory.returns(Q(story))
      _client.updateStory.returns(Q())

      pt.transitionToNextState('1/stories/1').then ->
        _client.updateStory.should.have.been.calledWith(1, 1, update)


  describe "discardReviewRequest", ->

    it "removes the link from the story description when found", ->
      story = {
        id: 1
        project_id: 1
        description: """
Just implement this and that.

----- Review Board Review Requests -----
review 12345 is approved [link](https://review.salsitasoft.com/r/12345)
review 23456 is pending [link](https://review.salsitasoft.com/r/23456)
review 34567 is pending [link](https://review.salsitasoft.com/r/34567)
----------------------------------------
"""
      }

      update = {
        description: """
Just implement this and that.

----- Review Board Review Requests -----
review 12345 is approved [link](https://review.salsitasoft.com/r/12345)
review 34567 is pending [link](https://review.salsitasoft.com/r/34567)
----------------------------------------
"""
      }

      _client.getStory.returns(Q(story))
      _client.updateStory.returns(Q())

      pt.discardReviewRequest('1/stories/1', '23456').then ->
        _client.updateStory.should.have.been.calledWith(1, 1, update)


  describe "tryPassTesting", ->

    it "updates the story when the conditions are met", ->
      event = {
        story: {
          id: 1
          project_id: 1
          current_state: 'started'
        }
        original_labels: [
          'foobar', reviewedLabel
        ]
        new_labels: [
          'foobar', reviewedLabel, passedLabel
        ]
      }

      update = {
        current_state: 'finished'
        labels: ['foobar']
      }

      _client.updateStory.returns(Q())

      pt.tryPassTesting(event).then ->
        _client.updateStory.should.have.been.calledWith(1, 1, update)

    it "does not update the story when the conditions are not met", ->
      event = {
        story: {
          id: 1
          project_id: 1
          current_state: 'started'
        }
        original_labels: [
          'foobar', reviewedLabel
        ]
        new_labels: [
          'foobar', reviewedLabel, failedLabel
        ]
      }

      _client.updateStory.returns(Q())

      pt.tryPassTesting(event).then ->
        _client.updateStory.should.have.not.been.called

  describe "tryFailTesting", ->

    it "updates the story when the conditions are met", ->
      event = {
        story: {
          id: 1
          project_id: 1
          current_state: 'started'
        }
        original_labels: [
          'foobar', reviewedLabel
        ]
        new_labels: [
          'foobar', reviewedLabel, failedLabel
        ]
      }

      update = {
        labels: ['foobar']
      }

      _client.updateStory.returns(Q())

      pt.tryFailTesting(event).then ->
        _client.updateStory.should.have.been.calledWith(1, 1, update)

    it "does not update the story when the conditions are not met", ->
      event = {
        story: {
          id: 1
          project_id: 1
          current_state: 'started'
        }
        original_labels: [
          'foobar', reviewedLabel
        ]
        new_labels: [
          'foobar', reviewedLabel, passedLabel
        ]
      }

      _client.updateStory.returns(Q())

      pt.tryFailTesting(event).then ->
        _client.updateStory.should.have.not.been.called
