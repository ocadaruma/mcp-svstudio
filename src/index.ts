#!/usr/bin/env node

/**
 * MCP server for interacting with Synthesizer V Studio.
 * This server provides tools and resources to:
 * - Get information about the current project
 * - Manage tracks and notes
  */

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListResourcesRequestSchema,
  ListToolsRequestSchema,
  ReadResourceRequestSchema,
  ErrorCode,
  McpError,
} from "@modelcontextprotocol/sdk/types.js";
import * as fs from "fs/promises";

// File paths for communication with the Lua script
const COMMAND_FILE = process.env.COMMAND_FILE || "/tmp/mcp-svstudio-command.json";
const RESPONSE_FILE = process.env.RESPONSE_FILE || "/tmp/mcp-svstudio-command-response.json";

// Timeout for waiting for response (in milliseconds)
const RESPONSE_TIMEOUT = 10000;
const RESPONSE_POLL_INTERVAL = 100;

/**
 * Functions for communicating with the Synthesizer V Studio Lua script
 */

// Function to write a command to the command file
async function writeCommand(command: any): Promise<void> {
  try {
    await fs.writeFile(COMMAND_FILE, JSON.stringify(command));
  } catch (error) {
    console.error("Error writing command:", error);
    throw new McpError(ErrorCode.InternalError, "Failed to write command to file");
  }
}

// Function to read response from the response file with timeout
async function readResponse(): Promise<any> {
  const startTime = Date.now();

  while (Date.now() - startTime < RESPONSE_TIMEOUT) {
    try {
      // Check if response file exists
      try {
        await fs.access(RESPONSE_FILE);
      } catch {
        // File doesn't exist yet, wait and try again
        await new Promise(resolve => setTimeout(resolve, RESPONSE_POLL_INTERVAL));
        continue;
      }

      // Read and parse the response
      const responseData = await fs.readFile(RESPONSE_FILE, 'utf-8');

      // Clear the response file
      await fs.writeFile(RESPONSE_FILE, '');

      return JSON.parse(responseData);
    } catch (error) {
      // Wait a bit before trying again
      await new Promise(resolve => setTimeout(resolve, RESPONSE_POLL_INTERVAL));
    }
  }

  throw new McpError(ErrorCode.InternalError, "Timeout waiting for response from Synthesizer V Studio");
}

// Function to execute a command and get the response
async function executeCommand(action: string, params: any = {}): Promise<any> {
  const command = {
    action,
    ...params
  };

  await writeCommand(command);
  return await readResponse();
}

// Type definitions for Synthesizer V Studio data
interface Project {
  name: string;
  path: string;
  tempo: number;
  timeSignature: string;
  trackCount: number;
}

interface Track {
  id: number;
  name: string;
  noteCount: number;
  notes?: Note[];
}

interface Note {
  id: number;
  lyrics: string;
  startTime: number;
  duration: number;
  pitch: number;
  parameters?: { [key: string]: number };
}

/**
 * Create an MCP server with capabilities for resources and tools
 * to interact with Synthesizer V Studio.
 */
const server = new Server(
  {
    name: "mcp-svstudio",
    version: "0.1.0",
  },
  {
    capabilities: {
      resources: {},
      tools: {},
    },
  }
);

/**
 * Handler for listing available resources.
 * Exposes the current project, tracks, and other Synthesizer V Studio data.
 */
server.setRequestHandler(ListResourcesRequestSchema, async () => {
  try {
    // Get tracks to list as resources
    const tracks = await executeCommand("list_tracks");

    const resources = [
      {
        uri: "svstudio://project",
        mimeType: "application/json",
        name: "Current Project",
        description: "Information about the current Synthesizer V Studio project"
      }
    ];

    // Add track resources if available
    if (Array.isArray(tracks)) {
      tracks.forEach(track => {
        resources.push({
          uri: `svstudio://track/${track.id}`,
          mimeType: "application/json",
          name: `Track: ${track.name}`,
          description: `Information about the track "${track.name}"`
        });
      });
    }

    return { resources };
  } catch (error) {
    console.error("Error listing resources:", error);
    // Return empty resources list on error
    return { resources: [] };
  }
});

/**
 * Handler for reading resources.
 * Returns the requested Synthesizer V Studio data.
 */
