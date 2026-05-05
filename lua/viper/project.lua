local M = {}

-- { [imported_file_uri] = root_uri }
local pinned_to = {}
-- { [root_uri] = { [file_uri] = true } }
local project_files = {}

--- Record that root_uri imports all files in other_uris.
--- Replaces any previous mapping for this root.
function M.setup(root_uri, other_uris)
  -- drop stale reverse-mappings for this root
  if project_files[root_uri] then
    for uri in pairs(project_files[root_uri]) do
      pinned_to[uri] = nil
    end
  end

  project_files[root_uri] = {}
  for _, uri in ipairs(other_uris) do
    pinned_to[uri] = root_uri
    project_files[root_uri][uri] = true
  end
end

--- Return the project root URI for uri, or nil if uri is itself a root
--- or not part of any known project.
function M.root_for(uri)
  return pinned_to[uri]
end

--- Exposed for testing.
function M.clear()
  pinned_to = {}
  project_files = {}
end

return M
