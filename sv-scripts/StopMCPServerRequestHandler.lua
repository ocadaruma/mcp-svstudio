STATE_FILE = "/tmp/svstudio-mcp-state.txt"

function getClientInfo()
    return {
        name = "StopServerRequestHandler",
        author = "Haruki Okada",
        category = "MCP",
        versionNumber = 1,
        minEditorVersion = 65540
    }
end

function main()
    local file = io.open(STATE_FILE, "w")
    file:write("terminated")
    file:close()
    SV:finish()
end
