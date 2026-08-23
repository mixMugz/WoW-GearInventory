-- GearInventory/Addons/exportimport.lua
-- Export and import logic: encode/decode character data.
-- Uses CBOR (binary) + Base64 via C_EncodingUtil — no manual type conversions needed.
-- UI (StaticPopupDialogs, buttons) lives in ui.lua.

local addonName, GI = ...

-- Import string header: "GI:v<format>:<KIND>:<base64>".
-- The version is parsed rather than compared as one fixed string, so a string
-- from another version can be reported as such instead of as plain garbage.
local FORMAT_VERSION = 1
local PREFIX_FULL    = "GI:v" .. FORMAT_VERSION .. ":FULL:"
local PREFIX_CHAR    = "GI:v" .. FORMAT_VERSION .. ":CHAR:"

-- Serializes value to CBOR → Deflate → Base64, prepends prefix.
-- Returns encoded string, or nil + error message on failure.
local function Encode(value, prefix)
  local ok, cbor = pcall(C_EncodingUtil.SerializeCBOR, value)
  if not ok or not cbor then return nil, tostring(cbor) end
  local ok2, compressed = pcall(C_EncodingUtil.CompressString, cbor,
    Enum.CompressionMethod.Deflate, Enum.CompressionLevel.OptimizeForSize)
  if not ok2 or not compressed then return nil, tostring(compressed) end
  local ok3, b64 = pcall(C_EncodingUtil.EncodeBase64, compressed)
  if not ok3 or not b64 then return nil, tostring(b64) end
  return prefix .. b64
end

-- ─── Public: Export ───────────────────────────────────────────────────────────

-- Returns an encoded string containing all saved characters, or nil + err on failure.
function GI.ExportAll()
  if not GI.db or not GI.db.characters then return nil, "no db" end
  return Encode(GI.db.characters, PREFIX_FULL)
end

-- Returns an encoded string for a single character (all specs), or nil + err on failure.
function GI.ExportCharacter(charKey)
  if not GI.db or not GI.db.characters then return nil, "no db" end
  local data = GI.db.characters[charKey]
  if not data then return nil, "no char" end
  return Encode({ key = charKey, data = data }, PREFIX_CHAR)
end

-- ─── Public: Import ───────────────────────────────────────────────────────────

-- A charKey is "Name-Realm" as written by the scan. Anything carrying escape
-- codes or of absurd length did not come from us: it must reach neither the DB
-- nor the chat frame, where "|" sequences would be interpreted as markup.
local function IsValidCharKey(key)
  return type(key) == "string"
     and #key >= 3 and #key <= 128
     and not key:find("|", 1, true)
     and key:find("-", 2, true) ~= nil
end

-- Minimum shape of one stored character. Fields below this level repair
-- themselves on that character's next scan, so checking them here buys nothing.
local function IsValidCharData(data)
  if type(data) ~= "table" then return false end
  if type(data.character) ~= "table" then return false end
  if data.gear ~= nil and type(data.gear) ~= "table" then return false end
  return true
end

