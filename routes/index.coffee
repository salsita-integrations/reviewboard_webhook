express = require('express')
router = express.Router()
request = require('request')
_ = require('lodash')
Q = require('q')
debug = require('debug')('reviewboard')
config = require('config')

issueTrackers = _.zipObject _.map config.trackers, (tracker) ->
  [tracker, require("./../models/issuetrackers/#{tracker}")]
issueTrackers._dummy = require('./../models/issuetrackers/dummy')

debug("Supported issue trackers: ", _.keys issueTrackers)


if process.env.NODE_ENV != 'production'
  # Long stack traces for Q.
  Q.longStackSupport = true


# ReviewBoard is sending 4 requests at the same time. Keep a wait list to
# prevent duplicite updates.
waitDict = {}


RB_URL = config.services.reviewboard.url
RB_WAIT_PERIOD_MS = config.services.reviewboard.waitInterval


parseStoryId = ({bugs_closed, branch}) ->
  if bugs_closed?.length == 1
    # A single bug is linked, we assume it's issue ID set by SalsaFlow.
    field = bugs_closed[0]
  else
    # No bug or more bugs linked, we assume it's GitFlow 1.0.
    field = branch

  return null unless field

  # Let's try to parse out the issue id.
  match = null

  # Match GitFlow1 style branch (e.g. "feature/123456/human-name").
  match = field.match /^.*\/([^/]+)\/.*$/
  if match then match = match[1]

  # Otherwise just take the id.
  match or= field

  return match


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


  # Middleware.
ensureReviewRequestPresent = (req, res, next) ->
  if not req.body?.payload?
    return res.send(422, "missing 'payload' field")

  payload = JSON.parse(req.body.payload)
  req.payload = payload

  rid = payload.review_request_id

  if not rid?
    console.error "error: Required parameter missing: review_request_id"
    return res.send(422)

  rbsessionid = req.app.get('rbsessionid')

  getReviewRequest(rbsessionid, rid)
    .then (rr) ->
      req.reviewRequest = rr
      next()
    .fail (err) ->
      console.error JSON.stringify(err)
      next(err)
    .done()


# Middleware.
throttleRBRequests = (req, res, next) ->
  rr = req.reviewRequest
  if not rr?
    return res.send(500, 'missing review request')

  if waitDict[rr.id]
    console.log "Review id #{rr.id} is in the wait list."
    return res.send(202)

  waitDict[rr.id] = true
  setTimeout (-> delete waitDict[rr.id]), RB_WAIT_PERIOD_MS

  next()


router.get '/', (req, res) ->
  res.send "Move on, nothing to see here."


# RB related middlewares.
router.post '/rb/*', ensureReviewRequestPresent
router.post '/rb/*', throttleRBRequests


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

  storyId = parseStoryId(rr)

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

  storyId = parseStoryId(rr)
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


# Get review request with id `rid` from ReviewBoard.
getReviewRequest = (rbsessionid, rid) ->
  defer = Q.defer()

  options = {
    method: 'GET'
    url: "#{RB_URL}/api/review-requests/#{rid}/"
    json: true
    headers:
      Cookie: "rbsessionid=#{rbsessionid}"
  }
  request options, (err, res, body) ->
    if err
      debug("getReviewRequest err", err)
      return defer.reject(err)
    if res.statusCode != 200
      debug("getReviewRequest failed to get", body)
      return defer.reject new Error(body)

    defer.resolve body.review_request

  return defer.promise


module.exports = {
  router: router
  issueTrackers: issueTrackers
  parseStoryId: parseStoryId
}

