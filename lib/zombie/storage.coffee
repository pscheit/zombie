# Web Storage, see http://dev.w3.org/html5/webstorage/
core = require("jsdom").dom.level3.core
events = require("jsdom").dom.level3.events


# Storage area. The storage area is shared by multiple documents of the same
# origin. For session storage, they must also share the same browsing context.
class StorageArea
  constructor: ->
    @length =  0
    @items = []
    @storages = []
  # Get key by ordinal position.
  key: (index)->
    i = 0
    for k of @items
      return k if i == index
      ++i
    return
  # Get value from key
  get: (key)->
    entry = @items[key]
    entry[0] if entry
  # Set the value of a key. We also need the source storage (so we don't send
  # it a storage event).
  set: (source, key, value)->
    if entry = @items[key]
      oldValue = entry[0]
      entry[0] = value
    else
      ++@length
      @items[key] = [value]
    @fire source, key, oldValue, value
  # Remove the value at the key. We also need source storage (see set above).
  remove: (source, key)->
    if entry = @items[key]
      oldValue = entry[0]
      --@length
      delete @items[key]
    @fire source, key, oldValue
  # Remove all values. We also need source storage (see set above).
  clear: (source)->
    if @length > 0
      @length = 0
      @items = []
      @fire source
  # Fire a storage event. Fire in all documents that share this storage area,
  # except for the source document.
  fire: (source, key, oldValue, newValue)->
    for [storage, window] in @storages
      continue if storage == source
      event = new StorageEvent(storage, window.location.href, key, oldValue, newValue)
      #process.nextTick -> window.dispatchEvent event, false, false
  # Associate local/sessionStorage and window with this storage area. Used when firing events.
  associate: (storage, window)->
    @storages.push [storage, window]
  dump: ->
    ("#{k} = #{v[0]}" for k,v of @items).join("\n")
        

# Implementation of the Storage interface, used by local and session storage.
class Storage
  constructor: (area, window)->
    area.associate this, window
    @__defineGetter__ "length", -> area.length
    this.key = (index)-> area.key(index)
    this.getItem = (key)-> area.get(key.toString())
    this.setItem = (key, value)-> area.set this, key.toString(), value
    this.removeItem = (key)-> area.remove this, key.toString()
    this.clear = -> area.clear this
    this.dump = -> area.dump()


# Implementation of the StorageEvent.
StorageEvent = (storage, url, key, oldValue, newValue)->
  events.Event.call this, "storage"
  @__defineGetter__ "url", -> url
  @__defineGetter__ "storageArea", -> storage
  @__defineGetter__ "key", -> key
  @__defineGetter__ "oldValue", -> oldValue
  @__defineGetter__ "newValue", -> newValue
Storage.prototype.__proto__ = events.Event.prototype


# Additional error codes defines for Web Storage and not in JSDOM.
core.SECURITY_ERR = 18


# Attach local and session storage to a window.
exports.attach = (browser, window)->
  browser._sessionStorage ?= {}
  window.__defineGetter__ "sessionStorage", ->
    # Each document has a separate sessionStorage object.
    return @document._sessionStorage if @document._sessionStorage
    # Each document origin is a distinct storage area.
    origin = @document.location
    area = browser._sessionStorage[origin.host] ?= new StorageArea()
    @document._sessionStorage = new Storage(area, window)

  browser._localStorage ?= {}
  window.__defineGetter__ "localStorage", ->
    # Each document has a separate localStorage object.
    return @document._localStorage if @document._localStorage
    # Each document origin is a distinct storage area.
    origin = @document.location
    throw new core.DOMException(core.SECURITY_ERR, "No document origin for local stroage") unless origin && origin.protocol && origin.hostname && origin.port
    area = browser._localStorage[origin.host] ?= new StorageArea()
    @document._localStorage = new Storage(area, window)