exports = window.chat ?= {}

class IRC5
  constructor: ->
    @$windowContainer = $('#chat')

    @ircResponseHandler = new chat.IRCResponseHandler()
    @chatCommands = new chat.ChatCommands(this)
    @chatCommands.addHandler new chat.DeveloperCommands(this)

    @chanList = new chat.ChannelList()
    @chanList.on 'clicked', (chan) =>
      win = @_getWindowFromChan(chan)
      @switchToWindow win

    @previousNick = undefined
    # TODO: don't let the user do anything until we load settings
    chrome.storage.sync.get 'nick', (settings) =>
      if settings?.nick
        @previousNick = settings.nick

    @systemWindow = new chat.Window('system')
    @switchToWindow @systemWindow
    @winList = [@systemWindow]

    @systemWindow.message '', "Welcome to irciii, a v2 Chrome app."
    @systemWindow.message '', "Type /connect <server> [port] to connect, then /nick <my_nick> and /join <#channel>."
    @systemWindow.message '', "Alt+[0-9] switches windows."

    @status 'hi!'

    @connections = {}

  connect: (server, port = 6667) ->
    name = server # TODO: 'irc.freenode.net' -> 'freenode'
    tries = 0
    while @connections[name]
      name = server + ++tries
    c = new irc.IRC
    c.setPreferredNick @previousNick if @previousNick?

    conn = @connections[name] = {irc:c, name, windows:{}}
    c.on 'connect', => @onConnected conn
    c.on 'disconnect', => @onDisconnected conn
    c.on 'message', (target, type, args...) =>
      @onIRCMessage conn, target, type, args...
    c.on 'joined', (chan) => @onJoined conn, chan
    c.on 'names', (chan, names) => @onNames conn, chan, names
    c.on 'parted', (chan) => @onParted conn, chan
    c.connect(server, port)
    @systemWindow.conn = conn

  onConnected: (conn) ->
    @systemWindow.message '', "Connected to #{conn.name}"
    for chan, win of conn.windows
      win.message '', '(connected)', type:'system'

  onDisconnected: (conn) ->
    @systemWindow.message '', "Disconnected from #{conn.name}"
    for chan, win of conn.windows
      @chanList.disconnect chan
      win.message '', '(disconnected)', type:'system'

  onJoined: (conn, chan) ->
    win = @_createWindowForChannel conn, chan
    win.nicks.clear()
    win.message '', '(You joined the channel)', type:'system'

  _createWindowForChannel: (conn, chan) ->
    if win = conn.windows[chan]
      @chanList.reconnect()
    else
      @chanList.add chan
      win = @makeWin conn, chan
    win

  onNames: (conn, chan, nicks) ->
    if win = conn.windows[chan]
      win.nicks.add(nicks...)

  onParted: (conn, chan) ->
    if win = conn.windows[chan]
      @chanList.disconnect chan
      win.message '', '(You left the channel)', type:'system'

  onIRCMessage: (conn, target, type, args...) =>
    if not target?
      system_handlers[type].apply @systemWindow, [conn].concat(args)
      return

    win = conn.windows[target]
    if not win
      @systemWindow.message conn.name, "unknown message: #{target}(#{type}): #{JSON.stringify args}"
      console.warn "message to unknown target", conn.name, target, type, args
      return

    if not @ircResponseHandler.canHandle type
      console.warn "received unknown message", conn.name, target, type, args
      return

    @ircResponseHandler.setWindow(win)
    @ircResponseHandler.handle type, args...

  system_handlers =
    welcome: (conn, msg) ->
      @message conn.name, msg, type: 'welcome'
    unknown: (conn, cmd) ->
      @message conn.name, cmd.command + ' ' + cmd.params.join(' ')
    nickinuse: (conn, oldnick, newnick, msg) ->
      @message conn.name, "Nickname #{oldnick} already in use: #{msg}"

  makeWin: (conn, chan) ->
    throw new Error("we already have a window for that") if conn.windows[chan]
    win = conn.windows[chan] = new chat.Window(chan)
    win.conn = conn
    win.target = chan
    @winList.push(win)
    win

  status: (status) ->
    if !status
      status = "[#{@currentWindow.conn?.irc.nick}] #{@currentWindow.target}"
    $('#status').text(status)

  switchToWindow: (win) ->
    throw new Error("switching to non-existant window") if not win?
    @currentWindow.detach() if @currentWindow
    win.attachTo @$windowContainer
    @currentWindow = win
    @chanList.select win.target
    @status()

  _getWindowFromChan: (chan) ->
    for win in @winList
      return win if win.target == chan
    undefined

  onTextInput: (text) ->
    if text[0] == '/'
      cmd = text[1..].split(/\s+/)
      type = cmd[0].toLowerCase()
      if @chatCommands.canHandle type
        @chatCommands.handle type, cmd[1..]...
      else
        console.log "no such command"
    else
      @chatCommands.handle 'say', text

exports.IRC5 = IRC5