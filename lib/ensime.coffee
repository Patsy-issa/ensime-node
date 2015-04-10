net = require('net')
exec = require('child_process').exec
fs = require 'fs'
{Subscriber} = require 'emissary'
SwankClient = require './swank-client'
StatusbarView = require './statusbar-view'
{CompositeDisposable} = require 'atom'
{car, cdr, fromLisp} = require './lisp'
{sexpToJObject} = require './swank-extras'
EditorControl = require './editor-control'
{updateEnsimeServer, startEnsimeServer} = require './ensime-startup'
{MessagePanelView, LineMessageView} = require 'atom-message-panel'
{log} = require './utils'


portFile = ->
    loadSettings = atom.getLoadSettings()
    console.log('loadSettings: ' + loadSettings)
    projectPath = atom.project.getPath()
    console.log('project path: ' + projectPath)
    projectPath + '/.ensime_cache/port'


createSwankClient = (portFileLoc, generalHandler) ->
  console.log("portFileLoc: " + portFileLoc)
  port = fs.readFileSync(portFileLoc).toString()
  new SwankClient(port, generalHandler)

###
startEnsime = (portFile) ->
  ensimeLocation = '~/dev/projects/ensime-src/dist'
  #ensimeServerBin = ensimeLocation + '/2.10/bin/server'
  ensimeServerBin = ensimeLocation + '/2.11/bin/server'
  command = 'cd ' + ensimeLocation + '\n' + ensimeServerBin + ' ' + portFile
  console.log("Running command: " + command)
  child = exec(command, (error, stdout, stderr) ->
    console.log('stdout: ' + stdout);
    console.log('stderr: ' + stderr);
    if(error != null)
      console.log('exec error: ' + error);
  )
###


