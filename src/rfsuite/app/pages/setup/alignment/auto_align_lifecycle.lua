local M = {}

function M.capture(runtime, session, signature, armedChanges)
  return { runtime = runtime, generation = runtime and runtime.generation or 0, session = session,
    signature = signature, armedChanges = armedChanges }
end

function M.isCurrent(currentRuntime, loaded, session, signature, connected, armedChanges, token)
  return loaded == true and connected == true and type(token) == "table"
    and currentRuntime == token.runtime and currentRuntime.generation == token.generation and session == token.session
    and signature == token.signature and armedChanges == token.armedChanges
end

function M.invalidate(runtime)
  if type(runtime) ~= "table" then return end
  runtime.generation = (runtime.generation or 0) + 1
end

return M