server.setRequestHandler(ReadResourceRequestSchema, async (request) => {
  try {
    const uri = request.params.uri;

    // Handle project resource
    if (uri === "svstudio://project") {
      const projectInfo = await executeCommand("get_project_info");

      return {
        contents: [{
          uri,
          mimeType: "application/json",
          text: JSON.stringify(projectInfo, null, 2)
        }]
      };
    }

    // Handle track resources
    const trackMatch = uri.match(/^svstudio:\/\/track\/(.+)$/);
    if (trackMatch) {
      const trackId = Number(trackMatch[1]);

      if (isNaN(trackId)) {
        throw new McpError(ErrorCode.InvalidRequest, `Invalid track ID: ${trackMatch[1]}`);
      }

      // Get track notes
      const notes = await executeCommand("get_track_notes", { trackId });

      if (notes.error) {
        throw new McpError(ErrorCode.InvalidRequest, notes.error);
      }

      // Get track info from list_tracks
      const tracks = await executeCommand("list_tracks");
      const track = Array.isArray(tracks) ? tracks.find(t => t.id === trackId) : null;

      if (!track) {
        throw new McpError(ErrorCode.InvalidRequest, `Track with ID ${trackId} not found`);
      }

      // Combine track info with notes
      const trackData = {
        ...track,
        notes
      };

      return {
        contents: [{
          uri,
          mimeType: "application/json",
          text: JSON.stringify(trackData, null, 2)
        }]
      };
    }

    throw new McpError(ErrorCode.InvalidRequest, `Resource not found: ${uri}`);
  } catch (error) {
    if (error instanceof McpError) {
      throw error;
    }

    console.error("Error reading resource:", error);
    throw new McpError(ErrorCode.InternalError, `Error reading resource: ${error instanceof Error ? error.message : "Unknown error"}`);
  }
});

/**
 * Handler for listing available tools.
 * Exposes tools for interacting with Synthesizer V Studio.
 */
server.setRequestHandler(ListToolsRequestSchema, async () => {
  return {
    tools: [
      {
        name: "get_project_info",
        description: "Get information about the current Synthesizer V Studio project",
        inputSchema: {
          type: "object",
          properties: {},
          required: []
        }
      },
      {
        name: "list_tracks",
        description: "List all tracks in the current project",
        inputSchema: {
          type: "object",
          properties: {},
          required: []
        }
      },
      {
        name: "get_track_notes",
        description: "Get all notes in a specific track",
        inputSchema: {
          type: "object",
          properties: {
            trackId: {
              type: "string",
              description: "ID of the track"
            }
          },
          required: ["trackId"]
        }
      },
      {
        name: "add_notes",
        description: "Add one or more notes to a track",
        inputSchema: {
          type: "object",
          properties: {
            trackId: {
              type: "string",
              description: "ID of the track"
            },
            notes: {
              type: "array",
              description: "Array of notes to add",
              items: {
                type: "object",
                properties: {
                  lyrics: {
                    type: "string",
                    description: "Lyrics text for the note"
                  },
                  startTime: {
                    type: "number",
                    description: "Start time in ticks"
                  },
                  duration: {
                    type: "number",
                    description: "Duration in ticks"
                  },
                  pitch: {
                    type: "number",
                    description: "MIDI pitch (0-127)"
                  }
                },
                required: ["lyrics", "startTime", "duration", "pitch"]
              }
            }
          },
          required: ["trackId", "notes"]
        }
      },
      {
        name: "add_track",
        description: "Add a new track to the project",
        inputSchema: {
          type: "object",
          properties: {
            name: {
              type: "string",
              description: "Name of the new track"
            }
          },
          required: []
        }
      },
      {
        name: "edit_notes",
        description: "Edit one or more notes",
        inputSchema: {
          type: "object",
          properties: {
            trackId: {
              type: "string",
              description: "ID of the track"
            },
            notes: {
              type: "array",
              description: "Array of notes to edit",
              items: {
                type: "object",
                properties: {
                  id: {
                    type: "number",
                    description: "The ID of the note"
                  },
                  lyrics: {
                    type: "string",
                    description: "Lyrics text for the note"
                  },
                  startTime: {
                    type: "number",
                    description: "Start time in ticks"
                  },
                  duration: {
                    type: "number",
                    description: "Duration in ticks"
                  },
                  pitch: {
                    type: "number",
                    description: "MIDI pitch (0-127)"
                  }
                },
                required: ["id"]
              }
            }
          },
          required: ["trackId", "notes"]
        }
      },
    ]
  };
});

/**
 * Handler for calling tools.
 * Implements the functionality for each tool.
 */
