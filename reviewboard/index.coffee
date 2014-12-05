request = require('request')
_ = require('lodash')
Q = require('q')
debug = require('debug')('reviewboard')
config = require('config')

RB_URL = config.services.reviewboard.url
RB_WAIT_PERIOD_MS = config.services.reviewboard.waitInterval


# ReviewBoard is sending 4 requests at the same time. Keep a wait list to
# prevent duplicite updates.
waitDict = {}


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


parseStoryId = ({bugs_closed, branch}) ->
  if bugs_closed?.length == 1
    # A single bug is linked, we assume it's issue ID set by SalsaFlow.
    field = bugs_closed[0]
    return field

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


module.exports = {
  getReviewRequest: getReviewRequest
  middleware: {
    ensureReviewRequestPresent: ensureReviewRequestPresent
    throttleRBRequests: throttleRBRequests
  }
  parseStoryId: parseStoryId
}
