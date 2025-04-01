# Synthesizer V Studio MCP Server

MCP server for [Synthesizer V Studio](https://dreamtonics.com/synthesizerv/).

## Installation

### 1. Configure Synthesizer V Studio

TBD

### 2. Configure MCP client

To use with Claude Desktop, add the server config:

On MacOS: `~/Library/Application Support/Claude/claude_desktop_config.json`

```json
{
  "mcpServers": {
    "SynthesizerVStudioMCP": {
      "command": "/path/to/node",
      "args": [
        "/path/to/svstudio-mcp/build/index.js"
      ]
    }
  }
}
```

## Demo

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
