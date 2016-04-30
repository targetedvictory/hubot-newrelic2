# Description:
#   Display stats from New Relic
#
# Dependencies:
#
# Configuration:
#   HUBOT_NEWRELIC_API_KEY
#   HUBOT_NEWRELIC_API_HOST="api.newrelic.com"
#
# Commands:
#   hubot newrelic help - Returns a list of commands for this plugin
#   hubot newrelic apps - Returns statistics for all applications from New Relic
#   hubot newrelic apps errors - Returns statistics for applications with errors from New Relic
#   hubot newrelic apps name <filter_string> - Returns a filtered list of applications
#   hubot newrelic apps instances <app_id> - Returns a list of one application's instances
#   hubot newrelic apps instancesbyname <filter_string> - Returns list of instances for matching applications
#   hubot newrelic apps hosts <app_id> - Returns a list of one application's hosts
#   hubot newrelic apps hostsbyname <filter_string> - Returns list of hosts for matching applications
#   hubot newrelic ktrans - Lists stats for all key transactions from New Relic
#   hubot newrelic ktrans id <ktrans_id> - Returns a single key transaction
#   hubot newrelic servers - Returns statistics for all servers from New Relic
#   hubot newrelic server name <filter_string> - Returns a filtered list of servers
#   hubot newrelic users - Returns a list of all account users from New Relic
#   hubot newrelic user email <filter_string> - Returns a filtered list of account users
#
# Authors:
#   statianzo
#
# Contributors:
#   spkane
#   ptshrdn
#

plugin = (robot) ->
  defaultApiKey = process.env.HUBOT_NEWRELIC_API_KEY
  # Support multiple API keys by setting additional environment
  # variables of the form HUBOT_NEWRELIC_API_KEY_<app name pattern>,
  # with app name hyphens converted to underscores
  accounts = {}
  accounts['_default'] = { pattern: '_default', apiKey: defaultApiKey, accountType: 'pro' }
  for own key, value of process.env
    if match = key.match(/HUBOT_NEWRELIC_API_KEY_(.+)/)
      accounts[match[1]] = { apiKey: value, accountType: process.env["HUBOT_NEWRELIC_ACCOUNT_TYPE_#{match[1]}"], pattern: match[1].toLowerCase() }
  apiHost = process.env.HUBOT_NEWRELIC_API_HOST or 'api.newrelic.com'
  apiBaseUrl = "https://#{apiHost}/v2/"
  config = {}
  # knownApps is an array, not an object, in case ids/names are repeated across accounts
  knownApps = []

  switch robot.adapterName
    when "hipchat"
      config.up = '(continue)'
      config.down = '(failed)'

  resetApps = () ->
    knownApps = []

  addApps = (applications, account) ->
    for app in applications
      knownApps.push { id: app.id, name: app.name, account: account }

  accountsByAppId = (id, cb) ->
    matches = (app for app in knownApps when app.id is id)
    for app in matches
      cb(app.account)

  accountsByPattern = (pattern, cb) ->
    env_pattern = pattern.split('-').join('_').toLowerCase()
    matches = (account for pattern, account of accounts when env_pattern.search(pattern) >= 0)
    if matches.length > 0
      cb(match) for match in matches
    else
      cb(accounts._default)

  request = (account, path, data, cb) ->
    if account.accountType == 'lite'
      requestToLiteAccount account, path, cb
    else
      requestToProAccount account, path, data, cb

  requestAll = (path, data, cb) ->
    request(account, path, data, cb) for pattern, account of accounts

  requestAllPro = (path, data, cb) ->
    request(account, path, data, cb) for pattern, account of accounts when account.accountType is 'pro'

  requestToPattern = (pattern, path, data, cb) ->
    accountsByPattern pattern, (account) ->
      request account, path, data, cb

  requestToLiteAccount = (account, path, cb) ->
    robot.http(apiBaseUrl + path)
      .header('X-Api-Key', account.apiKey)
      .get() (err, res, body) ->
        if err
          cb(err)
        else
          json = JSON.parse(body)
          if json.error
            cb(new Error(body))
          else
            cb(null, json, account)

  requestToProAccount = (account, path, data, cb) ->
    robot.http(apiBaseUrl + path)
      .header('X-Api-Key', account.apiKey)
      .header("Content-Type","application/x-www-form-urlencoded")
      .post(data) (err, res, body) ->
        if err
          cb(err)
        else
          json = JSON.parse(body)
          if json.error
            cb(new Error(body))
          else
            cb(null, json, account)

  filterApps = (account, applications, pattern) ->
    if account.accountType == 'lite'
      (app for app in applications when app.name.search(pattern) >= 0)
    else
      applications

  filterUsers = (account, users, pattern) ->
    if account.accountType == 'lite'
      (user for user in users when user.email.search(pattern) >= 0)
    else
      users

  # Initialize apps table at start
  requestAll 'applications.json', '', (err, json, account) ->
    if err
      console.log("Error initialing apps table: #{err}")
    else
      addApps json.applications, account

  robot.respond /(newrelic|nr) help$/i, (msg) ->
    msg.send "
