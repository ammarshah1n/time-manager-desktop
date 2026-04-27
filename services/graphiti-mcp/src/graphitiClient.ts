/**
 * Thin HTTP client for the sibling `graphiti` Python service (task 14). Used
 * only when a tool call needs to go through Graphiti's extraction + embedding
 * pipeline (i.e. `add_episode`). Reads bypass this and talk to Neo4j directly.
 */

export interface GraphitiAddEpisodeResponse {
  episode_uuid: string | null;
}

export class GraphitiClient {
  constructor(private readonly baseUrl: string) {}

  async addEpisode(args: {
    name: string;
    episode_body: string;
    source_description?: string;
    reference_time?: string;
    group_id?: string | null;
    source?: "text" | "message" | "json";
  }): Promise<GraphitiAddEpisodeResponse> {
    const res = await fetch(`${this.baseUrl.replace(/\/$/, "")}/episode`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        name: args.name,
        episode_body: args.episode_body,
        source_description: args.source_description ?? "timed",
        reference_time: args.reference_time ?? new Date().toISOString(),
        group_id: args.group_id ?? null,
        source: args.source ?? "text",
      }),
    });
    if (!res.ok) {
      const text = await res.text();
      throw new Error(`graphiti /episode failed ${res.status}: ${text}`);
    }
    return (await res.json()) as GraphitiAddEpisodeResponse;
  }
}
