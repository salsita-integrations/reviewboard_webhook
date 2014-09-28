# Dummy Issue Tracker
# ===================
#
# Generic implementation of an issue tracker. Used when we can't determine what
# PM tool should be used to handle an incoming RB notification.

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
