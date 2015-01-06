reviewboard_webhook
===================

Webhook server for that listens for ReviewBoard (and newly Pivotal Tracker) events and connects to PT and JIRA.

We use it to automate mundane boring tasks such as appending labels and changing states in Pivotal tracker
and/or moving issues around in JIRA when developing apps using [Salsaflow](https://github.com/salsaflow/salsaflow).

## Usage
Deploy _somewhere_. For example on Heroku (if you have a pinger that will keep your app awake).

## Env vars
 * `JIRA_HOST` ... URL of your JIRA installation
 * `JIRA_PORT` ... JIRA port, duh. Defaults to 80.
 * `JIRA_USER` and `JIRA_PASSWORD` ... Admin (or user that has access to all the projects you want to support) credentials for JIRA. We need this to be able to move the cards.
 * `RB_DOMAIN` ... ReviewBoard server URL
 * `RB_AUTH` ... `username:password` string for admin RB user (udesused to load review request details from RB).

## Tests
...are using [mocha](https://github.com/visionmedia/mocha). Just run `npm test` to run the suite.
