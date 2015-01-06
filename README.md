reviewboard_webhook
===================

Webhook server for that listens for ReviewBoard (and newly Pivotal Tracker) events and connects to PT and JIRA.

We use it to automate mundane boring tasks such as appending labels and changing states in Pivotal tracker
and/or moving issues around in JIRA when developing apps using [Salsaflow](https://github.com/salsaflow/salsaflow).

## Usage
Deploy _somewhere_. For example on Heroku (if you have a pinger that will keep your app awake).

## Tests
...are using [mocha](https://github.com/visionmedia/mocha). Just run `npm test` to run the suite.
