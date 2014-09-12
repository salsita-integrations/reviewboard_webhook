debug = require('debug')('reviewboard:tracker')
Q = require('q')

dummy = ->
  debug("Calling dummy (empty) implementation...")
  return Q()

module.exports = {
  linkReviewRequest: dummy
  markReviewAsApproved: dummy
  id: 'dummy'
}
