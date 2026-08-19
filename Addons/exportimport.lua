-- GearInventory/Addons/exportimport.lua
-- Export and import logic: encode/decode character data.
-- Uses CBOR (binary) + Base64 via C_EncodingUtil — no manual type conversions needed.
-- UI (StaticPopupDialogs, buttons) lives in ui.lua.

local addonName, GI = ...

local PREFIX_FULL = "GI:v1:FULL:"
local PREFIX_CHAR = "GI:v1:CHAR:"

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

-- Parses an import string. Returns: importType, data, conflicts, err
--   importType  = "full" | "char"
--   data        = decoded table (types preserved by CBOR, no normalization needed)
--   conflicts   = list of charKeys already present in DB (may be overwritten)
--   err         = error string if parsing failed (other returns are nil)
function GI.ParseImport(str)
  if not str or str == "" then
    return nil, nil, nil, "empty"
  end

  str = str:match("^%s*(.-)%s*$")  -- trim whitespace

  local isChar, b64
  if str:sub(1, #PREFIX_FULL) == PREFIX_FULL then
    isChar = false
    b64    = str:sub(#PREFIX_FULL + 1)
  elseif str:sub(1, #PREFIX_CHAR) == PREFIX_CHAR then
    isChar = true
    b64    = str:sub(#PREFIX_CHAR + 1)
  else
    return nil, nil, nil, "prefix"
  end

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

  -- Collect conflicts (charKeys already in DB, including current player)
  local myKey = UnitName("player") and GetRealmName()
    and (UnitName("player") .. "-" .. GetRealmName()) or nil
  local conflicts = {}
  if isChar then
    local k = decoded.key
    if k and GI.db and GI.db.characters[k] then
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
  local myKey = UnitName("player") and GetRealmName()
    and (UnitName("player") .. "-" .. GetRealmName()) or nil
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
