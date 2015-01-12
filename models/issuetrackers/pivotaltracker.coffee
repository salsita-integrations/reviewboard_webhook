Q = require('q')
EventEmitter = require('events').EventEmitter
request = require('request')
_ = require('lodash')
debug = require('debug')('pivotaltracker')
config = require('config')
pt = require("pivotaltracker")

implementedLabel = config.services.pivotaltracker.implementedLabel
reviewedLabel = config.services.reviewboard.approvedLabel
noReviewLabel = config.services.reviewboard.noReviewLabel
passedLabel = config.services.pivotaltracker.testingPassedLabel
failedLabel = config.services.pivotaltracker.testingFailedLabel
noTestingLabel = config.services.pivotaltracker.noTestingLabel

isPassedReviewLabel = (label) -> label in [reviewedLabel, noReviewLabel]
isPassedTestingLabel = (label) -> label in [passedLabel, noTestingLabel]
isFailedTestingLabel = (label) -> label is failedLabel

#
# The global client implementation that is being used by the functions in this module.
#

client = null

useClient = (apiClient) ->
  client = apiClient

#
# Default client implementation, which actually calls the Pivotal Tracker API.
#

getStory = (pid, sid) ->
  _client = new pt.Client(process.env.PT_TOKEN)
  Q.ninvoke(_client.project(pid).story(sid), 'get')

updateStory = (pid, sid, story) ->
  _client = new pt.Client(process.env.PT_TOKEN)
  Q.ninvoke(_client.project(pid).story(sid), 'update', story)

defaultClient = {
  getStory: getStory
  updateStory: updateStory
}

useClient(defaultClient)

#
# Exported functions.
#

# linkReviewRequest adds a record for the review request identified by `rrid`
# to the link section of the story specified by `storyIdTag`.
linkReviewRequest = (storyIdTag, rrid, _isRequestNew) ->
  debug('linkReviewRequest -> start')
  args = parseStoryIdTag(storyIdTag)
  client.getStory(args.pid, args.sid)
    .then (story) ->
      debug('linkReviewRequest -> got the story object')
      description = story.description || ''
      lines = description.split('\n')

      begin = lines.indexOf(linksSeparatorBegin)

      # Append a new links section to the description in case
      # the links begin separator is not present in the description.
      if begin is -1
        lines.push('')
        lines.push(linksSeparatorBegin)
        lines.push(link(rrid, 'pending'))
        lines.push(linksSeparatorEnd)

        return client.updateStory(story.projectId, story.id, {
          description: lines.join('\n')
        })
      begin++

      offset = lines.slice(begin).indexOf(linksSeparatorEnd)

      # In case there is no end separator, something is wrong...
      if offset is -1
        throw new Error("Inconsistent links section found for story #{story.id}")

      links = lines.slice(begin, begin + offset)

      # Make sure the link is not there yet.
      prefix = "review #{rrid}"
      alreadyThere = links.some (line) -> ~line.indexOf(prefix)
      if alreadyThere
        return

      # Apend the review request record to the existing links.
      links.push(link(rrid, 'pending'))

      # Generate the new description.
      amendedLines = lines.slice(0, begin).concat(links).concat(lines.slice(begin + offset))
      amendedDescription = amendedLines.join('\n')

      # Send the update request to Pivotal Tracker.
      client.updateStory(story.projectId, story.id, {
        description: amendedDescription
      })


# markReviewAsApproved marks the review as approved in Pivotal Tracker
# by rewriting the links section in the story description.
markReviewAsApproved = (storyIdTag, rrid) ->
  debug('markReviewAsApproved -> start')
  args = parseStoryIdTag(storyIdTag)
  client.getStory(args.pid, args.sid)
    .then (story) ->
      debug('markReviewAsApproved -> got the story object')
      lines = story.description.split('\n')

      begin = lines.indexOf(linksSeparatorBegin)

      # No links section found, something is wrong...
      if begin is -1
        throw new Error("No links section found for story #{story.id}")
      begin++

      offset = lines.slice(begin).indexOf(linksSeparatorEnd)

      # In case there is no end separator, something is wrong...
      if offset is -1
        throw new Error("Inconsistent links section found for story #{story.id}")

      prefix = "review #{rrid}"
      links = lines.slice(begin, begin + offset)
      amendedLinks = links.map (line) ->
        if ~line.indexOf(prefix)
          return link(rrid, 'approved')
        return line

      amendedLines = lines.slice(0, begin).concat(amendedLinks).concat(lines.slice(begin + offset))
      amendedDescription = amendedLines.join('\n')

      client.updateStory(story.projectId, story.id, {
        description: amendedDescription
      })


