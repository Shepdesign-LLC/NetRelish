export type { Database } from "./database.types";

import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "./database.types";

export type NetRelishClient = SupabaseClient<Database>;

/**
 * The one place a Supabase client is constructed. Never inline createClient
 * elsewhere — three clients sharing one contract is the point of this package.
 */
export function createNetRelishClient(
  url: string,
  anonKey: string,
): NetRelishClient {
  return createClient<Database>(url, anonKey);
}
