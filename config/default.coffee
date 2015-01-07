_ = require('lodash')

module.exports =
  trackers: do ->
    if process.env.ENABLED_TRACKERS?
      _.compact(process.env.ENABLED_TRACKERS?.split(','))
    else
      ['jira', 'pivotaltracker']
  services:
    jira:
      host: process.env.JIRA_HOST
      port: process.env.JIRA_PORT or 80
      user: process.env.JIRA_USER
      password: process.env.JIRA_PASSWORD
      transitions: {
        10501: # coding subtask
          required_state: "10401"
          transition: "461"
        '*': # all other types
          required_state: "10401"
          transition: "341"
      }

    reviewboard:
      domain: process.env.RB_DOMAIN
      url: "https://#{process.env.RB_DOMAIN}"
      approvedLabel: 'reviewed'
      waitInterval: 5000

    pivotaltracker:
      implementedLabel: 'implemented'
      testingPassedLabel: 'qa+'
      testingFailedLabel: 'qa-'
