Q = require('q')
request = require('request')
_ = require('lodash')
debug = require('debug')('reviewboard')
pt = require("pivotaltracker")

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
  client = new pt.Client(process.env.PT_TOKEN)
  Q.nfcall(client.project(pid).story(sid).get)

updateStory = (pid, sid, story) ->
  client = new pt.Client(process.env.PT_TOKEN)
  Q.nfcall(client.project(pid).story(sid).update, story)

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
  debug('PT -> linkReviewRequest -> start')
  parseStoryIdTag(storyIdTag)
    .then (args) ->
      client.getStory(args.pid, args.sid)
    .then (story) ->
      debug('PT -> linkReviewRequest -> got the story object')
      lines = story.description.split('\n')

      begin = lines.indexOf(linksSeparatorBegin)

      # Append a new links section to the description in case
      # the links begin separator is not present in the description.
      if begin is -1
        lines.push('')
        lines.push(linksSeparatorBegin)
        lines.push("review #{rrid} is pending")
        lines.push(linksSeparatorEnd)

        return client.updateStory(story.project_id, story.id, {
          description: lines.join('\n')
        })
      begin++

      offset = lines.slice(begin).indexOf(linksSeparatorEnd)

      # In case there is no end separator, something is wrong...
      if offset is -1
        return Q.reject(new Error("Inconsistent links section found for story #{story.id}"))

      links = lines.slice(begin, begin + offset)

      # Make sure the link is not there yet.
      prefix = "review #{rrid}"
      alreadyThere = links.some (line) -> line.indexOf(prefix) is 0
      if alreadyThere
        return Q()

      # Apend the review request record to the existing links.
      links.push("review #{rrid} is pending")

      # Generate the new description.
      amendedLines = lines.slice(0, begin).concat(links).concat(lines.slice(begin + offset))
      amendedDescription = amendedLines.join('\n')

      # Send the update request to Pivotal Tracker.
      client.updateStory(story.project_id, story.id, {
        description: amendedDescription
      })


# markReviewAsApproved marks the review as approved in Pivotal Tracker
# by rewriting the links section in the story description.
markReviewAsApproved = (storyIdTag, rrid) ->
  debug('PT -> markReviewAsApproved -> start')
  parseStoryIdTag(storyIdTag)
    .then (args) ->
      client.getStory(args.pid, args.sid)
    .then (story) ->
      debug('PT -> markReviewAsApproved -> got the story object')
      lines = story.description.split('\n')

      begin = lines.indexOf(linksSeparatorBegin)

      # No links section found, something is wrong...
      if begin is -1
        return Q.reject(new Error("No links section found for story #{story.id}"))
      begin++

      offset = lines.slice(begin).indexOf(linksSeparatorEnd)

      # In case there is no end separator, something is wrong...
      if offset is -1
        return Q.reject(new Error("Inconsistent links section found for story #{story.id}"))

      prefix = "review #{rrid}"
      links = lines.slice(begin, begin + offset)
      amendedLinks = links.map (line) ->
        if line.indexOf(prefix) is 0
          return "review #{rrid} is approved"
        return line

      amendedLines = lines.slice(0, begin).concat(amendedLinks).concat(lines.slice(begin + offset))
      amendedDescription = amendedLines.join('\n')

      client.updateStory(story.project_id, story.id, {
        description: amendedDescription
      })


# Links Section Format
#
# ----- Review Board Review Requests -----
# review 10000 is approved
# review 10001 is pending
# ----------------------------------------
linksSeparatorBegin = '----- Review Board Review Requests -----'
linksSeparatorEnd   = '----------------------------------------'

areAllReviewsApproved = (storyIdTag) ->
  debug('PT -> areAllReviewsApproved -> start')
  parseStoryIdTag(storyIdTag)
    .then (args) ->
      client.getStory(args.pid, args.sid)
    .then (story) ->
      debug('PT -> areAllReviewsApproved -> got the story object')
      lines = story.description.split('\n')

      begin = lines.indexOf(linksSeparatorBegin)
      if begin is -1
        return
      begin++

      offset = lines.slice(begin).indexOf(linksSeparatorEnd)
      if offset is -1
        offset = lines.length - begin

      return lines.slice(begin, begin + offset)

    .then (lines) ->
      lines.every (l) -> l.indexOf('approved') isnt -1


transitionToNextState = (storyIdTag) ->
  debug('PT -> transitionToNextState -> start')
  parseStoryIdTag(storyIdTag)
    .then (args) ->
      client.getStory(args.pid, args.sid)
    .then (story) ->
      debug('PT -> transitionToNextState -> got the story object')
      switch story.current_state
        when 'started'
          # Look for the reviewed label. In case it is not there, we add it.
          # That signals that the story is ready to be tested.
          alreadyThere = story.labels.some (label) -> label.name is 'reviewed'
          if alreadyThere
            return Q()
          labels = story.labels.map (label) -> {id: label.id}
          labels.push({name: 'reviewed'})
          client.updateStory(story.project_id, story.id, {labels: labels})
        when 'finished'
          client.updateStory(story.project_id, story.id, {current_state: 'delivered'})


discardReviewRequest = (storyIdTag, rrid) ->
  debug('PT -> discardReviewRequest -> start')
  parseStoryIdTag(storyIdTag)
    .then (args) ->
      client.getStory(args.pid, args.sid)
    .then (story) ->
      debug('PT -> discardReviewRequest -> got the story object')
      lines = story.description.split('\n')

      begin = lines.indexOf(linksSeparatorBegin)
      if begin is -1
        return Q()
      begin++

      offset = lines.slice(begin).indexOf(linksSeparatorEnd)
      if offset is -1
        return Q.reject(new Error("Inconsistent links section found for story #{story.id}"))
      
      links = lines.slice(begin, begin + offset)
      prefix = "review #{rrid}"
      doUpdate = false
      amendedLinks = links.filter (line) ->
        if line.indexOf(prefix) is 0
          doUpdate = true
          return false
        return true

      if not doUpdate
        return Q()

      amendedLines = lines.slice(0, begin).concat(amendedLinks).concat(lines.slice(begin + offset))
      amendedDescription = amendedLines.join('\n')

      client.updateStory(story.project_id, story.id, {
        description: amendedDescription
      })


parseStoryIdTag = (storyIdTag) ->
  parts = storyIdTag.split('/')
  if parts.length isnt 3
    return Q.reject(new Error("Invalid Story-Id tag: #{storyIdTag}"))
  else
    return Q({
      pid: parts[0]
      sid: parts[2]
    })


module.exports = {
  useClient: useClient
  linkReviewRequest: linkReviewRequest
  markReviewAsApproved: markReviewAsApproved
  areAllReviewsApproved: areAllReviewsApproved
  transitionToNextState: transitionToNextState
  discardReviewRequest: discardReviewRequest
  id: 'pivotaltracker'
}