Note: In these commands you can shorten newrelic to nr.\n
#{robot.name} newrelic help\n
#{robot.name} newrelic apps\n
#{robot.name} newrelic apps errors\n
#{robot.name} newrelic apps name <filter_string>\n
#{robot.name} newrelic apps instances <app_id>\n
#{robot.name} newrelic apps instancesbyname <filter_string>\n
#{robot.name} newrelic apps hosts <app_id>\n
#{robot.name} newrelic apps hostsbyname <filter_string>\n
#{robot.name} newrelic ktrans\n
#{robot.name} newrelic ktrans id <ktrans_id>\n
#{robot.name} newrelic servers\n
#{robot.name} newrelic server name <filter_string>\n
#{robot.name} newrelic users\n
#{robot.name} newrelic user email <filter_string>"

  robot.respond /(newrelic|nr) apps$/i, (msg) ->
    # rebuild the app lookup table when issuing this command
    resetApps()
    requestAll 'applications.json', '', (err, json, account) ->
      if err
        msg.send "Failed: #{err.message}"
      else
        addApps json.applications, account
        msg.send plugin.apps json.applications, config

  robot.respond /(newrelic|nr) apps cache$/i, (msg) ->
    # hidden command: show app lookup table; not api keys though
    for app in knownApps
      msg.send "id:#{app.id} name:#{app.name} acctType:#{app.account.accountType} acctPattern:#{app.account.pattern}"

  robot.respond /(newrelic|nr) apps errors$/i, (msg) ->
    requestAll 'applications.json', '', (err, json, account) ->
      if err
        msg.send "Failed: #{err.message}"
      else
        result = (item for item in json.applications when item.error_rate > 0)
        if result.length > 0
          msg.send plugin.apps result, config
        else
          msg.send "No applications in account #{account.pattern} with errors."

  robot.respond /(newrelic|nr) ktrans$/i, (msg) ->
    requestAllPro 'key_transactions.json', '', (err, json, account) ->
      if err
        msg.send "Failed: #{err.message}"
      else
        msg.send plugin.ktrans json.key_transactions, config

  robot.respond /(newrelic|nr) servers$/i, (msg) ->
    requestAll 'servers.json', '', (err, json, account) ->
      if err
        msg.send "Failed: #{err.message}"
      else
        msg.send plugin.servers json.servers, config

  robot.respond /(newrelic|nr) users$/i, (msg) ->
    requestAll 'users.json', '', (err, json, account) ->
      if err
        msg.send "Failed: #{err.message}"
      else
        msg.send "Account: #{account.pattern}"
        msg.send plugin.users json.users, config

  robot.respond /(newrelic|nr) apps name ([\s\S]+)$/i, (msg) ->
    pattern = msg.match[2]
    data = encodeURIComponent('filter[name]') + '=' +  encodeURIComponent(pattern)
    requestToPattern pattern, 'applications.json', data, (err, json, account) ->
      if err
        msg.send "Failed: #{err.message}"
      else
        msg.send plugin.apps filterApps(account, json.applications, pattern), config

  robot.respond /(newrelic|nr) apps hosts ([0-9]+)$/i, (msg) ->
    id = parseInt(msg.match[2].trim())
    # use lookup table to decide which account to use for the id
    accountsByAppId id, (account) ->
      request account, "applications/#{msg.match[2]}/hosts.json", '', (err, json, account) ->
        if err
          msg.send "Failed: #{err.message}"
        else
          msg.send plugin.hosts json.application_hosts, config

  robot.respond /(newrelic|nr) apps hostsbyname (.+)$/i, (msg) ->
    pattern = msg.match[2].trim()
    data = encodeURIComponent('filter[name]') + '=' +  encodeURIComponent(pattern)
    accountsByPattern pattern, (account) ->
      request account, 'applications.json', data, (err, json, account) ->
        if err
          msg.send "Failed: #{err.message}"
        else
          for app in filterApps(account, json.applications, pattern)
            request account, "applications/#{app.id}/hosts.json", '', (err, json, account) ->
              if err
                msg.send "Failed: #{err.message}"
              else
                msg.send plugin.hosts json.application_hosts, config

  robot.respond /(newrelic|nr) apps instances ([0-9]+)$/i, (msg) ->
    id = parseInt(msg.match[2].trim())
    accountsByAppId id, (account) ->
      request account, "applications/#{msg.match[2]}/instances.json", '', (err, json, account) ->
        if err
          msg.send "Failed: #{err.message}"
        else
          msg.send plugin.instances json.application_instances, config

  robot.respond /(newrelic|nr) apps instancesbyname (.+)$/i, (msg) ->
    pattern = msg.match[2].trim()
    data = encodeURIComponent('filter[name]') + '=' +  encodeURIComponent(pattern)
    accountsByPattern pattern, (account) ->
      request account, 'applications.json', data, (err, json, account) ->
        if err
          msg.send "Failed: #{err.message}"
        else
          for app in filterApps(account, json.applications, pattern)
            request account, "applications/#{app.id}/instances.json", '', (err, json, account) ->
              if err
                msg.send "Failed: #{err.message}"
              else
                msg.send plugin.hosts json.application_instances, config

  robot.respond /(newrelic|nr) ktrans id ([0-9]+)$/i, (msg) ->
    id = parseInt(msg.match[2].trim())
    requestAllPro "key_transactions/#{msg.match[2]}.json", '', (err, json, account) ->
      if err
        msg.send "Failed: #{err.message}"
      else
        msg.send plugin.ktran json.key_transaction, config

  robot.respond /(newrelic|nr) servers name ([a-zA-Z0-9\-.]+)$/i, (msg) ->
    data = encodeURIComponent('filter[name]') + '=' +  encodeURIComponent(msg.match[2])
    # TODO: name filtering for servers on lite accounts
    requestAllPro 'servers.json', data, (err, json, account) ->
      if err
        msg.send "Failed: #{err.message}"
      else
        msg.send plugin.servers json.servers, config

  robot.respond /(newrelic|nr) users email ([a-zA-Z0-9.@]+)$/i, (msg) ->
    pattern = msg.match[2].trim()
    data = encodeURIComponent('filter[email]') + '=' +  encodeURIComponent(pattern)
    requestAll 'users.json', data, (err, json, account) ->
      if err
        msg.send "Failed: #{err.message}"
      else
        msg.send "Account: #{account.pattern}"
        msg.send plugin.users filterUsers(account, json.users, pattern), config

