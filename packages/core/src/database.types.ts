// GENERATED FILE — do not hand-edit.
// Regenerate with the Supabase MCP `generate_typescript_types` tool against
// project qiyqlbaggqthcuxslwyk, or `supabase gen types typescript --project-id qiyqlbaggqthcuxslwyk`.

export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.15"
  }
  public: {
    Tables: {
      embeddings: {
        Row: {
          created_at: string
          item_id: string
          model: string
          user_id: string
          vector: string
        }
        Insert: {
          created_at?: string
          item_id: string
          model: string
          user_id: string
          vector: string
        }
        Update: {
          created_at?: string
          item_id?: string
          model?: string
          user_id?: string
          vector?: string
        }
        Relationships: [
          {
            foreignKeyName: "embeddings_item_id_fkey"
            columns: ["item_id"]
            isOneToOne: true
            referencedRelation: "items"
            referencedColumns: ["id"]
          },
        ]
      }
      item_labels: {
        Row: {
          deleted_at: string | null
          item_id: string
          label_id: string
          updated_at: string
          user_id: string
        }
        Insert: {
          deleted_at?: string | null
          item_id: string
          label_id: string
          updated_at?: string
          user_id: string
        }
        Update: {
          deleted_at?: string | null
          item_id?: string
          label_id?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "item_labels_item_id_fkey"
            columns: ["item_id"]
            isOneToOne: false
            referencedRelation: "items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "item_labels_label_id_fkey"
            columns: ["label_id"]
            isOneToOne: false
            referencedRelation: "labels"
            referencedColumns: ["id"]
          },
        ]
      }
      items: {
        Row: {
          body: string | null
          created_at: string
          deleted_at: string | null
          field_ts: Json
          fts: unknown
          id: string
          jar_id: string | null
          kind: string
          meta: Json | null
          sealed_at: string | null
          title: string
          touched_at: string
          updated_at: string
          url: string | null
          user_id: string
        }
        Insert: {
          body?: string | null
          created_at?: string
          deleted_at?: string | null
          field_ts?: Json
          fts?: unknown
          id: string
          jar_id?: string | null
          kind: string
          meta?: Json | null
          sealed_at?: string | null
          title: string
          touched_at?: string
          updated_at?: string
          url?: string | null
          user_id: string
        }
        Update: {
          body?: string | null
          created_at?: string
          deleted_at?: string | null
          field_ts?: Json
          fts?: unknown
          id?: string
          jar_id?: string | null
          kind?: string
          meta?: Json | null
          sealed_at?: string | null
          title?: string
          touched_at?: string
          updated_at?: string
          url?: string | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "items_jar_id_fkey"
            columns: ["jar_id"]
            isOneToOne: false
            referencedRelation: "jars"
            referencedColumns: ["id"]
          },
        ]
      }
      jars: {
        Row: {
          created_at: string
          deleted_at: string | null
          field_ts: Json
          hue: number
          id: string
          name: string
          sealed_at: string | null
          shelf_life_hours: number | null
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          deleted_at?: string | null
          field_ts?: Json
          hue: number
          id: string
          name: string
          sealed_at?: string | null
          shelf_life_hours?: number | null
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          deleted_at?: string | null
          field_ts?: Json
          hue?: number
          id?: string
          name?: string
          sealed_at?: string | null
          shelf_life_hours?: number | null
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      labels: {
        Row: {
          deleted_at: string | null
          field_ts: Json
          id: string
          name: string
          updated_at: string
          user_id: string
        }
        Insert: {
          deleted_at?: string | null
          field_ts?: Json
          id: string
          name: string
          updated_at?: string
          user_id: string
        }
        Update: {
          deleted_at?: string | null
          field_ts?: Json
          id?: string
          name?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      recipes: {
        Row: {
          deleted_at: string | null
          field_ts: Json
          id: string
          jar_id: string
          name: string
          steps: Json
          updated_at: string
          user_id: string
        }
        Insert: {
          deleted_at?: string | null
          field_ts?: Json
          id: string
          jar_id: string
          name: string
          steps: Json
          updated_at?: string
          user_id: string
        }
        Update: {
          deleted_at?: string | null
          field_ts?: Json
          id?: string
          jar_id?: string
          name?: string
          steps?: Json
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "recipes_jar_id_fkey"
            columns: ["jar_id"]
            isOneToOne: false
            referencedRelation: "jars"
            referencedColumns: ["id"]
          },
        ]
      }
      suggestion_feedback: {
        Row: {
          action: string
          at: string
          deleted_at: string | null
          item_id: string
          jar_id: string
          updated_at: string
          user_id: string
        }
        Insert: {
          action: string
          at?: string
          deleted_at?: string | null
          item_id: string
          jar_id: string
          updated_at?: string
          user_id: string
        }
        Update: {
          action?: string
          at?: string
          deleted_at?: string | null
          item_id?: string
          jar_id?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "suggestion_feedback_item_id_fkey"
            columns: ["item_id"]
            isOneToOne: false
            referencedRelation: "items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "suggestion_feedback_jar_id_fkey"
            columns: ["jar_id"]
            isOneToOne: false
            referencedRelation: "jars"
            referencedColumns: ["id"]
          },
        ]
      }
      tabs: {
        Row: {
          deleted_at: string | null
          field_ts: Json
          id: string
          item_id: string | null
          jar_id: string | null
          opened_at: string
          position: number
          scroll_y: number
          seal_after: string | null
          sealed_at: string | null
          sealed_batch: string | null
          touched_at: string
          updated_at: string
          url: string | null
          user_id: string
        }
        Insert: {
          deleted_at?: string | null
          field_ts?: Json
          id: string
          item_id?: string | null
          jar_id?: string | null
          opened_at?: string
          position?: number
          scroll_y?: number
          seal_after?: string | null
          sealed_at?: string | null
          sealed_batch?: string | null
          touched_at?: string
          updated_at?: string
          url?: string | null
          user_id: string
        }
        Update: {
          deleted_at?: string | null
          field_ts?: Json
          id?: string
          item_id?: string | null
          jar_id?: string | null
          opened_at?: string
          position?: number
          scroll_y?: number
          seal_after?: string | null
          sealed_at?: string | null
          sealed_batch?: string | null
          touched_at?: string
          updated_at?: string
          url?: string | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "tabs_item_id_fkey"
            columns: ["item_id"]
            isOneToOne: false
            referencedRelation: "items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tabs_jar_id_fkey"
            columns: ["jar_id"]
            isOneToOne: false
            referencedRelation: "jars"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      sync_push: {
        Args: { client_synced_at: string; payload: Json }
        Returns: Json
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {},
  },
} as const