# Links Section Format
#
# ----- Review Board Review Requests -----
# review 10000 is approved
# review 10001 is pending
# ----------------------------------------
linksSeparatorBegin = '+---- Review Board Review Requests ----+'
linksSeparatorEnd   = '+----------------------------------------------------+'

areAllReviewsApproved = (storyIdTag) ->
  debug('areAllReviewsApproved -> start')
  args = parseStoryIdTag(storyIdTag)
  client.getStory(args.pid, args.sid)
    .then (story) ->
      debug('areAllReviewsApproved -> got the story object')

      # The story must be labeled with 'implemented' to ever return true.
      if not (story.labels.some (label) -> label.name is implementedLabel)
        debug("areAllReviewApproved -> 'implemented' label missing")
        return false

      lines = story.description.split('\n')

      begin = lines.indexOf(linksSeparatorBegin)
      if begin is -1
        return true
      begin++

      offset = lines.slice(begin).indexOf(linksSeparatorEnd)
      if offset is -1
        throw new Error("Inconsistent links section found for story #{story.id}")

      links = lines.slice(begin, begin + offset)
      return links.every (line) -> ~line.indexOf('approved')


transitionToNextState = (storyIdTag) ->
  debug('transitionToNextState -> start')
  args = parseStoryIdTag(storyIdTag)
  client.getStory(args.pid, args.sid)
    .then (story) ->
      debug('transitionToNextState -> got the story object')
      switch story.currentState
        when 'started'
          # This function is only called when the story is fully reviewed.
          # The task here is to drop the 'implemented' label and add 'reviewed'.
          # This transitions the story from Implemented to Reviewed.

          # First, make sure the 'reviewed' label is not there yet.
          # In that case there is nothing to do and we return.
          alreadyThere = story.labels.some (label) -> label.name is reviewedLabel
          if alreadyThere
            return

          # Drop the 'implemented' label.
          filteredLabels = story.labels.filter (label) -> label.name isnt implementedLabel

          # Add the 'reviewed' label.
          labels = filteredLabels.map (label) -> {id: label.id}
          labels.push({name: reviewedLabel})

          # Update the story.
          client.updateStory(story.projectId, story.id, {labels: labels})
        when 'finished'
          client.updateStory(story.projectId, story.id, {currentState: 'delivered'})


discardReviewRequest = (storyIdTag, rrid) ->
  debug('discardReviewRequest -> start')
  args = parseStoryIdTag(storyIdTag)
  client.getStory(args.pid, args.sid)
    .then (story) ->
      debug('discardReviewRequest -> got the story object')
      lines = story.description.split('\n')

      begin = lines.indexOf(linksSeparatorBegin)
      if begin is -1
        return
      begin++

      offset = lines.slice(begin).indexOf(linksSeparatorEnd)
      if offset is -1
        throw new Error("Inconsistent links section found for story #{story.id}")
      
      links = lines.slice(begin, begin + offset)
      prefix = "review #{rrid}"
      amendedLinks = links.filter (line) -> line.indexOf(prefix)

      if amendedLinks.length is links.length
        return

      amendedLines = lines.slice(0, begin).concat(amendedLinks).concat(lines.slice(begin + offset))
      amendedDescription = amendedLines.join('\n')

      client.updateStory(story.projectId, story.id, {
        description: amendedDescription
      })


parseStoryIdTag = (storyIdTag) ->
  parts = storyIdTag.split('/')
  if parts.length isnt 3
    throw new Error("Invalid Story-Id tag: #{storyIdTag}")
  return {
    pid: parts[0]
    sid: parts[2]
  }


