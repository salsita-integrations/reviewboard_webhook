express = require('express')
router = express.Router()
request = require('request')
_ = require('lodash')
Q = require('q')
debug = require('debug')('reviewboard')
config = require('config')
rb = require('../reviewboard')

issueTrackers = _.zipObject _.map config.trackers, (tracker) ->
  [tracker, require("./../models/issuetrackers/#{tracker}")]
issueTrackers._dummy = require('./../models/issuetrackers/dummy')

debug("Supported issue trackers: ", _.keys issueTrackers)


if process.env.NODE_ENV != 'production'
  # Long stack traces for Q.
  Q.longStackSupport = true


getIssueTrackerForStory = (storyId) ->
  debug("Determining issue tracker for story #{storyId}")
  tracker = null
  if storyId.match(/^[0-9]+$/)
    tracker = issueTrackers.pivotaltracker
  else if storyId.match(/^.+-.+$/)
    tracker = issueTrackers.jira
  tracker or= issueTrackers._dummy
  debug "Using tracker: ", tracker.id
  return tracker


router.get '/', (req, res) ->
  res.send "Move on, nothing to see here."


# RB related middlewares.
router.post '/rb/*', rb.middleware.ensureReviewRequestPresent
router.post '/rb/*', rb.middleware.throttleRBRequests


# Handle a newly published update to a review request (eiether approving or
# non-approving).
# If it's a `ship-it`, mark review as approved in the PM tool.
router.post '/rb/review-published', (req, res) ->
  # Reply right away (so that we don't block ReviewBoard).
  res.send 'ok'

  debug('Handling published review...')

  rr = req.reviewRequest
  payload = req.payload

  debug("processing request (no wait list item for #{rr.id}")

  storyId = rb.parseStoryId(rr)

  debug("For story", storyId)

  if not storyId
    console.error "ERROR: Could not determine story id"
    return res.send(400)

  issueTracker = getIssueTrackerForStory(storyId)

  if not payload['ship_it']
    debug("ship_it field is falsy or undefined, ignoring the notification.")
    return

  issueTracker.markReviewAsApproved(storyId, rr['id'])
    .then ->
      console.log("Story #{storyId} marked as review approved.")
    .then ->
      issueTracker.areAllReviewsApproved(storyId).then (allApproved) ->
        if allApproved
          issueTracker.transitionToNextState(storyId)
          console.log("Story #{storyId} transitioned to \"reviewed\" state")
    .fail (err) ->
      console.error("Failed to process story #{storyId}", err)
    .done()


# Handle a newly published review request.
# Link the review request to the corresponding story in the PM tool.
router.post '/rb/review-request-published', (req, res) ->
  # Reply right away (so that we don't block ReviewBoard).
  res.send 'ok'

  rr = req.reviewRequest
  payload = req.payload

  storyId = rb.parseStoryId(rr)
  debug 'story id to update: ', storyId

  if not storyId?
    console.error("ERROR: Could not determine story id")
    return

  issueTracker = getIssueTrackerForStory(storyId)

  debug("Linking issue #{rr.id} to story #{storyId}...")

  issueTracker.linkReviewRequest(storyId, rr['id'], payload.new)
    .then ->
      console.log("Story #{storyId} review #{rr['id']} linked.")

    .fail (err) ->
      console.error("Failed to link review request", err)

    .done()

router.post '/rb/review-request-closed', (req, res) ->
  # Reply right away (so that we don't block ReviewBoard).
  res.send 'ok'

  rr = req.reviewRequest
  payload = req.payload

  storyId = rb.parseStoryId(rr)
  debug 'story id to update: ', storyId

  if not storyId?
    console.error("ERROR: Could not determine story id")
    return

  if payload.type != 'D'
    debug("Ignoring review request close event for #{rr['id']} (type is not \"discarded\")")
    return

  issueTracker = getIssueTrackerForStory(storyId)

  debug("Closing linked issue #{rr.id} at story #{storyId}...")

  issueTracker.discardReviewRequest(storyId, rr['id'])
    .then ->
      console.log("Story #{storyId} review #{rr['id']} discarded.")

    .fail (err) ->
      console.error("Failed to link review request", err)

    .done()
  
  
  
  



module.exports = {
  router: router
  issueTrackers: issueTrackers
}