plugin.apps = (apps, opts = {}) ->
  up = opts.up || "UP"
  down = opts.down || "DN"

  lines = apps.map (a) ->
    line = []
    app_summary = a.application_summary || {}
    usr_summary = a.end_user_summary || {}

    if a.reporting
      line.push up
    else
      line.push down

    line.push "#{a.name} (#{a.id})"

    if isFinite(app_summary.response_time)
      line.push "SrvRes:#{app_summary.response_time}ms"

    if isFinite(app_summary.throughput)
      line.push "SrvRPM:#{app_summary.throughput}"

    if isFinite(app_summary.apdex_score)
      line.push "SrvApdex:#{app_summary.apdex_score}"

    if isFinite(app_summary.error_rate)
      line.push "Err:#{app_summary.error_rate}%"

    if isFinite(usr_summary.response_time)
      line.push "UsrRes:#{usr_summary.response_time}s"

    if isFinite(usr_summary.throughput)
      line.push "UsrRPM:#{usr_summary.throughput}"

    if isFinite(usr_summary.apdex_score)
      line.push "UsrApdex:#{usr_summary.apdex_score}"

    if isFinite(app_summary.host_count)
      line.push "Hosts:#{app_summary.host_count}"

    if isFinite(app_summary.instance_count)
      line.push "Instances:#{app_summary.instance_count}"

    line.join "  "

  lines.join("\n")

