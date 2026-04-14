export interface LogContext {
  function_name: string;
  executive_id?: string;
  step?: string;
}

export function createRequestLogger(functionName: string) {
  const request_id = crypto.randomUUID();
  const start = Date.now();
  
  return {
    request_id,
    info(step: string, data?: Record<string, unknown>) {
      console.log(JSON.stringify({ request_id, function_name: functionName, step, duration_ms: Date.now() - start, ...data }));
    },
    error(step: string, error: unknown, data?: Record<string, unknown>) {
      const message = error instanceof Error ? error.message : String(error);
      const stack = error instanceof Error ? error.stack : undefined;
      console.error(JSON.stringify({ request_id, function_name: functionName, step, error: message, stack, duration_ms: Date.now() - start, ...data }));
    },
  };
}
