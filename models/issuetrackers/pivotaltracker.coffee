Q = require('q')
request = require('request')
_ = require('lodash')
debug = require('debug')('reviewboard')
pivotal = require("pivotal")
pivotal.useToken(process.env.PT_TOKEN)


# Dummy implementations.
# TODO: Should we support PT too?
areAllReviewsApproved = -> Q(false)
transitionToNextState = -> Q()


markReviewAsApproved = (storyId, _rid) ->
  return addLabel(storyId, config.services.reviewboard.approvedLabel)


addLabel = (storyId, label) ->
  debug('PT -> addLabel -> start')
  Q.ninvoke(pivotal, 'getProjects')
    .then (obj) ->
      debug('PT -> addLabel -> Got a list of projects from PT')
      projectsIds = _.pluck obj.project, 'id'
      Q.allSettled _.map projectsIds, (pid) ->
        Q.ninvoke(pivotal, 'getStory', pid, storyId)

    .then (promises) ->
      debug('PT -> addLabel -> got story promises')
      # Check if we have any resolved promises (i.e., success).
      p = _.find promises, state: "fulfilled"
      if not p
        console.log "No relevant story found..."
        return Q.reject(new Error("Could not find story #{storyId}."))
      return p.value

    .then (story) ->
      debug('PT -> addLabel -> story found')
      if not story.labels
        labels = []
      else if typeof(story.labels) == 'string'
        labels = [story.labels]
      else
        labels = story.labels.split(',')
      if ~labels.indexOf('reviewed')
        return Q("done")
      else
        labels.push("reviewed")
      return Q.ninvoke(
        pivotal, 'updateStory',
        story.project_id, story.id,
        {labels: labels.join(',')})


# Sets `current_state` of story with `storyId` to `state`.
#
# We don't have PT project id so we'll need to iterate over
# all the projects we have access to.
linkReviewRequest = (storyId, rid, isRequestNew) ->

  if isRequestNew
    msg = "New review request added: #{RB_URL}/r/#{rid}"
  else
    # It's an update.
    msg = "Review request updated: #{RB_URL}/r/#{rid}"

  # Give me all the projects.
  Q.ninvoke(pivotal, 'getProjects')

    # Iterate over them and try to update story with `storyId`.
    # We'll get a HTTP 404 if the story doesn't belong to the project.
    .then (obj) ->
      Q.allSettled _.map obj.project, (project) ->
        Q.ninvoke pivotal, 'addStoryComment', project.id, storyId, msg
      
    # We've pinged all the projects. Let's see if we succeeded.
    .then (settledPromises) ->
      # Check if we have any resolved promises (i.e., update success).
      p = _.find settledPromises, state: "fulfilled"
      if not p
        console.log "No relevant story found..."
        return Q.reject(new Error("Could not find story #{storyId}."))
      # Yay, adding story comment succeeded!
      console.log "Comment added!"
      return Q("done")

    .fail (err) ->
      console.error "addComment error", err
      Q.reject(err)


module.exports = {
  linkReviewRequest: linkReviewRequest
  markReviewAsApproved: markReviewAsApproved
  areAllReviewsApproved: areAllReviewsApproved
  transitionToNextState: transitionToNextState
  id: 'pivotaltracker'
}
