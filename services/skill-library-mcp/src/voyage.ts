/**
 * Voyage `voyage-3` embedding client. 1024-dim outputs to match
 * `skills.embedding VECTOR(1024)`.
 *
 * Voyage's REST API: POST https://api.voyageai.com/v1/embeddings
 *   body: { input: string | string[], model: "voyage-3", input_type: "document" | "query" }
 *   response: { data: [{ embedding: number[], index: number }], model, usage: { total_tokens } }
 */

export interface VoyageClient {
  embed(input: string, inputType?: "query" | "document"): Promise<number[]>;
}

export function createVoyageClient(apiKey: string, model = "voyage-3"): VoyageClient {
  return {
    async embed(input: string, inputType: "query" | "document" = "query"): Promise<number[]> {
      const res = await fetch("https://api.voyageai.com/v1/embeddings", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${apiKey}`,
        },
        body: JSON.stringify({ input, model, input_type: inputType }),
      });
      if (!res.ok) {
        const text = await res.text();
        throw new Error(`voyage embed failed ${res.status}: ${text}`);
      }
      const json = (await res.json()) as {
        data: Array<{ embedding: number[]; index: number }>;
      };
      const first = json.data[0];
      if (!first) throw new Error("voyage embed: empty data array");
      return first.embedding;
    },
  };
}
