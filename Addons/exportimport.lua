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

-- Writes parsed import data into the DB. Call only after any needed confirmation.
-- The current player's character is always skipped — live data must not be overwritten.
-- skipExisting: if true, characters already in DB are skipped instead of overwritten.
-- Returns: count (imported new), overwritten (replaced existing), skipped (skipped due to current player or existing), charKey (single-char only), writtenKeys (list of all written charKeys)
function GI.ApplyImport(importType, data, skipExisting)
  if not GI.db or not GI.db.characters then return 0, 0, 0 end
  local myKey = GI.PlayerKey()
  local count, overwritten, skipped = 0, 0, 0
  local writtenKeys = {}
  if importType == "char" then
    local key = data.key
    if key == myKey then
      skipped = 1
    elseif skipExisting and GI.db.characters[key] then
      skipped = 1
    elseif key and data.data then
      if GI.db.characters[key] then overwritten = 1 else count = 1 end
      GI.db.characters[key] = data.data
      writtenKeys[#writtenKeys + 1] = key
    end
  else
    for charKey, charData in pairs(data) do
      if charKey == myKey then
        skipped = skipped + 1
      elseif skipExisting and GI.db.characters[charKey] then
        skipped = skipped + 1
      else
        if GI.db.characters[charKey] then overwritten = overwritten + 1 else count = count + 1 end
        GI.db.characters[charKey] = charData
        writtenKeys[#writtenKeys + 1] = charKey
      end
    end
  end
  GI.RefreshCharacterList()
  return count, overwritten, skipped, importType == "char" and data.key or nil, writtenKeys
end