-- Parses an import string. Returns: importType, data, conflicts, err
--   importType  = "full" | "char"
--   data        = decoded table (types preserved by CBOR, no normalization needed)
--   conflicts   = list of charKeys already present in DB (may be overwritten)
--   err         = "empty" | "prefix" | "version" | "decode" | "decompress"
--                 | "deserialize" | "shape"; other returns are nil when set
function GI.ParseImport(str)
  if not str or str == "" then
    return nil, nil, nil, "empty"
  end

  str = str:match("^%s*(.-)%s*$")  -- trim whitespace

  local ver, kind, b64 = str:match("^GI:v(%d+):(%u+):(.*)$")
  if not ver then
    return nil, nil, nil, "prefix"
  end
  if tonumber(ver) ~= FORMAT_VERSION then
    return nil, nil, nil, "version"
  end
  if kind ~= "FULL" and kind ~= "CHAR" then
    return nil, nil, nil, "prefix"
  end
  local isChar = (kind == "CHAR")

  local ok, compressed = pcall(C_EncodingUtil.DecodeBase64, b64)
  if not ok or not compressed then
    return nil, nil, nil, "decode"
  end

  local ok2, cbor = pcall(C_EncodingUtil.DecompressString, compressed,
    Enum.CompressionMethod.Deflate)
  if not ok2 or not cbor then
    return nil, nil, nil, "decompress"
  end

  local ok3, decoded = pcall(C_EncodingUtil.DeserializeCBOR, cbor)
  if not ok3 or type(decoded) ~= "table" then
    return nil, nil, nil, "deserialize"
  end

  -- The header only proves the string claims to be ours. Validate the payload
  -- before anything is written to the DB or echoed into chat.
  if isChar then
    if not IsValidCharKey(decoded.key) or not IsValidCharData(decoded.data) then
      return nil, nil, nil, "shape"
    end
  else
    local any = false
    for charKey, charData in pairs(decoded) do
      if not IsValidCharKey(charKey) or not IsValidCharData(charData) then
        return nil, nil, nil, "shape"
      end
      any = true
    end
    if not any then
      return nil, nil, nil, "shape"
    end
  end

  -- Collect conflicts (charKeys already in DB, including current player)
  local conflicts = {}
  if isChar then
    local k = decoded.key
    if GI.db and GI.db.characters[k] then
      conflicts[#conflicts + 1] = k
    end
  else
    for charKey in pairs(decoded) do
      if GI.db and GI.db.characters[charKey] then
        conflicts[#conflicts + 1] = charKey
      end
    end
  end

  return isChar and "char" or "full", decoded, conflicts
end

-- Rebuilds one character from GI.DB_FIELDS instead of storing the decoded table
-- as it arrived. Anything the current schema does not name is dropped, so an
-- export written by an older build cannot put a removed field back into the DB.
--
-- The addon is not public yet, so the schema is still free to move and there is
-- deliberately no v1 -> v2 conversion here: an old field is discarded, not
-- translated. Once the format is frozen this is where that conversion would go.
local function Pick(src, fields)
  local out = {}
  for i = 1, #fields do
    local key = fields[i]
    out[key] = src[key]
  end
  return out
end

local function SanitizeCharacter(charData)
  local clean = {
    character = Pick(charData.character or {}, GI.DB_FIELDS.character),
    gear      = {},
  }

  for specID, bucket in pairs(charData.gear or {}) do
    if type(bucket) == "table" then
      local outBucket = Pick(bucket, GI.DB_FIELDS.spec)

      local color = bucket.avgIlvlColor
      if type(color) == "table" then
        outBucket.avgIlvlColor = { r = color.r, g = color.g, b = color.b }
      end

      local slots = {}
      for slotKey, slot in pairs(bucket.slots or {}) do
        -- Slot keys are "s"..slotID strings; a slot without an item ID is nothing.
        if type(slotKey) == "string" and type(slot) == "table" and slot.id then
          slots[slotKey] = Pick(slot, GI.DB_FIELDS.slot)
        end
      end
      outBucket.slots = slots

      clean.gear[specID] = outBucket
    end
  end

  return clean
end

-- Writes one imported character and reports what happened:
--   "new" | "replaced" | "merged" | "skipped"
--
-- The character being played is a special case. Their record and their active
-- spec are live data coming from the running game and must not be replaced — but
-- their *other* specs exist only in the import, and dropping the whole character
-- loses them. So the active spec is kept and the rest are merged in.
local function ApplyOneCharacter(charKey, charData, myKey, skipExisting)
  if type(charKey) ~= "string" or type(charData) ~= "table" then return "skipped" end

  local existing = GI.db.characters[charKey]
  if skipExisting and existing then return "skipped" end

  charData = SanitizeCharacter(charData)

  if charKey ~= myKey or not existing then
    GI.db.characters[charKey] = charData
    return existing and "replaced" or "new"
  end

  local activeSpec = existing.character and existing.character.specID
  local merged = false
  for specID, bucket in pairs(charData.gear or {}) do
    if specID ~= activeSpec then
      existing.gear = existing.gear or {}
      existing.gear[specID] = bucket
      merged = true
    end
  end
  return merged and "merged" or "skipped"
end

-- Writes parsed import data into the DB. Call only after any needed confirmation.
-- skipExisting: if true, characters already in DB are skipped instead of written.
-- Returns: count (new), overwritten (existing ones replaced wholesale), merged
-- (the played character, whose other specs were folded in), skipped, charKey
-- (single-char only), writtenKeys (list of all written charKeys)
function GI.ApplyImport(importType, data, skipExisting)
  if not GI.db or not GI.db.characters then return 0, 0, 0 end

  local myKey = GI.PlayerKey()
  local count, overwritten, merged, skipped = 0, 0, 0, 0
  local writtenKeys = {}

  local function Apply(charKey, charData)
    local result = ApplyOneCharacter(charKey, charData, myKey, skipExisting)
    if result == "new" then
      count = count + 1
    elseif result == "replaced" then
      overwritten = overwritten + 1
    elseif result == "merged" then
      merged = merged + 1
    else
      skipped = skipped + 1
      return
    end
    writtenKeys[#writtenKeys + 1] = charKey
  end

  if importType == "char" then
    Apply(data.key, data.data)
  else
    for charKey, charData in pairs(data) do
      Apply(charKey, charData)
    end
  end

  GI.RefreshCharacterList()
  return count, overwritten, merged, skipped, importType == "char" and data.key or nil, writtenKeys
end
