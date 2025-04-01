# Synthesizer V Studio MCP Server

MCP server for [Synthesizer V](https://dreamtonics.com/synthesizerv/) AI Vocal Studio, which allows LLMs to create/edit vocal tracks e.g. adding lyrics to the melody.

## Installation

### Prerequisites

- Node.js (tested with v22)
- Synthesizer V Studio (tested with V2)

### 0. Clone this repo

`git clone https://github.com/ocadaruma/mcp-svstudio.git`

### 1. Configure Synthesizer V Studio

- Copy below two files to Synthesizer V Studio scripts folder (On MacOS with V2 Studio, it's `~/Library/Application Support/Dreamtonics/Synthesizer V Studio 2/scripts` by default)
  * `sv-scripts/StartMCPServerRequestHandler.lua`
  * `sv-scripts/StopMCPServerRequestHandler.lua`
- Run `StartServerRequestHandler` on Synthesizer V Studio
  * From Scripts menu > MCP > StartServerRequestHandler
  * ⚠️ Please do this before configuring MCP client. Otherwise, you will get connection issue.

### 2. Configure MCP client

⚠️ Please run only one MCP server at a time.

Add below config to the MCP server config of your client. (e.g. On MacOS Claude Desktop, it's `~/Library/Application Support/Claude/claude_desktop_config.json` by default)

```json
{
  "mcpServers": {
    "SynthesizerVStudioMCP": {
      "command": "/path/to/node",
      "args": [
        "/path/to/mcp-svstudio/build/index.js"
      ]
    }
  }
}
```

## Example commands

- Sing something (then "Add harmony track")
  * [Demo](https://youtu.be/uMz_mfS3aic)
- Create an EDM vocal track
- Add lyrics to the existing track

## Development

Install dependencies:
```bash
npm install
```

Build the server:
```bash
npm run build
```

For development with auto-rebuild:
```bash
npm run watch
```
