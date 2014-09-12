express = require('express')
router = express.Router()
sa = require('superagent')

pt = require('./../models/pivotal')

RB_URL="https://review.salsitasoft.com"

router.get '/', (req, res) ->
  res.render 'index', { title: 'Express' }


router.post '/', (req, res) ->
  rid = req.body.review_request_id
  rbsessionid = req.app.get('rbsessionid')
  console.log "payload: ", req.body
  getReviewRequest(rbsessionid, rid)
    .then (rr) ->
      console.log 'Branch: ', rr.branch
      match = rr.branch.match /^.*\/([0-9]{6,9})\/.*$/
      match or= rr.branch.match /^([0-9]{6,9})$.*/
      if not match
        console.log("ERROR: Could not determine PT story id from " +
          "'branch' field.")
        console.log "payload: ", req.body
        return res.send(422)
      if req.body.new
        msg = "New review request added: #{RB_URL}/r/#{rid}"
      else
        msg = "Review request updated: #{RB_URL}/r/#{rid}"
      pt.addCommentToStory(match[1], msg)
        .then ->
          res.send 'ok'
        .fail (err) ->
          console.error "error: ", err
          res.send 500, err


getReviewRequest = (rbsessionid, rid) ->
  rb_url = "#{RB_URL}/api/review-requests/#{rid}/"
  req = sa.get(rb_url)
    .set('Cookie', "rbsessionid=" + rbsessionid)
    .set('Accept', 'application/json')
    .buffer()
  Q.nbind(req.end, req)()
    .then (res) ->
      console.log 'review request loaded'
      obj = JSON.parse(res.text)
      debug('RB request: %j', obj)
      return obj


module.exports = router