plugin.hosts = (hosts, opts = {}) ->

  lines = hosts.map (h) ->
    line = []
    summary = h.application_summary || {}

    line.push h.application_name
    line.push h.host

    if isFinite(summary.response_time)
      line.push "Res:#{summary.response_time}ms"

    if isFinite(summary.throughput)
      line.push "RPM:#{summary.throughput}"

    if isFinite(summary.error_rate)
      line.push "Err:#{summary.error_rate}%"

    line.join "  "

  lines.join("\n")

plugin.instances = (instances, opts = {}) ->

  lines = instances.map (i) ->
    line = []
    summary = i.application_summary || {}

    line.push i.application_name
    line.push i.host

    if isFinite(summary.response_time)
      line.push "Res:#{summary.response_time}ms"

    if isFinite(summary.throughput)
      line.push "RPM:#{summary.throughput}"

    if isFinite(summary.error_rate)
      line.push "Err:#{summary.error_rate}%"

    line.join "  "

  lines.join("\n")

plugin.ktrans = (ktrans, opts = {}) ->

  lines = ktrans.map (k) ->
    line = []
    a_summary = k.application_summary || {}
    u_summary = k.end_user_summary || {}

    line.push "#{k.name} (#{k.id})"

    if isFinite(a_summary.response_time)
      line.push "Res:#{a_summary.response_time}ms"

    if isFinite(u_summary.response_time)
      line.push "URes:#{u_summary.response_time}ms"

    if isFinite(a_summary.throughput)
      line.push "RPM:#{a_summary.throughput}"

    if isFinite(u_summary.throughput)
      line.push "URPM:#{u_summary.throughput}"

    if isFinite(a_summary.error_rate)
      line.push "Err:#{a_summary.error_rate}%"

    line.join "  "

  lines.join("\n")

plugin.ktran = (ktran, opts = {}) ->

  result = [ktran]

  lines = result.map (t) ->
    line = []
    a_summary = t.application_summary || {}

    line.push t.name

    if isFinite(a_summary.response_time)
      line.push "Res:#{a_summary.response_time}ms"

    if isFinite(a_summary.throughput)
      line.push "RPM:#{a_summary.throughput}"

    if isFinite(a_summary.error_rate)
      line.push "Err:#{a_summary.error_rate}%"

    line.join "  "

  lines.join("\n")

plugin.servers = (servers, opts = {}) ->
  up = opts.up || "UP"
  down = opts.down || "DN"

  lines = servers.map (s) ->
    line = []
    summary = s.summary || {}

    if s.reporting
      line.push up
    else
      line.push down

    line.push "#{s.name} (#{s.id})"

    if isFinite(summary.cpu)
      line.push "CPU:#{summary.cpu}%"

    if isFinite(summary.memory)
      line.push "Mem:#{summary.memory}%"

    if isFinite(summary.fullest_disk)
      line.push "Disk:#{summary.fullest_disk}%"

    line.join "  "

  lines.join("\n")

plugin.users = (users, opts = {}) ->

  lines = users.map (u) ->
    line = []

    line.push "#{u.first_name} #{u.last_name}"
    line.push "Email: #{u.email}"
    line.push "Role: #{u.role}"

    line.join "  "

  lines.join("\n")

module.exports = plugin
