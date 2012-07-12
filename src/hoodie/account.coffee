#
# Hoodie.Account
#
# write something here ...
#

class Hoodie.Account
  
  # ## Properties
  username    : undefined

  
  # ## Constructor
  #
  constructor : (@hoodie) ->
    
    # handle session
    @username = @hoodie.config.get '_account.username'
    
    # authenticate on next tick
    # window.setTimeout @authenticate
    @on 'signIn',  @_handleSignIn
    @on 'signOut', @_handleSignOut
  
  
  # ## Authenticate
  # 
  # Use this method to assure that the user is authenticated:
  # `hoodie.account.authenticate().done( doSomething ).fail( handleError )`
  authenticate : =>
    defer = @hoodie.defer()
    
    unless @username
      return defer.reject().promise()
      
    if @_authenticated is true
      return defer.resolve(@username).promise()
      
    if @_authenticated is false
      return defer.reject().promise()
    
    # @_authenticated is undefined
    @_authRequest = @hoodie.request 'GET', "/_session"

    @_authRequest.done (response) =>
      if response.userCtx.name
        @_authenticated = true
        @username = response.userCtx.name
        defer.resolve @username
      else
        @_authenticated = false
        delete @username
        @hoodie.trigger 'account:error:unauthenticated'
        defer.reject()
          
    @_authRequest.fail (xhr) ->
      try
        error = JSON.parse(xhr.responseText)
      catch e
        error = error: xhr.responseText or "unknown"
        
      defer.reject(error)
        
    return defer.promise()
    
    
  # ## sign up with username & password
  #
  # uses standard couchDB API to create a new document in _users db.
  # The backend will automatically create a userDB based on the username
  # address.
  #
  signUp : (username, password = '') ->
    defer = @hoodie.defer()
    
    key     = "#{@_prefix}:#{username}"

    data = 
      _id        : key
      name       : username
      type       : 'user'
      roles      : []
      password   : password

    requestPromise = @hoodie.request 'PUT', "/_users/#{encodeURIComponent key}",
      data        : JSON.stringify data
      contentType : 'application/json'
      
    handleSucces = (response) =>
        @hoodie.trigger 'account:signUp', username
        @_doc._rev = response.rev
        @signIn(username, password).then defer.resolve, defer.reject

    requestPromise.then handleSucces, defer.reject
      
    return defer.promise()


  # ## sign in with username & password
  #
  # uses standard couchDB API to create a new user session (POST /_session)
  #
  signIn : (username, password = '') ->
    defer = @hoodie.defer()

    requestPromise = @hoodie.request 'POST', '/_session', 
      data: 
        name      : username
        password  : password
        
    handleSucces = (response) =>
      @hoodie.trigger 'account:signIn', username
      @fetch()
      defer.resolve username, response
    
    requestPromise.then handleSucces, defer.reject
    
    return defer.promise()

  # alias
  login: @::signIn


  # ## change password
  #
  # NOTE: simple implementation, currentPassword is ignored.
  #
  changePassword : (currentPassword = '', newPassword) ->
    defer = @hoodie.defer()
    unless @username
      defer.reject error: "unauthenticated", reason: "not logged in"
      return defer.promise()
    
    key = "#{@_prefix}:#{@username}"
    
    data = $.extend {}, @_doc
    delete data.salt
    delete data.passwordSha
    data.password = newPassword
    
    @hoodie.request 'PUT',  "/_users/#{encodeURIComponent key}",
      data        : JSON.stringify data
      contentType : "application/json"
      success     : (response) =>
        @fetch()
        defer.resolve()
        
      error       : (xhr) ->
        try
          error = JSON.parse(xhr.responseText)
        catch e
          error = error: xhr.responseText or "unknown"
          
        defer.reject(error)


  # ## sign out 
  #
  # uses standard couchDB API to destroy a user session (DELETE /_session)
  #
  # TODO: handle errors
  signOut: ->
    @hoodie.request 'DELETE', '/_session', 
      success : => @hoodie.trigger 'account:signOut'

  # alias
  logout: @::signOut
  
  
  # ## On
  #
  # alias for `hoodie.on`
  on : (event, cb) -> @hoodie.on "account:#{event}", cb
  
  
  # ## db
  #
  # escape user username (or what ever he uses to sign up)
  # to make it a valid couchDB database name
  # 
  #     Converts an username address user name to a valid database name
  #     The character replacement rules are:
  #       [A-Z] -> [a-z]
  #       @ -> $
  #       . -> _
  #     Notes:
  #      can't reverse because _ are valid before the @.
  #
  #
  db : -> 
    @username?.toLowerCase().replace(/@/, "$").replace(/\./g, "_");
    
    
  # ## fetch
  #
  # fetches _users doc from CouchDB and caches it in _doc
  fetch : ->
    defer = @hoodie.defer()
    
    unless @username
      defer.reject error: "unauthenticated", reason: "not logged in"
      return defer.promise()
    
    key = "#{@_prefix}:#{@username}"
    @hoodie.request 'GET', "/_users/#{encodeURIComponent key}",
    
      success     : (response) => 
        @_doc = response
        defer.resolve response
      
      error       : (xhr) ->
        try
          error = JSON.parse(xhr.responseText)
        catch e
          error = error: xhr.responseText or "unknown"
          
        defer.reject(error) 
        
    return defer.promise()
    
    
  # ## destroy
  #
  # destroys a user' account  
  destroy: ->
    @fetch().pipe =>
      key = "#{@_prefix}:#{@username}"
      @hoodie.request 'DELETE', "/_users/#{encodeURIComponent key}?rev=#{@_doc._rev}"


  # ## PRIVATE
  #
  _prefix : 'org.couchdb.user'
  
  # couchDB _users doc
  _doc : {}
  
  #
  _handleSignIn: (@username) =>
    @hoodie.config.set '_account.username', @username
    @_authenticated = true
  
  #
  _handleSignOut: =>
    delete @username
    @hoodie.config.remove '_account.username'
    @_authenticated = false
