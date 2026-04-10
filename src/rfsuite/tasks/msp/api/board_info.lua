local Api = {
  command = 4,
  simulatorResponse = { 0x42, 0, 0, 0, 0, 11, 82, 79, 84, 79, 82, 70, 76, 73, 71, 72, 84 } -- Board ID 0x42, Name "ROTORFLIGHT"
}

function Api.parse(buf)
  if type(buf) ~= "table" or #buf < 6 then return nil end
  
  local boardId = tonumber(buf[1]) or 0
  local boardVersion = tonumber(buf[2]) or 0
  local boardType = tonumber(buf[6]) or 0
  local nameLength = tonumber(buf[7]) or 0
  
  -- Parse board name (null-terminated or length-limited)
  local boardName = ""
  if nameLength > 0 and #buf >= (7 + nameLength) then
    for i = 1, nameLength do
      local byte = tonumber(buf[7 + i]) or 0
      if byte ~= 0 then
        boardName = boardName .. string.char(byte)
      end
    end
  end

  if boardName == "" then
    local startIdx = 6
    for i = 6, #buf do
      local b = tonumber(buf[i]) or 0
      if b >= 32 and b <= 126 then
        startIdx = i
        break
      end
    end

    for i = startIdx, #buf do
      local b = tonumber(buf[i]) or 0
      if b == 0 then break end
      if b >= 32 and b <= 126 then
        boardName = boardName .. string.char(b)
      end
    end
  end
  
  return {
    boardId = boardId,
    boardVersion = boardVersion,
    boardType = boardType,
    boardName = boardName
  }
end

return Api
