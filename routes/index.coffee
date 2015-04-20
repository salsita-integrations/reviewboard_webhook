express = require('express')
router = express.Router()
request = require('request')
EventEmitter = require('events').EventEmitter
_ = require('lodash')
Q = require('q')
debug = require('debug')('reviewboard')
ptDebug = require('debug')('pivotaltracker')
config = require('config')
rb = require('../reviewboard')
pivotaltracker = require('./../models/issuetrackers/pivotaltracker')

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
  if storyId.match(/^[0-9]+\/stories\/[0-9]+$/)
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
    console.error "ERROR: Could not determine story id for RR:", rr
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

# Handle GitHub review issue events.
router.post '/github/issues', (req, res) ->
  issue = req.issue

  # Continue iff this is a review issues event.
  reviewLabel = config.services.github.reviewLabel
  isReviewIssue = issue.labels.any (label) -> label.name is reviewLabel
  if not isReviewRequest
    res.send 201
    return

  # Extract the story ID.
  storyId = github.parseStoryId(issue)
  debug 'story id to update: ', storyId

  if not storyId?
    console.error("ERROR: Could not determine story id for GitHub issue: #{issue}")
    res.send 500
    return

  issueTracker = getIssueTrackerForStory(storyId)

  # Continue iff the issue is opened, closed or reopened.
  switch issue.state
    when 'opened' then handleGitHubIssueOpened(issue, storyId, issueTracker)
    when 'closed' then handleGitHubIssueClosed(issue, storyId, issueTracker)
    when 'reopened' then handleGitHubIssueReopened(issue, storyId, issueTracker)


handleGitHubIssueOpened = (issue, storyIdTag, issueTracker) ->
  issueTracker.addComment(storyIdTag, issue.number, issue.html_url, 'Review issue opened.')
    .then ->
      console.log("Added comment to #{storyIdTag}: GitHub review issue #{issue.number} opened.")

    .fail (err) ->
      console.error("Failed add the review comment to story #{storyIdTag}", err)

    .done()


handleGitHubIssueClosed = (issue, storyIdTag, issueTracker) ->
  issueTracker.addComment(storyIdTag, issue.number, issue.html_url, 'Review issue closed.')
    .then ->
      console.log("Added comment to #{storyIdTag}: GitHub review issue #{issue.number} closed.")


    .fail (err) ->
      console.error("Failed add the review comment to story #{storyIdTag}", err)

    .done()



router.post '/pt/activity', (req, res) ->
  # Reply right away, no need to block the request.
  res.send 202

  body = req.body

  # Only process story updates.
  if body.kind isnt 'story_update_activity'
    return

  story_cache = {}

  for change in body.changes
    do (change) ->
      if change.kind is 'story' and change.new_values.labels?
        # Fetch the story object so that we can emit it with the event.
        promise = null
        pid = body.project.id
        sid = change.id

        cached_story = story_cache[sid]
        if cached_story?
          # The story is in the cache.
          promise = Q(cached_story)
        else
          # Fetch the relevant story.
          promise = pivotaltracker.getStory(pid, sid)
            .then (story) ->
              # Save the story into the cache.
              story_cache[story.id] = story
              return story

            .fail (err) ->
              console.error("PT activity: failed to get story (pid=#{pid}, sid=#{sid}):", err)

        # Once we have the story, we can emit the event.
        promise
          .then (story) ->
            ptDebug("/pt/activity -> emit 'labels' event")
            pivotaltracker.activity.emit 'labels', {
              story:              story
              original_label_ids: change.original_values.label_ids
              original_labels:    change.original_values.labels
              new_label_ids:      change.new_values.label_ids
              new_labels:         change.new_values.labels
            }

          .fail (err) ->
            console.error('PT activity:', err)

          .done()

module.exports = {
  router: router
  issueTrackers: issueTrackers
}