module.exports = Ensime =
  subscriptions: null

  config: {
    ensimeServerVersion: {
      description: 'Version of Ensime server',
      type: 'string',
      default: "0.9.10-SNAPSHOT"
    },
    sbtExec: {
      description: 'Full path to sbt. \'which sbt\'',
      type: 'string',
      default: "/usr/local/bin/sbt"
    },
    JAVA_HOME: {
      description: 'path to JAVA_HOME'
      type: 'string'
      default: '/Library/Java/JavaVirtualMachines/jdk1.8.0_05.jdk/Contents/Home/'
    },
    ensimeServerFlags: {
      description: 'java flags for ensime server startup'
      type: 'string',
      default: ''
    },
    devMode: {
      description: 'Turn on for extra console logging during development',
      type: 'boolean',
      default: false
    },
    runServerDetached: {
      description: "Run the Ensime server as a detached process. Useful while developing"
      type: 'boolean',
      default: false
    }
  }


  activate: (state) ->
    @subscriptions = new CompositeDisposable
    @statusbarView = new StatusbarView()
    @statusbarView.init()


    # Need to have a started server and port file
    @subscriptions.add atom.commands.add 'atom-workspace', "ensime:update-ensime-server", => updateEnsimeServer()
    @subscriptions.add atom.commands.add 'atom-workspace', "ensime:init-project", => @initProject()

    @subscriptions.add atom.commands.add 'atom-workspace', "ensime:start-server", =>
      if not @ensimeServerPid then @ensimeServerPid = startEnsimeServer()
    @subscriptions.add atom.commands.add 'atom-workspace', "ensime:stop-server", =>
      @ensimeServerPid?.kill()

    @subscriptions.add atom.commands.add 'atom-workspace', "ensime:typecheck-all", => @typecheckAll()
    @subscriptions.add atom.commands.add 'atom-workspace', "ensime:typecheck-file", => @typecheckFile()
    @subscriptions.add atom.commands.add 'atom-workspace', "ensime:typecheck-buffer", => @typecheckBuffer()


    @subscriptions.add atom.commands.add 'atom-workspace', "ensime:init-builder", => @initBuilder()
    @subscriptions.add atom.commands.add 'atom-workspace', "ensime:go-to-definition", => @goToDefinitionOfCursor()

    @initMessagePanel()


  deactivate: ->
    @subscriptions.dispose()
    @controlSubscription.dispose()
    @ensimeServerPid?.kill()

  serialize: ->

  generalHandler: (msg) ->
    head = car(msg)
    tail = cdr(msg)
    headStr = head.toString()
    console.log("this: " + this)

    if(headStr == ':compiler-ready')
      @statusbarView.setText('compiler ready…')

    else if(headStr == ':full-typecheck-finished')
      @statusbarView.setText('Full typecheck finished!')

    else if(headStr == ':indexer-ready')
      @statusbarView.setText('indexer ready…')

    else if(headStr == ':clear-all-java-notes')
      @statusbarView.setText('feature todo: clear all java notes')

    else if(headStr == ':clear-all-scala-notes')
      log(":clear-all-scala-notes received")
      @messages.clear()

    else if(headStr.startsWith(':background-message'))
      @statusbarView.setText("#{tail}")

    else if(headStr == ':scala-notes')
      @handleScalaNotes(tail)


  _client: null
  client: ->
    if(@_client) then @_client else
      @_client = createSwankClient(portFile(), (msg) => @generalHandler(msg) )
      @_client

  startEnsime: ->
    startEnsime(portFile())

  initProject: ->
    @client().sendAndThen("(swank:init-project)", (msg) -> )

    # Register an EditorControl for each editor view
    @controlSubscription = atom.workspace.observeTextEditors (editor) =>
      editorView = atom.views.getView(editor)
      editorView.flowController = new EditorControl(editor, @client())




  initMessagePanel: ->
    @messages = new MessagePanelView
        title: 'Ensime'

    @messages.attach()

    @messages.add new LineMessageView
        line: 23
        character: 4
        message: 'You haven\'t had a single drop of coffee since this character'

    @messages.add new LineMessageView
        line: 18
        character: 4
        message: 'You haven\'t had asdf of coffee since this character'

    @messages.add new LineMessageView
        line: 1
        character: 4
        message: 'You haven\'t had a single drop of coffee since this character'

  typecheckAll: ->
    @client().sendAndThen("(swank:typecheck-all)", (msg) ->)

  # typechecks currently open file
  typecheckBuffer: ->
    b = atom.workspace.getActiveTextEditor()?.getBuffer()
    swankMsg = "(swank:typecheck-file \"#{b.getPath()}\" #{JSON.stringify(b.getText())})"
    log("swankMsg: #{swankMsg}")
    @client().sendAndThen(swankMsg, (result) ->)

  typecheckFile: ->
    b = atom.workspace.getActiveTextEditor()?.getBuffer()
    swankMsg = "(swank:typecheck-file \"#{b.getPath()}\")"
    log("swankMsg: #{swankMsg}")
    @client().sendAndThen(swankMsg, (result) ->)

  initBuilder: ->
    #client.write(swankRpc("(swank:builder-init)"))

  goToDefinitionOfCursor: ->
    editor = atom.workspace.getActiveTextEditor()
    textBuffer = editor.getBuffer()
    pos = editor.getCursorBufferPosition()
    @client().goToTypeAtPoint(textBuffer, pos)

  handleScalaNotes: (msg) ->
    array = sexpToJObject msg
    result = array[0]
    notes = result[':notes']

    handleNote = (note) =>
      file = note[':file']
      # for now only handle currently open file.
      textBuffer = atom.workspace.getActiveTextEditor()?.getBuffer()
      if(textBuffer.getPath() == file)
        begOffset = note[':beg']
        pos = textBuffer.positionForCharacterIndex(begOffset)
        @messages.add new LineMessageView
          line: pos.row
          character: pos.column
          message: note[':msg']

    handleNote note for note in notes

  provideLinks: ->
    require('./provide-links-processor')
