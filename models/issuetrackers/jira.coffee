JiraApi = require('jira').JiraApi
config = require('config')
Q = require('q')
_ = require('lodash')
debug = require('debug')('reviewboard:route')


jira = new JiraApi(
  'https', config.services.jira.host, config.services.jira.port,
  config.services.jira.user, config.services.jira.password,
  '2')


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


markReviewAsApproved = (issueKey, rid) ->
  Q.ninvoke(jira, 'getRemoteLinks', issueKey).then (links) ->
    # Verify whether this review request has a coresponding remote link in
    # JIRA.
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
  id: 'jira'
}