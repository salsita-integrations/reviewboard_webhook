process.on('uncaughtException', function (err) {
  console.error((new Date).toUTCString() + ' uncaughtException:', 
    JSON.stringify(err, null, 2))
  console.error(err.stack)
  process.exit(1)
})

var express = require('express');
var path = require('path');
var favicon = require('static-favicon');
var logger = require('morgan');
var cookieParser = require('cookie-parser');
var bodyParser = require('body-parser');
var _ = require('lodash');
require('coffee-script/register');
var debug = require('debug')('reviewboard:app');


debug("requiring routes...")
var routes = require('./routes/index');
debug("Routes required")


var app = express();

// view engine setup
app.set('views', path.join(__dirname, 'views'));
app.set('view engine', 'jade');

app.use(favicon());
app.use(logger('dev'));
app.use(bodyParser.json());
app.use(bodyParser.urlencoded());
app.use(cookieParser());
app.use(express.static(path.join(__dirname, 'public')));

app.use('/', routes);

/// catch 404 and forward to error handler
app.use(function(req, res, next) {
    var err = new Error('Not Found');
    err.status = 404;
    next(err);
});

/// error handlers

// development error handler
// will print stacktrace
if (app.get('env') === 'development') {
    app.use(function(err, req, res, next) {
        res.status(err.status || 500);
        res.render('error', {
            message: err.message,
            error: err
        });
    });
}

// production error handler
// no stacktraces leaked to user
app.use(function(err, req, res, next) {
    res.status(err.status || 500);
    res.render('error', {
        message: err.message,
        error: {}
    });
});


sa = require('superagent');
tough = require('tough-cookie');
var Cookie = tough.Cookie;


setInterval(function() {
  renewRbCookie();
}, 1000 * 60 * 60 * 24 * 7); // Renew cookie every week (to be sure).

renewRbCookie();

function renewRbCookie() {
  debug("renewing RB cookie...")
  sa
    .get('https://' + process.env.RB_AUTH + '@' + process.env.RB_DOMAIN + '/api/review-requests/')
    .end(function(err, res) {
      debug("renewing RB cookie -> RB response received", err, res.headers['set-cookie'])
      if (err) {
        return app.emit('app:error', err);
      }
      var cookies;
      if (res.headers['set-cookie'] instanceof Array)
        cookies = res.headers['set-cookie'].map(function (c) { return (Cookie.parse(c)); });
      else
        cookies = [Cookie.parse(res.headers['set-cookie'])];
      rbsession = _.find(cookies, function(cookie) { return cookie.key == 'rbsessionid'; });
      debug("Setting rbsessionid...")
      app.set('rbsessionid', rbsession.value);
      app.emit('app:ready');
    });
}


module.exports = app;
