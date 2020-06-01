-- Copyright (c) Jérémie N'gadi
--
-- All rights reserved.
--
-- Even if 'All rights reserved' is very clear :
--
--   You shall not use any piece of this software in a commercial product / service
--   You shall not resell this software
--   You shall not provide any facility to install this particular software in a commercial product / service
--   If you redistribute this software, you must link to ORIGINAL repository at https://github.com/ESX-Org/es_extended
--   This copyright should appear in every part of the project code

local db = M('db')

M('serializable')
M('table')

local pass = function(x) return x end

Persist = function(schema, pk)

  local debugName     = debugName or 'PersistBase_' .. schema
  local extDebugName = 'Persist_' .. schema
  local fields        = {}
  local dbfields      = {}
  local pType         = Extends(Serializable, debugName)

  function pType:constructor(data)

    self.super:ctor(data)

    self.__SCHEMA = schema
    self.__PK     = pk

    for k,v in pairs(fields) do
      self:field(k, data[k])
    end

  end

  local set = function(name, field, encode, decode)

    encode                  = encode or pass
    decode                  = decode or pass
    dbfields[#dbfields + 1] = field
    fields[name]            = {data = field, encode = encode, decode = decode}

  end

  pType.define = function(data)
    for i=1, #data, 1 do
      local entry = data[i]
      set(entry.name, entry.field, entry.encode, entry.decode)
    end
  end

  pType.findOne = function(query, cb)

    local queryFields = {}
    local keys        = {}

    for k,v in pairs(fields) do
      keys[#keys + 1] = v.data.name
    end

    for k,v in pairs(query) do
      queryFields[fields[k].data.name] = v
    end

    local sql, data = db.DBQuery().select(keys).from(schema).where(queryFields).escape().build()

    MySQL.Async.fetchAll(sql, data, function(rows)

      if rows[1] == nil then
        cb(nil)
      else

        local row  = rows[1]
        local data = {}

        for k,v in pairs(fields) do
          data[k] = v.decode(row[v.data.name])
        end

        cb(pType.new(data))

      end

    end)

  end

  pType.find = function(query, cb)

    local queryFields = {}
    local keys        = {}

    for k,v in pairs(fields) do
      keys[#keys + 1] = v.data.name
    end

    for k,v in pairs(query) do
      queryFields[fields[k].data.name] = v
    end

    local keys      = table.map(fields, function(e) return e.data.name end)
    local sql, data = db.DBQuery().select(keys).from(schema).where(queryFields).escape().build()

    MySQL.Async.fetchAll(sql, {['@value'] = value}, function(rows)

      cb(table.map(rows, function(e)

        local row  = e
        local data = {}

        for k,v in pairs(fields) do
          data[k] = v.decode(row[v.data.name])
        end

        return pType.new(data)

      end))

    end)

  end

  pType.ensure = function(key, data, cb)

    local id = data[key]

    if id == nil then

      local instance = pType.new(data)

      instance:save(function(id)
        cb(instance)
      end)

    else

      pType.findOne({[key] = id}, function(instance)

        if instance == nil then

          local instance = pType.new(data)

          instance:save(function(id)
            cb(instance)
          end)

        else

          for k,v in pairs(data) do
            instance[k] = v
          end

          cb(instance)

        end

      end)

    end

  end

  function pType:save(cb)

    local serialized = self:serialize()
    local keys       = ''
    local values     = ''
    local update     = ''

    local data   = {
      ['@pk'] = pk,
      ['@id'] = self:getPK(),
    }

    local count = 0

    for k,v in pairs(fields) do

      if serialized[k] ~= nil then

        local escaped    = '@' .. k
        local backticked = '`' .. v.data.name .. '`'

        if count > 0 then
          keys   = keys   .. ', '
          values = values .. ', '
          update = update .. ', '
        end

        keys          = keys   .. backticked
        values        = values .. escaped
        update        = update .. backticked .. '=' .. escaped
        data[escaped] = fields[k].encode(serialized[k])

        count = count + 1

      end

    end

    local sql = 'INSERT INTO `' .. schema .. '` (' .. keys .. ') VALUES (' .. values .. ') ON DUPLICATE KEY UPDATE ' .. update .. '; SELECT LAST_INSERT_ID();'

    MySQL.Async.fetchAll(sql, data, function(rows)

      local id = rows[2][1]['LAST_INSERT_ID()']

      if (id ~= nil) and (self:getPK() == nil) then
        self:setPK(id)
      end

      if cb ~= nil then
        cb(id)
      end

    end)

  end

  function pType:setPK(val)
    self[self.__PK] = val
  end

  function pType:getPK()
    return self[self.__PK]
  end

  on('esx:db:init', function(initTable, extendTable)
    initTable(schema, pk, dbfields)
  end)

  return Extends(pType, extDebugName)

end

