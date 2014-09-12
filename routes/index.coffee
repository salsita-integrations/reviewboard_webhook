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


parseStoryId = (reviewRequest) ->
  match = reviewRequest.branch.match /^.*\/([0-9]+)\/.*$/
  # Match story id in GitFlow 2 branch field.
  match or= reviewRequest.branch.match /^([0-9]+)$.*/
  # Match JIRA issue key.
  match or= reviewRequest.branch.match /^(.+-.+)$.*/
  if not match?
    return null
  else
    return match[1]


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
  rr = req.reviewRequest?
  if not rr?
    res.send(500, 'missing review request')

  if waitDict[rr.id]
    console.log "Review id #{rr.id} is in the wait list."
    return res.send(429)

  waitDict[rr.id] = true
  setTimeout (-> delete waitDict[rr.id]), RB_WAIT_PERIOD_MS

  next()


router.get '/', (req, res) ->
  res.send "Move on, nothing to see here."


# RB related middlewares.
router.post '/rb/*', ensureReviewRequestPresent
router.post '/rb/*', throttleRBRequests


# Handle new review => if it's a 'ship-it', append a 'reviewed' label to the
# corresponding PT story (determined by the `branch` field in review request).
router.post '/rb/review-published', (req, res) ->
  res.send 'ok'

  debug('handling published review')

  rr = req.reviewRequest
  payload = req.payload

  debug('obtained payload', payload)
  debug("processing request (no wait list item for #{rr.id}")

  storyId = parseStoryId(rr)

  debug("For story", storyId)

  if not storyId
    console.error "ERROR: Could not determine story id from " +
      "'branch' field: ", payload
    return res.send(400)

  issueTracker = getIssueTrackerForStory(storyId)

  if not payload['ship_it']?
    debug("No ship_it field found, ignoring the notification.")
    return

  issueTracker.markReviewAsApproved(storyId, rr['id'])
    .then ->
      console.log("Story #{storyId} marked as review approved.")
    .fail (err) ->
      console.error("Failed to mark story #{storyId} as approved", err)
    .done()


router.post '/rb/review-request-published', (req, res) ->
  res.send 'ok'

  rr = req.reviewRequest
  payload = req.payload

  debug 'Review request branch field: ', rr.branch
  storyId = parseStoryId(rr)
  debug 'story id to update: ', storyId

  if not storyId?
    console.error("ERROR: Could not determine story id from " +
      "'branch' field: ", payload)
    return

  issueTracker = getIssueTrackerForStory(storyId)

  debug("Linking issue #{rr.id} to story #{storyId}...")

  issueTracker
    .linkReviewRequest(storyId, rr['id'], payload.new).done()


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


module.exports = router
# Export this to allow testing.
module.exports.issueTrackers = issueTrackers