link = (rrid, state) ->
  "review #{rrid} is #{state} ([link](#{config.services.reviewboard.url}/r/#{rrid}))"

##
## Pivotal Tracker Activity Hooks
##

activity = new EventEmitter()

activity.on 'labels', (event) ->
  tryPassTesting event
    .fail (err) ->
      console.error('failed to update Pivotal Tracker story:', err)
    .done()

activity.on 'labels', (event) ->
  tryFailTesting event
    .fail (err) ->
      console.error('failed to update Pivotal Tracker story:', err)
    .done()

# Handle qa+ label added.
#
# Expected: state:started label:reviewed label:qa+
# Change:   state:finished -label:reviewed -label:qa+
#           (transition to Tested)
tryPassTesting = (event) ->
  debug('tryPassTesting')

  # Check the input conditions.
  story = event.story
  original_labels = event.original_labels
  new_labels = event.new_labels

  original_reviewed = original_labels.some isPassedReviewLabel
  new_reviewed = new_labels.some isPassedReviewLabel

  original_tested = original_labels.some isPassedTestingLabel
  new_tested = new_labels.some isPassedTestingLabel

  # The story is started.
  if story.currentState isnt 'started'
    debug('tryPassTesting -> skip (not started)')
    return Q()
  # In case the labels were already there, do nothing.
  # Something is probably wrong, but we cannot decide clearly what to do.
  # This probably means that the previous hooks was not processed correctly or something,
  # because otherwise the labels would be gone already.
  if original_reviewed and original_tested
    debug('tryPassTesting -> skip (labels were already there, oops)')
    return Q()
  # Finally, check that the labels are there.
  if not (new_reviewed and new_tested)
    debug('tryPassTesting -> skip (labels are not there yet)')
    return Q()

  debug('tryPassTesting -> update the story')
  labels = new_labels.filter (label) ->
    not (isPassedReviewLabel(label) or isPassedTestingLabel(label))
  labels = labels.map (label) ->
    {name: label}
  return client.updateStory(story.projectId, story.id, {
    currentState: 'finished'
    labels: labels
  })

# Handle qa- added.
#
# Expected: state:started label:reviewed label:qa-
# Change:   -label:reviewed -label:qa-
#           (transition to Being Implemented)
tryFailTesting = (event) ->
  debug('tryFailTesting')

  # Check the input conditions.
  story = event.story
  original_labels = event.original_labels
  new_labels = event.new_labels

  original_reviewed = original_labels.some isPassedReviewLabel
  new_reviewed = new_labels.some isPassedReviewLabel

  original_failed = original_labels.some isFailedTestingLabel
  new_failed = new_labels.some isFailedTestingLabel

  # The story is started.
  if story.currentState isnt 'started'
    debug('tryFailTesting -> skip (not started)')
    return Q()
  # In case the labels were already there, do nothing.
  # Something is probably wrong, but we cannot decide clearly what to do.
  # This probably means that the previous hooks was not processed correctly or something,
  # because otherwise the labels would be gone already.
  if original_reviewed and original_failed
    debug('tryFailTesting -> skip (labels were already there, oops)')
    return Q()
  # Finally, check that the labels are there.
  if not (new_reviewed and new_failed)
    debug('tryFailTesting -> skip (labels are not there yet)')
    return Q()

  debug('tryFailTesting -> update the story')
  labels = new_labels.filter (label) ->
    not (isPassedReviewLabel(label) or isFailedTestingLabel(label))
  labels = labels.map (label) ->
    {name: label}
  return client.updateStory(story.projectId, story.id, {labels: labels})


module.exports = {
  useClient: useClient
  getStory: (pid, sid) -> client.getStory(pid, sid)
  updateStory: (pid, sid, update) -> client.updateStory(pid, sid, update)
  linkReviewRequest: linkReviewRequest
  markReviewAsApproved: markReviewAsApproved
  areAllReviewsApproved: areAllReviewsApproved
  transitionToNextState: transitionToNextState
  discardReviewRequest: discardReviewRequest
  activity: activity
  tryPassTesting: tryPassTesting
  tryFailTesting: tryFailTesting
  id: 'pivotaltracker'
}
