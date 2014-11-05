JiraApi = require('jira').JiraApi
config = require('config')
Q = require('q')
_ = require('lodash')
debug = require('debug')('reviewboard:route')


jira = new JiraApi(
  'https', config.services.jira.host, config.services.jira.port,
  config.services.jira.user, config.services.jira.password,
  '2')


areAllReviewsApproved = (issueKey) ->
  Q.ninvoke(jira, 'getRemoteLinks', issueKey)
    .then (links) ->
      # Developers are supposed to post review requests before they move the
      # issue to "in review" so we assume 0 reviews means it's a "special"
      # issue without reviews.
      if links.length == 0 then return true
      return _.all links, ({object}) -> object.status.resolved


transitionToReviewed = (issueKey) ->
  # Note: this expects JIRA to take care of verifying whether the issue is in
  # the correct state (IOW we assume the "to-reviewed" transition is only
  # carried out successfully when the issue is in the "implemented" state).
  Q.ninvoke(jira, 'transitionIssue', issueKey, {
    transition: {
      id: config.services.jira.transitions.to_reviewed
    }})


# Add a remote issue link to the JIRA issue.
linkReviewRequest = (issueKey, rid) ->
  Q.ninvoke(jira, 'getRemoteLinks', issueKey).then (links) ->
    # Check whether this review request is already linked.
    if (_.any links, ({object}) -> ~object.title.indexOf(rid))
      console.log("Review #{rid} already linked.")
      return

    rb_url = config.services.reviewboard.url
    link =
      globalId: "#{rb_url}/r/#{rid}"
      application:
        type: "com.reviewboard"
        name: "ReviewBoard"
      object:
        url: "#{rb_url}/r/#{rid}"
        title: "r#{rid}"
        icon:
          url16x16: "#{rb_url}/static/rb/images/favicon.ico"

    return Q.ninvoke(jira, 'createRemoteLink', issueKey, link)

  .fail (err) ->
    console.error "error", err
    Q.reject err


# Set the status of the correspoding remote issue issue link to `resolved`
# (this will change the issue link to use striked font which looks nice and
# adds to good UX).
markReviewAsApproved = (issueKey, rid) ->
  Q.ninvoke(jira, 'getRemoteLinks', issueKey).then (links) ->
    # Verify whether this review request has a coresponding remote link in
    # JIRA.
    # n QAQ
    link = _.find links, ({object}) -> ~object.title.indexOf(rid)
    if not link
      console.warn("No linked review with id #{rid}.")
      return

    rb_url = config.services.reviewboard.url
    link =
      globalId: link.object.url
      object:
        url: "#{rb_url}/r/#{rid}"
        title: "r#{rid}"
        status:
          resolved: true
        icon:
          url16x16: "http://www.openwebgraphics.com/resources/data/47/accept.png"

    return Q.ninvoke(jira, 'createRemoteLink', issueKey, link)

  .fail (err) ->
    console.error "error", err
    Q.reject err


module.exports = {
  linkReviewRequest: linkReviewRequest
  markReviewAsApproved: markReviewAsApproved
  areAllReviewsApproved: areAllReviewsApproved
  transitionToReviewed: transitionToReviewed
  id: 'jira'
}