server.setRequestHandler(CallToolRequestSchema, async (request) => {
  try {
    switch (request.params.name) {
      case "get_project_info": {
        const projectInfo = await executeCommand("get_project_info");

        return {
          content: [{
            type: "text",
            text: JSON.stringify(projectInfo, null, 2)
          }]
        };
      }

      case "list_tracks": {
        const tracks = await executeCommand("list_tracks");

        return {
          content: [{
            type: "text",
            text: JSON.stringify(tracks, null, 2)
          }]
        };
      }

      case "get_track_notes": {
        const args = request.params.arguments as any;
        const trackId = Number(args.trackId);

        if (isNaN(trackId)) {
          return {
            content: [{
              type: "text",
              text: "Error: Invalid track ID"
            }],
            isError: true
          };
        }

        const notes = await executeCommand("get_track_notes", { trackId });

        if (notes.error) {
          return {
            content: [{
              type: "text",
              text: `Error: ${notes.error}`
            }],
            isError: true
          };
        }

        return {
          content: [{
            type: "text",
            text: JSON.stringify(notes, null, 2)
          }]
        };
      }

      case "add_notes": {
        const args = request.params.arguments as any;
        const trackId = Number(args.trackId);

        if (isNaN(trackId)) {
          return {
            content: [{
              type: "text",
              text: "Error: Invalid track ID"
            }],
            isError: true
          };
        }

        if (!Array.isArray(args.notes) || args.notes.length === 0) {
          return {
            content: [{
              type: "text",
              text: "Error: No notes provided"
            }],
            isError: true
          };
        }

        const result = await executeCommand("add_notes", {
          trackId,
          notes: args.notes.map((note: any) => ({
            lyrics: String(note.lyrics),
            startTime: Number(note.startTime),
            duration: Number(note.duration),
            pitch: Number(note.pitch)
          }))
        });

        if (result.error) {
          return {
            content: [{
              type: "text",
              text: `Error: ${result.error}`
            }],
            isError: true
          };
        }

        return {
          content: [{
            type: "text",
            text: result.message || `${args.notes.length} notes added successfully`
          }]
        };
      }

      case "edit_notes": {
        const args = request.params.arguments as any;
        const trackId = Number(args.trackId);

        if (isNaN(trackId)) {
          return {
            content: [{
              type: "text",
              text: "Error: Invalid track ID"
            }],
            isError: true
          };
        }

        if (!Array.isArray(args.notes) || args.notes.length === 0) {
          return {
            content: [{
              type: "text",
              text: "Error: No notes provided"
            }],
            isError: true
          };
        }

        const result = await executeCommand("edit_notes", {
          trackId,
          notes: args.notes.map((note: any) => ({
            id: Number(note.id),
            lyrics: note.lyrics && String(note.lyrics),
            startTime: note.startTime && Number(note.startTime),
            duration: note.duration && Number(note.duration),
            pitch: note.pitch && Number(note.pitch)
          }))
        });

        if (result.error) {
          return {
            content: [{
              type: "text",
              text: `Error: ${result.error}`
            }],
            isError: true
          };
        }

        return {
          content: [{
            type: "text",
            text: result.message || `${args.notes.length} notes edited successfully`
          }]
        };
      }

      case "add_track": {
        const args = request.params.arguments as any;

        const params: any = {
          name: args.name || "New Track"
        };

        const result = await executeCommand("add_track", params);

        if (result.error) {
          return {
            content: [{
              type: "text",
              text: `Error: ${result.error}`
            }],
            isError: true
          };
        }

        return {
          content: [{
            type: "text",
            text: result.message || `Track "${params.name}" added successfully with ID ${result.trackId}`
          }]
        };
      }

      default:
        return {
          content: [{
            type: "text",
            text: `Error: Unknown tool "${request.params.name}"`
          }],
          isError: true
        };
    }
  } catch (error) {
    console.error("Error executing command:", error);

    return {
      content: [{
        type: "text",
        text: `Error: ${error instanceof Error ? error.message : "Unknown error"}`
      }],
      isError: true
    };
  }
});

/**
 * Start the server using stdio transport.
 */
async function main() {
  // Log server startup for debugging
  console.error("Starting Synthesizer V Studio MCP server...");

  // Initialize communication files
  try {
    // Clear any existing command file
    await fs.writeFile(COMMAND_FILE, "");

    // Start the MCP server
    const transport = new StdioServerTransport();
    await server.connect(transport);

    console.error("Synthesizer V Studio MCP server running");
  } catch (error) {
    console.error("Error initializing server:", error);
    process.exit(1);
  }
}

main().catch((error) => {
  console.error("Server error:", error);
  process.exit(1);
});
