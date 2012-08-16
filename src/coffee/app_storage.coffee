logger = new Util.Logger('Life::AppStorage','debug')
logger.debug("loading app_storage.js...")

class AppStorage
  constructor: ->
    @logger = logger
    file = Components.classes["@mozilla.org/file/directory_service;1"]
                         .getService(Components.interfaces.nsIProperties)
                         .get("ProfD", Components.interfaces.nsIFile)
    file.append("life.sqlite")
    logger.debug("Opening database: " + file.path)
    storageService = Components.classes["@mozilla.org/storage/service;1"]
                            .getService(Components.interfaces.mozIStorageService)
    try
      @db = storageService.openDatabase(file)

 
      # structure
      @db.beginTransaction()

      if !@db.tableExists("simple")
        @db.createTable("simple","k TEXT PRIMARY KEY, v TEXT")
        @db.executeSimpleSQL("CREATE UNIQUE INDEX simple_by_k ON simple (k)")

      if !@db.tableExists("objects")
        fields = [
          "object_id TEXT PRIMARY KEY",
          "parent_id TEXT",
          "from_id TEXT",
          "tag TEXT",
          "date INTEGER",
          "serialized TEXT",
        ]
        @db.createTable("objects", fields.join(", "))
        @db.executeSimpleSQL("CREATE UNIQUE INDEX objects_by_object_id ON objects (object_id)")
        @db.executeSimpleSQL("CREATE INDEX objects_by_parent_id ON objects (parent_id)")
        @db.executeSimpleSQL("CREATE INDEX objects_by_tag_and_date ON objects (tag, date)")
        @db.executeSimpleSQL("CREATE INDEX objects_by_tag_and_from_id ON objects (tag, from_id)")
      @db.commitTransaction()

      # statements
      @st_get_simple = @db.createStatement("SELECT v FROM simple WHERE simple.k = :k")
      @st_put_simple = @db.createStatement("INSERT OR REPLACE INTO simple (k,v) VALUES (:k,:v)")
      @st_insert_object = @db.createStatement("INSERT OR REPLACE INTO objects (object_id,from_id,parent_id,date,serialized,tag) VALUES (:object_id,:from_id,:parent_id,:date,:serialized,:tag);")
      @st_get_object = @db.createStatement("SELECT serialized FROM objects WHERE object_id = :object")
      @st_objects_by_parent_id= @db.createStatement("SELECT object_id FROM objects WHERE parent_id = :parent_id AND date < :before ORDER BY date DESC LIMIT :limit")
      @st_objects_by_parent_id_and_tag= @db.createStatement("SELECT object_id FROM objects WHERE parent_id = :parent_id AND tag = :tag AND date < :before ORDER BY date DESC LIMIT :limit")
      @st_objects_by_parent_id_and_tag_and_from_id = @db.createStatement("SELECT object_id FROM objects WHERE parent_id = :parent_id AND tag = :tag AND from_id = :from_id AND date < :before ORDER BY date DESC LIMIT :limit")
      @st_objects_by_tag= @db.createStatement("SELECT object_id FROM objects WHERE tag = :tag AND date < :before ORDER BY date DESC LIMIT :limit")
      @st_objects_by_tag_and_from_id= @db.createStatement("SELECT object_id FROM objects WHERE tag = :tag AND from_id = :from_id AND date < :before ORDER BY date DESC LIMIT :limit")

    catch e
      logger.error("WTF!  Error opening application database: #{@db.lastError}",e)

 
  get: (k)->
    try
      @st_get_simple.params.k = k
      while @st_get_simple.step()
        result = @st_get_simple.row.v
      return result
    catch e
      logger.error("error on get from application databasee: #{@db.lastError}",e)
    return null
    

  put: (k,v)->
    try
      @db.beginTransaction()
      @st_put_simple.params.k = k
      @st_put_simple.params.v = v
      while @st_put_simple.step()
        1
      @db.commitTransaction()
      true
    catch e
      logger.error("failed to put simple storage",e)
      @db.rollbackTransaction()
      false


  get_object: (id)->
    @logger.debug("get_object: id=#{id}")
    @st_get_object.params.object = id
    obj = undefined
    while(@st_get_object.step())
      obj = @objify(@st_get_object.row.serialized)
      if(!obj)
        @logger.debug("getData: No serialized found for id: " + id)
        obj = {}
    return obj
 
  # tag: "", from_id: "", parent_id: "", before: N, limit: N
  list_objects:  (options={})->
    if options.parent_id?
      if options.from_id? && options.tag?
        st = @st_objects_by_parent_id_and_tag_and_from_id
        st.params.from_id = options.from_id
        st.params.tag = options.tag
      else if options.tag?
        st = @st_objects_by_parent_id_and_tag
        st.params.tag = options.tag
      else
        st = @st_objects_by_parent_id
      st.params.parent_id = options.parent_id

    else if options.from_id? && options.tag?
      st = @st_objects_by_tag_and_from_id
      st.params.tag = options.tag
      st.params.from_id = options.from_id

    else if options.tag?
      st = @st_objects_by_tag
      st.params.tag = options.tag

    else
      throw "Invalid options for list_objects: #{options.toSource()}"
   
    st.params.before = options.before ||= (Math.pow(2,62) - 1)
    st.params.limit = options.limit ||= 100

    objects = []
    while(st.step())
      objects.push(@get_object(st.row.object_id))
    logger.debug("list_objects w/ options: #{options.toSource()} matched #{objects.length} objects.")
    return objects

  rawput_object: (obj)->
    @st_insert_object.params.object_id = obj.id
    @st_insert_object.params.tag = obj.tag
    @st_insert_object.params.date = obj.date || new Date().getTime()
    @st_insert_object.params.from_id = obj.from || null
    @st_insert_object.params.parent_id = obj.parent_id || null
    @st_insert_object.params.serialized = @stringify(obj)
    @logger.debug("inserting object: " + obj.toSource())
    while @st_insert_object.step()
      1

  put_object: (obj)->
    try
      @db.beginTransaction()
      @rawput_object(obj)
      @db.commitTransaction()
      true
    catch e
      @logger.error("error inserting object",e)
      @db.rollbackTransaction()
      false

  stringify: (obj)->JSON.stringify(obj)
  objify: (str)->JSON.parse(str)

# exports
window.AppStorage = AppStorage
