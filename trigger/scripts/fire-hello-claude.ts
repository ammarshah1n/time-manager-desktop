import { tasks } from "@trigger.dev/sdk/v3";

const handle = await tasks.trigger("hello-claude", { probe_text: "Say 'wave1-2-verified' in one word." });
console.log("Triggered:", handle.id, "publicAccessToken:", handle.publicAccessToken?.slice(0, 20) + "...");
